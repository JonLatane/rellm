//! HLS streaming of video `Media`: `/media/hls/{id}/master.m3u8`, `/media/hls/{id}/{variant}/playlist.m3u8`
//! and `/media/hls/{id}/{variant}/{n}.ts`. See `logic::media::hls` for how the streams are made and
//! why; this is just the (access-checked) HTTP side.
//!
//! These live under `/media/` on purpose: the same visibility/licensing rules, CORS handling and
//! CDN caching rule that already cover `/media/{id}` cover them, and all of their URIs are relative
//! (plus the viewer's `?authorization=`, if they used one) so a player needs nothing but the master
//! playlist's URL.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use rocket::fs::NamedFile;
use rocket::http::{ContentType, Status};
use rocket::{http::CookieJar, routes, Route, State};
use rocket_cache_response::CacheResponse;
use uuid::Uuid;

use crate::logic::hls::{self, HLS_VARIANTS};
use crate::logic::{is_video_content_type, object_path_version_base};
use crate::web::headers::AuthHeader;
use crate::web::media::{
    authorize_media_view, blocks_cors, load_media_file, media_cache_control, MediaAccess, MediaResponse,
};
use crate::web::RocketState;

lazy_static! {
    pub static ref MEDIA_HLS_ENDPOINTS: Vec<Route> =
        routes![hls_options, hls_master_playlist, hls_media_playlist, hls_segment];

    /// One lock per rendition being segmented, so concurrent first requests share a single `ffmpeg` pass.
    static ref SEGMENTING: Mutex<HashMap<String, Arc<rocket::tokio::sync::Mutex<()>>>> = Mutex::new(HashMap::new());
}

/// Used to manage CORS for the HLS endpoints.
#[rocket::options("/media/hls/<id>/<rest..>")]
pub async fn hls_options(id: &str, rest: PathBuf) -> &'static str {
    let _ = (id, rest);
    ""
}

/// `?authorization=<token>` if the viewer authorized with one (a `<video>`/hls.js request can't set
/// headers the way a gRPC call does), to pass on to every URI in the playlists.
fn uri_suffix(authorization: &Option<String>) -> String {
    match authorization {
        Some(token) if !token.is_empty() => {
            format!("?authorization={}", rocket::http::RawStr::new(token).percent_encode())
        }
        _ => String::new(),
    }
}

/// The variants (name, stored object path) `access` may stream: the `HLS_VARIANTS` whose rendition is
/// an MP4 -- what `convert_media_sizes` makes for a video that isn't a `.webm`. Empty for anything
/// that isn't a video, and for a video not (yet) converted, whose viewers keep using `/media/{id}`.
/// A viewer without full access to `LICENSED` media gets only the cropped preview.
fn streamable_variants(access: &MediaAccess) -> Vec<(&'static str, String)> {
    let media = &access.media;
    if !media.original().is_some_and(|o| is_video_content_type(&o.content_type)) {
        return vec![];
    }
    let sizes = media.sizes();
    HLS_VARIANTS
        .iter()
        .filter(|(name, _)| (*name == "preview") != access.has_full_access)
        .filter_map(|(name, conversion)| {
            sizes
                .iter()
                .find(|s| s.conversion == *conversion as i32 && s.content_type == "video/mp4")
                .map(|s| (*name, s.object_storage_path.clone()))
        })
        .collect()
}

fn internal_error<E: std::fmt::Display>(error: E) -> Status {
    log::error!("HLS: {error}");
    Status::InternalServerError
}

/// The directory holding `object_storage_path`'s HLS segments and playlist, creating them first (from
/// the rendition's stored MP4, fetched like any `/media/{id}` request) if this process hasn't yet.
/// `404` if the rendition isn't something every player can stream (not H.264).
async fn ensure_segments(object_storage_path: &str, state: &State<RocketState>) -> Result<PathBuf, Status> {
    let dir = PathBuf::from(format!("{}/{}.hls", state.tempdir.path().display(), object_storage_path));
    let ready = |dir: &PathBuf| dir.join("playlist.m3u8").exists();
    if ready(&dir) {
        return Ok(dir);
    }

    let lock = SEGMENTING
        .lock()
        .unwrap()
        .entry(object_storage_path.to_owned())
        .or_default()
        .clone();
    let _guard = lock.lock().await;
    if ready(&dir) {
        return Ok(dir);
    }

    let (_, file) = load_media_file(object_storage_path.to_owned(), "video/mp4".to_owned(), state).await?;
    let input = file.path().to_owned();
    let out = dir.clone();
    let tmp = PathBuf::from(format!("{}.tmp-{}", dir.display(), Uuid::new_v4()));
    let tmp_for_task = tmp.clone();
    let result = rocket::tokio::task::spawn_blocking(move || -> anyhow::Result<bool> {
        if !hls::probe(&input)?.is_streamable() {
            return Ok(false);
        }
        hls::segment_video(&input, &tmp_for_task)?;
        std::fs::rename(&tmp_for_task, &out)?;
        Ok(true)
    })
    .await;
    SEGMENTING.lock().unwrap().remove(object_storage_path);
    match result {
        Ok(Ok(true)) => {
            evict_superseded_hls_dirs(&dir, object_storage_path);
            Ok(dir)
        }
        Ok(Ok(false)) => Err(Status::NotFound),
        Ok(Err(e)) => {
            let _ = std::fs::remove_dir_all(&tmp);
            Err(internal_error(e))
        }
        Err(e) => {
            let _ = std::fs::remove_dir_all(&tmp);
            Err(internal_error(e))
        }
    }
}

/// Deletes the HLS directories of *earlier versions* of the rendition just segmented into `dir` --
/// the same housekeeping, for the same reason, as `media::evict_superseded_cache_files`.
fn evict_superseded_hls_dirs(dir: &std::path::Path, object_storage_path: &str) {
    let Some(base) = object_path_version_base(object_storage_path) else { return };
    let (Some(parent), Some(own_name)) = (dir.parent(), dir.file_name().and_then(|n| n.to_str())) else { return };
    let Some(base_name) = base.rsplit('/').next() else { return };
    let Ok(entries) = std::fs::read_dir(parent) else { return };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(name) = name.to_str() else { continue };
        if name != own_name && hls::is_superseded_hls_dir(name, base_name) {
            let _ = std::fs::remove_dir_all(entry.path());
        }
    }
}

fn playlist_content_type() -> ContentType {
    ContentType::new("application", "vnd.apple.mpegurl")
}

type PlaylistResponse = MediaResponse<CacheResponse<(ContentType, String)>>;

fn playlist_response(access: &MediaAccess, body: String, token_in_body: bool, state: &State<RocketState>) -> PlaylistResponse {
    let block_cors = blocks_cors(access.user.as_ref(), state);
    MediaResponse {
        // A playlist with the viewer's token inside it mustn't be shared.
        inner: CacheResponse::new(
            (playlist_content_type(), body),
            media_cache_control(access.licensed || token_in_body),
        ),
        block_cors,
        vary_on_auth: access.licensed || block_cors,
        content_disposition: None,
    }
}

/// The master playlist: one variant per stored MP4 rendition, with the resolution and bit rate that
/// `ffprobe` reports for it, for the player to choose between.
#[rocket::get("/media/hls/<id>/master.m3u8?<authorization>")]
pub async fn hls_master_playlist(
    id: &str,
    authorization: Option<String>,
    cookies: &CookieJar<'_>,
    state: &State<RocketState>,
    auth_header: Option<AuthHeader<'_>>,
) -> Result<PlaylistResponse, Status> {
    let suffix = uri_suffix(&authorization);
    let access = authorize_media_view(id, authorization, auth_header, cookies, state)?;
    let mut variants = vec![];
    for (name, object_storage_path) in streamable_variants(&access) {
        let (_, file) = load_media_file(object_storage_path, "video/mp4".to_owned(), state).await?;
        let input = file.path().to_owned();
        let info = rocket::tokio::task::spawn_blocking(move || hls::probe(&input))
            .await
            .map_err(internal_error)?;
        match info {
            Ok(info) if info.is_streamable() => variants.push((name, info)),
            Ok(_) => {}
            Err(e) => return Err(internal_error(e)),
        }
    }
    if variants.is_empty() {
        return Err(Status::NotFound);
    }
    let body = hls::master_playlist(&variants, &suffix);
    Ok(playlist_response(&access, body, !suffix.is_empty(), state))
}

/// One variant's media playlist (segment list), straight from `ffmpeg` apart from the
/// `?authorization=` each segment URI carries on.
// Explicit ranks: without them Rocket sees `playlist.m3u8` as colliding with `<segment>`.
#[rocket::get("/media/hls/<id>/<variant>/playlist.m3u8?<authorization>", rank = 1)]
pub async fn hls_media_playlist(
    id: &str,
    variant: &str,
    authorization: Option<String>,
    cookies: &CookieJar<'_>,
    state: &State<RocketState>,
    auth_header: Option<AuthHeader<'_>>,
) -> Result<PlaylistResponse, Status> {
    let suffix = uri_suffix(&authorization);
    let (access, dir) = authorized_segments(id, variant, authorization, cookies, state, auth_header).await?;
    let playlist = std::fs::read_to_string(dir.join("playlist.m3u8")).map_err(internal_error)?;
    Ok(playlist_response(&access, hls::with_uri_suffix(&playlist, &suffix), !suffix.is_empty(), state))
}

/// One `.ts` segment of a variant.
#[rocket::get("/media/hls/<id>/<variant>/<segment>?<authorization>", rank = 2)]
pub async fn hls_segment(
    id: &str,
    variant: &str,
    segment: &str,
    authorization: Option<String>,
    cookies: &CookieJar<'_>,
    state: &State<RocketState>,
    auth_header: Option<AuthHeader<'_>>,
) -> Result<MediaResponse<CacheResponse<(ContentType, NamedFile)>>, Status> {
    if !hls::is_segment_name(segment) {
        return Err(Status::NotFound);
    }
    let (access, dir) = authorized_segments(id, variant, authorization, cookies, state, auth_header).await?;
    let file = NamedFile::open(dir.join(segment)).await.map_err(|_| Status::NotFound)?;
    let block_cors = blocks_cors(access.user.as_ref(), state);
    Ok(MediaResponse {
        inner: CacheResponse::new((ContentType::new("video", "mp2t"), file), media_cache_control(access.licensed)),
        block_cors,
        vary_on_auth: access.licensed || block_cors,
        content_disposition: None,
    })
}

/// Checks the viewer may stream `variant` of media `id` and returns its (made if need be) segment directory.
async fn authorized_segments(
    id: &str,
    variant: &str,
    authorization: Option<String>,
    cookies: &CookieJar<'_>,
    state: &State<RocketState>,
    auth_header: Option<AuthHeader<'_>>,
) -> Result<(MediaAccess, PathBuf), Status> {
    let access = authorize_media_view(id, authorization, auth_header, cookies, state)?;
    let object_storage_path = streamable_variants(&access)
        .into_iter()
        .find(|(name, _)| *name == variant)
        .map(|(_, path)| path)
        .ok_or(Status::NotFound)?;
    let dir = ensure_segments(&object_storage_path, state).await?;
    Ok((access, dir))
}

