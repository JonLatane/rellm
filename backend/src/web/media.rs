use std::str::FromStr;

use crate::db_connection::*;
use crate::logic::{adjust_server_media_usage_bytes, update_media_storage_used};
use crate::marshaling::*;
use crate::models;
use crate::protos::{MediaConversion, Visibility};
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

#[rocket::get("/media/<id>?<authorization>&<size>")]
pub async fn media_file<'a>(
    id: &str,
    authorization: Option<String>,
    size: Option<String>,
    cookies: &CookieJar<'_>,
    state: &State<RocketState>,
    auth_header: Option<AuthHeader<'_>>,
) -> Result<CacheResponse<(ContentType, NamedFile)>, Status> {
    log::info!("media_file: {:?}, size: {:?}", id, size);
    let _user = get_media_user(authorization, auth_header, cookies, state).ok();

    let data = load_media_file_data(id, size.as_deref(), state).await?;

    Ok(CacheResponse::new(
        data,
        CacheControl {
            must_revalidate: true,
            ..CacheControl::public(3600 * 12)
        },
    ))
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
    let requested = match size {
        Some("original") => MediaConversion::Original,
        Some("small") => MediaConversion::Small,
        Some("large") => MediaConversion::Large,
        Some("video_preview_small") => MediaConversion::VideoPreviewThumbnailSmall,
        Some("video_preview_medium") => MediaConversion::VideoPreviewThumbnailMedium,
        Some("video_preview_large") => MediaConversion::VideoPreviewThumbnailLarge,
        _ => MediaConversion::Medium,
    };

    resolve_media_size_preferring(media, &[requested])
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
