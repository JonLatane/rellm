use std::str::FromStr;

use crate::db_connection::*;
use crate::logic::{adjust_server_media_usage_bytes, update_media_storage_used};
use crate::marshaling::*;
use crate::models;
use crate::protos::{MediaConversion, Permission, Visibility};
use crate::rpcs::get_server_configuration_proto;
use crate::schema;
use crate::schema::media;
use crate::schema::user_access_tokens::dsl as user_access_tokens;
use crate::schema::user_refresh_tokens::dsl as user_refresh_tokens;
use crate::schema::users::dsl as users;
use crate::web::headers::{AuthHeader, ContentTypeHeader, FilenameHeader};
use crate::web::RocketState;
use log::info;
use rocket::fs::NamedFile;
use rocket::http::uri::Host;
use rocket::http::ContentType;

use diesel::*;
use rocket::http::MediaType;
use rocket::{data::ToByteUnit, http::CookieJar, routes, Data, Route, State};

use rocket::http::Status;
use rocket_cache_response::{CacheControl, CacheResponse};
use uuid::Uuid;

lazy_static! {
    pub static ref MEDIA_ENDPOINTS: Vec<Route> = routes![
        create_media_options,
        create_media,
        media_file_options,
        media_file
    ];
}

/// Used to manage CORS for the media upload endpoint.
#[rocket::options("/media")]
pub async fn create_media_options() -> &'static str {
    return "";
}

#[rocket::post("/media", data = "<media>")]
pub async fn create_media(
    media: Data<'_>,
    cookies: &CookieJar<'_>,
    state: &State<RocketState>,
    auth_header: Option<AuthHeader<'_>>,
    content_type_header: ContentTypeHeader<'_>,
    filename_header: FilenameHeader<'_>,
    host: &Host<'_>,
) -> Result<String, (Status, String)> {
    log::info!("create_media");
    let user = get_media_user(None, auth_header, cookies, state).map_err(no_message)?;
    let uuid = Uuid::new_v4();
    let object_storage_path = format!(
        "user/{}@{}-{}/{}-{}",
        user.id.to_proto_id(),
        host.domain().to_string(),
        user.username,
        uuid,
        filename_header.0
    );

    let put_response = state
        .bucket
        .put_object_stream(&mut media.open(250.mebibytes()), &object_storage_path)
        .await
        .map_err(|_| (Status::InternalServerError, String::new()))?;
    let uploaded_bytes = put_response.uploaded_bytes() as i64;

    log::info!(
        "create_media status_code: {:?}, uploaded_bytes: {}",
        put_response.status_code(),
        uploaded_bytes
    );

    if let Some(limit) = user.media_storage_limit_bytes {
        if user.media_storage_bytes_used + uploaded_bytes > limit {
            state.bucket.delete_object(&object_storage_path).await.ok();
            return Err((
                Status::PayloadTooLarge,
                format!(
                    "This upload ({} bytes) would exceed your storage limit ({} of {} bytes used).",
                    uploaded_bytes, user.media_storage_bytes_used, limit
                ),
            ));
        }
    }

    // Same idea as the per-user check above, but against the server-wide cap
    // (`MediaSettings.server_media_allocation_bytes`) -- `server_media_usage_bytes` is a running
    // total (see `logic::server_storage_usage`'s own doc), not necessarily perfectly fresh, but
    // close enough to gate uploads on without an expensive full recompute on every request.
    {
        let mut config_conn = state.pool.get().unwrap();
        if let Ok(server_configuration) = get_server_configuration_proto(&mut config_conn) {
            if let Some(media_settings) = server_configuration.media_settings {
                let server_usage = media_settings.server_media_usage_bytes as i64;
                let server_limit = media_settings.server_media_allocation_bytes as i64;
                if server_usage + uploaded_bytes > server_limit {
                    state.bucket.delete_object(&object_storage_path).await.ok();
                    return Err((
                        Status::PayloadTooLarge,
                        format!(
                            "This upload ({} bytes) would exceed this server's storage limit ({} of {} bytes used).",
                            uploaded_bytes, server_usage, server_limit
                        ),
                    ));
                }
            }
        }
    }

    let content_type = content_type_header.0.to_string();
    let metadata = if content_type.starts_with("video/") {
        models::MediaMetadata {
            video_preview_time_ms: Some(1000),
            ..Default::default()
        }
    } else {
        models::MediaMetadata::default()
    };

    let sizes = vec![models::MediaSize {
        conversion: MediaConversion::Original as i32,
        object_storage_path,
        content_type,
        size_bytes: uploaded_bytes,
        aspect_ratio: None,
    }];

    let mut conn = state.pool.get().unwrap();
    let media = insert_into(media::table)
        .values(&models::NewMedia {
            user_id: Some(user.id),
            name: Some(filename_header.0.to_string()),
            description: None,
            generated: false,
            visibility: Visibility::GlobalPublic.to_string_visibility(),
            metadata: serde_json::to_value(metadata).unwrap(),
            sizes: serde_json::to_value(sizes).unwrap(),
        })
        .get_result::<models::Media>(&mut conn)
        .map_err(|_| (Status::InternalServerError, String::new()))?;

    if let Err(e) = update_media_storage_used(user.id, &mut conn) {
        log::error!(
            "Failed to update media_storage_bytes_used for user {}: {:?}",
            user.id,
            e
        );
    }
    if let Err(e) = adjust_server_media_usage_bytes(&mut conn, uploaded_bytes) {
        log::error!(
            "Failed to adjust server_media_usage_bytes for new media {}: {:?}",
            media.id,
            e
        );
    }

    Ok(media.id.to_proto_id())
}

fn no_message(status: Status) -> (Status, String) {
    (status, String::new())
}

/// Used to manage CORS for the media download endpoint(s).
#[rocket::options("/media/<id>")]
pub async fn media_file_options(id: &str) -> &'static str {
    let _id = id;
    return "";
}

/// Response header `media_file` sets to ask the `CORS` fairing to leave off every
/// `Access-Control-Allow-*` header (and then removes itself) -- see
/// `MediaSettings.block_cors_anonymous_media_access`.
pub const BLOCK_CORS_HEADER: &str = "X-Rellm-Block-CORS";

/// Wraps a responder, optionally tagging it with `BLOCK_CORS_HEADER` and `Vary`ing on the headers
/// that decide whether it's tagged (so a shared cache never serves one viewer's CORS-less anonymous
/// copy to an authenticated one, or vice versa).
pub struct MediaResponse<R> {
    inner: R,
    block_cors: bool,
    vary_on_auth: bool,
}

impl<'r, 'o: 'r, R: rocket::response::Responder<'r, 'o>> rocket::response::Responder<'r, 'o>
    for MediaResponse<R>
{
    fn respond_to(self, request: &'r rocket::Request<'_>) -> rocket::response::Result<'o> {
        let mut response = self.inner.respond_to(request)?;
        if self.block_cors {
            response.set_header(rocket::http::Header::new(BLOCK_CORS_HEADER, "1"));
        }
        if self.vary_on_auth {
            response.set_header(rocket::http::Header::new("Vary", "Authorization, Cookie"));
        }
        Ok(response)
    }
}

#[rocket::get("/media/<id>?<authorization>&<size>")]
pub async fn media_file<'a>(
    id: &str,
    authorization: Option<String>,
    size: Option<String>,
    cookies: &CookieJar<'_>,
    state: &State<RocketState>,
    auth_header: Option<AuthHeader<'_>>,
) -> Result<MediaResponse<CacheResponse<(ContentType, NamedFile)>>, Status> {
    log::info!("media_file: {:?}, size: {:?}", id, size);
    let user = get_media_user(authorization, auth_header, cookies, state).ok();

    let media = load_media_by_id(id, state)?;
    {
        let mut conn = state.pool.get().unwrap();
        let follows_owner = media.visibility == Visibility::Limited.to_string_visibility()
            && match (user.as_ref(), media.user_id) {
                (Some(viewer), Some(owner_id)) => viewer_follows(viewer.id, owner_id, &mut conn),
                _ => false,
            };
        let licensed_globally = crate::rpcs::licensed_media_visible_globally(&mut conn);
        if !media_visible_to_viewer(&media, user.as_ref(), follows_owner, licensed_globally) {
            return Err(Status::NotFound);
        }
    }
    let licensed = media.visibility == Visibility::Licensed.to_string_visibility();
    let has_full_access = !licensed || viewer_has_full_access(&media, user.as_ref(), state);
    let (object_storage_path, content_type) =
        resolve_media_size_for_viewer(&media, size.as_deref(), has_full_access)?;
    let data = load_media_file(object_storage_path, content_type, state).await?;

    // Anonymous requests to servers with `block_cors_anonymous_media_access` get no CORS headers,
    // even for `GLOBAL_PUBLIC` media. (Authenticated requests are unaffected.)
    let block_cors = user.is_none() && {
        let mut conn = state.pool.get().unwrap();
        get_server_configuration_proto(&mut conn)
            .ok()
            .and_then(|c| c.media_settings)
            .is_some_and(|m| m.block_cors_anonymous_media_access)
    };

    // A `LICENSED` item's bytes depend on who's asking, so they must never sit in a shared cache.
    let cache_control = if licensed {
        CacheControl {
            must_revalidate: true,
            ..CacheControl::private(0)
        }
    } else {
        CacheControl {
            must_revalidate: true,
            ..CacheControl::public(3600 * 12)
        }
    };
    Ok(MediaResponse {
        inner: CacheResponse::new(data, cache_control),
        block_cors,
        vary_on_auth: licensed || block_cors,
    })
}

/// Whether `viewer` (`None` if anonymous) may see `media` at all -- the same rules `GetMedia` applies
/// (see `query_visible_media!`): the owner and admins always; otherwise `GLOBAL_PUBLIC` for anyone,
/// `SERVER_PUBLIC` for any logged-in viewer, `LICENSED` for logged-in viewers (or anyone, if
/// `licensed_globally`), `LIMITED` for followers of the owner (`follows_owner`), and never `PRIVATE`.
/// `LICENSED` media's *bytes* are gated further by `resolve_media_size_for_viewer`.
pub fn media_visible_to_viewer(
    media: &models::Media,
    viewer: Option<&models::User>,
    follows_owner: bool,
    licensed_globally: bool,
) -> bool {
    if let Some(viewer) = viewer {
        if media.user_id == Some(viewer.id)
            || viewer.permissions.to_proto_permissions().contains(&Permission::Admin)
        {
            return true;
        }
    }
    match media.visibility.to_proto_visibility() {
        Some(Visibility::GlobalPublic) => true,
        Some(Visibility::ServerPublic) => viewer.is_some(),
        Some(Visibility::Licensed) => viewer.is_some() || licensed_globally,
        Some(Visibility::Limited) => viewer.is_some() && follows_owner,
        _ => false,
    }
}

fn viewer_follows(viewer_id: i64, owner_id: i64, conn: &mut PgPooledConnection) -> bool {
    use crate::schema::follows;
    select(diesel::dsl::exists(
        follows::table
            .filter(follows::user_id.eq(viewer_id))
            .filter(follows::target_user_id.eq(owner_id)),
    ))
    .get_result(conn)
    .unwrap_or(false)
}

/// Owner, admins, and holders of an active (`revoked_at IS NULL`) `media_licenses` row.
fn viewer_has_full_access(
    media: &models::Media,
    user: Option<&models::User>,
    state: &State<RocketState>,
) -> bool {
    let Some(user) = user else { return false };
    if media.user_id == Some(user.id) || user.permissions.to_proto_permissions().contains(&Permission::Admin) {
        return true;
    }
    let mut conn = state.pool.get().unwrap();
    viewer_holds_active_license(media.id, user.id, &mut conn)
}

pub fn viewer_holds_active_license(
    media_id: i64,
    user_id: i64,
    conn: &mut PgPooledConnection,
) -> bool {
    use crate::schema::media_licenses;
    select(diesel::dsl::exists(
        media_licenses::table
            .filter(media_licenses::media_id.eq(media_id))
            .filter(media_licenses::user_id.eq(user_id))
            .filter(media_licenses::revoked_at.is_null()),
    ))
    .get_result(conn)
    .unwrap_or(false)
}

/// Sizes anyone may fetch for `LICENSED` media: the cropped preview itself, plus still-image
/// thumbnails (video poster frames, audio waveforms, and an image's own `Small`).
const UNLICENSED_VIEWABLE_CONVERSIONS: [MediaConversion; 8] = [
    MediaConversion::UnlicensedPreviewMedium,
    MediaConversion::Small,
    MediaConversion::VideoPreviewThumbnailSmall,
    MediaConversion::VideoPreviewThumbnailMedium,
    MediaConversion::VideoPreviewThumbnailLarge,
    MediaConversion::AudioPreviewThumbnailSmall,
    MediaConversion::AudioPreviewThumbnailMedium,
    MediaConversion::AudioPreviewThumbnailLarge,
];

/// Like `resolve_media_size`, but for a viewer without full access to a `LICENSED` item (see
/// `has_full_access`): only `UNLICENSED_VIEWABLE_CONVERSIONS` are ever served -- by default (and
/// when a restricted size is requested) the cropped `UNLICENSED_PREVIEW_MEDIUM`, or `Small`, and
/// never the original. `403 Forbidden` if none of those exist.
pub fn resolve_media_size_for_viewer(
    media: &models::Media,
    size: Option<&str>,
    has_full_access: bool,
) -> Result<(String, String), Status> {
    if has_full_access {
        return Ok(resolve_media_size(media, size));
    }
    let sizes = media.sizes();
    let find = |conversion: MediaConversion| {
        sizes
            .iter()
            .find(|s| s.conversion == conversion as i32)
            .map(|s| (s.object_storage_path.clone(), s.content_type.clone()))
    };
    let requested = requested_conversion(size);
    UNLICENSED_VIEWABLE_CONVERSIONS
        .contains(&requested)
        .then(|| find(requested))
        .flatten()
        .or_else(|| find(MediaConversion::UnlicensedPreviewMedium))
        .or_else(|| find(MediaConversion::Small))
        .ok_or(Status::Forbidden)
}

/// Picks the (object_storage_path, content_type) to serve for a given size request.
///
/// `size` of `Some("original")` always forces the unconverted original. `video_preview_small`/
/// `_medium`/`_large` request the `image/jpeg` poster-frame sizes video `Media` gets instead of
/// (not in addition to) its ordinary `small`/`medium`/`large` -- see `MediaConversion`'s own doc in
/// `media.proto` -- e.g. `Components.MediaRenderer`'s play-button-overlaid thumbnail. Otherwise the
/// requested size (defaulting to `Medium` when `size` is `None`/unrecognized) is looked up, falling
/// through to the original if that converted size isn't available -- which also covers media that
/// hasn't been converted at all. Note that fallback would serve the original *video* file for an
/// unresolved `video_preview_*` request -- harmless in practice since callers only ever request one
/// once they already know (from the `Media` they fetched over gRPC) that it exists.
fn resolve_media_size(media: &models::Media, size: Option<&str>) -> (String, String) {
    resolve_media_size_preferring(media, &[requested_conversion(size)])
}

fn requested_conversion(size: Option<&str>) -> MediaConversion {
    match size {
        Some("original") => MediaConversion::Original,
        Some("small") => MediaConversion::Small,
        Some("large") => MediaConversion::Large,
        Some("video_preview_small") => MediaConversion::VideoPreviewThumbnailSmall,
        Some("video_preview_medium") => MediaConversion::VideoPreviewThumbnailMedium,
        Some("video_preview_large") => MediaConversion::VideoPreviewThumbnailLarge,
        Some("audio_preview_small") => MediaConversion::AudioPreviewThumbnailSmall,
        Some("audio_preview_medium") => MediaConversion::AudioPreviewThumbnailMedium,
        Some("audio_preview_large") => MediaConversion::AudioPreviewThumbnailLarge,
        Some("unlicensed_preview") => MediaConversion::UnlicensedPreviewMedium,
        _ => MediaConversion::Medium,
    }
}

/// Picks the (object_storage_path, content_type) to serve, trying each `MediaConversion` in `preference`
/// order in turn and falling back to the original (unconverted) upload if none of them are
/// available -- which also covers media that hasn't been converted at all.
fn resolve_media_size_preferring(
    media: &models::Media,
    preference: &[MediaConversion],
) -> (String, String) {
    let sizes = media.sizes();

    preference
        .iter()
        .find_map(|conversion| sizes.iter().find(|s| s.conversion == *conversion as i32))
        .or_else(|| sizes.iter().find(|s| s.conversion == MediaConversion::Original as i32))
        .map(|s| (s.object_storage_path.clone(), s.content_type.clone()))
        .unwrap_or_default()
}

fn load_media_by_id(id: &str, state: &State<RocketState>) -> Result<models::Media, Status> {
    schema::media::table
        .filter(
            media::id.eq(id
                .to_string()
                .to_db_id_or_err("media_id")
                .map_err(|_| Status::BadRequest)?),
        )
        .first::<models::Media>(&mut state.pool.get().unwrap())
        .map_err(|_| Status::NotFound)
}

// #[rocket::get("/media/<id>?<authorization>&<size>")]
pub async fn load_media_file_data<'a>(
    id: &str,
    size: Option<&str>,
    state: &State<RocketState>,
) -> Result<(ContentType, NamedFile), Status> {
    log::info!("media_file: {:?}, size: {:?}", id, size);

    // TODO: Validate moderation/visiblity/permissions etc.
    let media = load_media_by_id(id, state)?;
    let (object_storage_path, content_type) = resolve_media_size(&media, size);
    load_media_file(object_storage_path, content_type, state).await
}

/// Like [`load_media_file_data`], but tries each `ConvertedSizeSpec` in `preference` order
/// instead of a single client-requested size string, falling back to the original if none of
/// them are available.
pub async fn load_media_file_data_preferring<'a>(
    id: &str,
    preference: &[MediaConversion],
    state: &State<RocketState>,
) -> Result<(ContentType, NamedFile), Status> {
    log::info!("media_file: {:?}, preference: {:?}", id, preference);

    // TODO: Validate moderation/visiblity/permissions etc.
    let media = load_media_by_id(id, state)?;
    let (object_storage_path, content_type) = resolve_media_size_preferring(&media, preference);
    load_media_file(object_storage_path, content_type, state).await
}

async fn load_media_file(
    object_storage_path: String,
    content_type: String,
    state: &State<RocketState>,
) -> Result<(ContentType, NamedFile), Status> {
    let local_filename = format!(
        "{}/{}.mediafile",
        state.tempdir.path().display(),
        object_storage_path
    );
    if !std::path::Path::new(&local_filename).exists() {
        // Ensure local directory exists.
        let mut _filevec: Vec<&str> = local_filename.split("/").collect();
        _filevec.pop();
        let local_filedir = _filevec.join("/");
        // info!("local_filedir: {}", local_filedir);
        std::fs::create_dir_all(local_filedir).map_err(|_| Status::InternalServerError)?;

        // Download file from S3 into a tempfile
        let temp_filename = format!("{}-download-{}", local_filename, Uuid::new_v4());
        let mut async_output_file = tokio::fs::File::create(temp_filename.to_owned())
            .await
            .map_err(|_| Status::InternalServerError)?;
        let _status_code = state
            .bucket
            .get_object_to_writer(object_storage_path, &mut async_output_file)
            .await
            .map_err(|_| Status::InternalServerError)?;

        // Rename tempfile to final filename
        std::fs::rename(temp_filename, &local_filename).map_err(|_| Status::InternalServerError)?;
    }

    let media_type =
        ContentType(MediaType::from_str(&content_type).map_err(|_| Status::ExpectationFailed)?);
    info!("media_type: {:?}", media_type);
    let result = open_named_file(&local_filename).await?;
    // let result = NamedFile::open(local_filename)
    //     .await
    //     .map_err(|_| Status::ImATeapot)?;
    Ok((media_type, result))

    // let mut _stream = state
    //     .bucket
    //     .get_object_stream(media.object_storage_path.as_str())
    //     .await
    //     .map_err(|_| Status::NotFound)?;

    // Ok(ByteStream::from(async_output_file.st))

    // This should work.
    // Ok(ByteStream::from(_stream.bytes()))

    // Or this.
    // Ok(ByteStream! {
    //     let mut stream: &'a ResponseDataStream = &state
    //         .bucket
    //         .get_object_stream(media.object_storage_path.as_str())
    //         .await
    //         .map_err(|_| Status::NotFound).unwrap();
    //     while let Some(bytes) = stream.bytes().next().await {
    //         yield bytes;
    //     }
    // })

    // We should at least be able to write to an output file and return that... but this doesn't compile either.
    // Seems the S3 `ResponseDataStream` type is not `Send`.

    // let mut async_output_file = tokio::fs::File::create(media.object_storage_path).await.expect("Unable to create file");
    // while let Some(chunk) = _stream.bytes.next().await {
    //     async_output_file.write_all(&chunk).await.map_err(|_| Status::NotFound)?;
    // }

    // So far all I can get to work is this...
    // Ok(ByteStream! { yield bytes::Bytes::from("test")})
}

pub async fn open_named_file(local_filename: &str) -> Result<NamedFile, Status> {
    Ok(NamedFile::open(local_filename)
        .await
        .map_err(|_| Status::ImATeapot)?)
}

/// Gets the user from a manual rellm_access_token, auth header, or cookies (in that priority order).
fn get_media_user(
    manual_authorization: Option<String>,
    auth_header: Option<AuthHeader<'_>>,
    cookies: &CookieJar<'_>,
    state: &State<RocketState>,
) -> Result<models::User, Status> {
    let access_token = match manual_authorization {
        Some(access_token) => access_token,
        _ => match auth_header {
            Some(auth_header) => auth_header.0.to_string(),
            _ => match cookies.get("rellm_access_token") {
                Some(access_token) => access_token.value().to_string(),
                _ => return Err(Status::Unauthorized),
            },
        },
    };

    let user = get_auth_user(access_token, &mut state.pool.get().unwrap());
    match user {
        Ok(user) => Ok(user),
        Err(status) => Err(status),
    }
}

fn get_auth_user(
    access_token: String,
    conn: &mut PgPooledConnection,
) -> Result<models::User, Status> {
    let user_id = get_auth_user_id(access_token, conn);
    let user: models::User = match user_id {
        Err(status) => return Err(status),
        Ok(user_id) => schema::users::table
            .select(models::USER_COLUMNS)
            .filter(users::id.eq(user_id))
            .first::<models::User>(conn)
            .unwrap(),
    };
    Ok(user)
}

fn get_auth_user_id(access_token: String, conn: &mut PgPooledConnection) -> Result<i64, Status> {
    delete(
        user_access_tokens::user_access_tokens
            .filter(user_access_tokens::token.eq(access_token.to_owned()))
            .filter(user_access_tokens::expires_at.lt(diesel::dsl::now)),
    )
    .execute(conn)
    .unwrap_or(0);

    let user_id: Result<i64, _> = schema::user_access_tokens::table
        .inner_join(schema::user_refresh_tokens::table)
        .select(user_refresh_tokens::user_id)
        .filter(user_access_tokens::token.eq(access_token))
        .first::<i64>(conn);

    match user_id {
        Ok(user_id) => Ok(user_id),
        Err(_) => Err(Status::Unauthorized),
    }
}
