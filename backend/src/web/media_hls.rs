//! HLS streaming of video `Media`: `/media/hls/{id}/master.m3u8`, `/media/hls/{id}/{variant}/playlist.m3u8`
//! and `/media/hls/{id}/{variant}/{n}.ts`. See `logic::media::hls` for how the streams are made and
//! why; this is just the (access-checked) HTTP side.
//!
//! Off unless an admin turns on `MediaSettings.hls_streaming_enabled` -- every URL here is a `404` until
//! then (see `hls_enabled`), since streaming costs more than the stored size conversions do.
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

use crate::logic::hls::{self, StreamInfo, HLS_VARIANTS};
use crate::models::MediaConversionExt;
use crate::logic::{is_video_content_type, object_path_version_base};
use crate::protos::MediaConversion;
use crate::rpcs::get_server_configuration_proto;
use crate::web::headers::AuthHeader;
use crate::web::media::{
    authorize_media_view, blocks_cors, load_media_file, media_cache_control, MediaAccess, MediaResponse,
};
use crate::web::RocketState;

lazy_static! {
    pub static ref MEDIA_HLS_ENDPOINTS: Vec<Route> =
        routes![hls_options, hls_master_playlist, hls_media_playlist, hls_segment];

    /// What `ffprobe` said about each rendition (keyed by its versioned object path, so a regenerated one is
    /// probed afresh), so a master playlist doesn't re-fetch and re-probe every rendition on every request.
    static ref PROBES: Mutex<HashMap<String, StreamInfo>> = Mutex::new(HashMap::new());

    /// One lock per rendition being segmented, so concurrent first requests share a single `ffmpeg` pass.
    static ref SEGMENTING: Mutex<HashMap<String, Arc<rocket::tokio::sync::Mutex<()>>>> = Mutex::new(HashMap::new());
}

/// Used to manage CORS for the HLS endpoints.
#[rocket::options("/media/hls/<id>/<rest..>")]
pub async fn hls_options(id: &str, rest: PathBuf) -> &'static str {
    let _ = (id, rest);
    ""
}

/// The query string every URI in a variant's playlists carries: the rendition's `version` (see
/// `hls::version_of`) and, if the viewer authorized with one, their `authorization=<token>` (a
/// `<video>`/hls.js request can't set headers the way a gRPC call does).
fn uri_suffix(version: &str, authorization: &Option<String>) -> String {
    match authorization {
        Some(token) if !token.is_empty() => {
            format!("?v={}&authorization={}", version, rocket::http::RawStr::new(token).percent_encode())
        }
        _ => format!("?v={version}"),
    }
}

/// One stored rendition a viewer may stream.
struct Variant {
    name: &'static str,
    conversion: MediaConversion,
    object_storage_path: String,
    size_bytes: i64,
    /// Width / height, recorded when the rendition was converted.
    aspect_ratio: Option<f32>,
}

/// The variants `access` may stream: the `HLS_VARIANTS` whose rendition is an MP4 -- what
/// `convert_media_sizes` makes for a video that isn't a `.webm`. Empty for anything that isn't a video,
/// and for a video not (yet) converted, whose viewers keep using `/media/{id}`. A viewer without full
/// access to `LICENSED` media gets only the cropped preview.
fn streamable_variants(access: &MediaAccess) -> Vec<Variant> {
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
                .map(|s| Variant {
                    name,
                    conversion: *conversion,
                    object_storage_path: s.object_storage_path.clone(),
                    size_bytes: s.size_bytes,
                    aspect_ratio: s.aspect_ratio,
                })
        })
        .collect()
}

/// Whether the admin has turned HLS streaming on (`MediaSettings.hls_streaming_enabled`, off by default).
fn hls_enabled(state: &State<RocketState>) -> bool {
    let mut conn = state.pool.get().unwrap();
    get_server_configuration_proto(&mut conn)
        .ok()
        .and_then(|c| c.media_settings)
        .is_some_and(|m| m.hls_streaming_enabled)
}

/// `ffprobe` for the rendition at `object_storage_path`, remembered after the first time.
async fn probe_cached(object_storage_path: &str, state: &State<RocketState>) -> Result<StreamInfo, Status> {
    if let Some(info) = PROBES.lock().unwrap().get(object_storage_path) {
        return Ok(info.clone());
    }
    let (_, file) = load_media_file(object_storage_path.to_owned(), "video/mp4".to_owned(), state).await?;
    let input = file.path().to_owned();
    let info = rocket::tokio::task::spawn_blocking(move || hls::probe(&input))
        .await
        .map_err(internal_error)?
        .map_err(internal_error)?;
    let mut probes = PROBES.lock().unwrap();
    if probes.len() >= 1024 {
        probes.clear(); // bounded: a cleared entry is just probed again
    }
    probes.insert(object_storage_path.to_owned(), info.clone());
    Ok(info)
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
    if dir.join("playlist.m3u8").exists() {
        return Ok(dir);
    }

    let lock = SEGMENTING
        .lock()
        .unwrap()
        .entry(object_storage_path.to_owned())
        .or_default()
        .clone();
    let result = segment_exclusively(&lock, dir, object_storage_path, state).await;
    release_segmenting_lock(object_storage_path, lock);
    result
}

/// Forgets `object_storage_path`'s segmenting lock, unless another request holds (or is waiting on) it:
/// handles are only ever cloned under `SEGMENTING`'s own mutex, so a count of 2 (the map's and ours)
/// means nobody else can be using it, and a request arriving later makes a fresh one. Dropping it any
/// earlier could let a waiter and a newcomer segment the same rendition at once.
fn release_segmenting_lock(object_storage_path: &str, lock: Arc<rocket::tokio::sync::Mutex<()>>) {
    let mut locks = SEGMENTING.lock().unwrap();
    if Arc::strong_count(&lock) <= 2 {
        locks.remove(object_storage_path);
    }
}

/// `ensure_segments`' work, once `lock` is this request's alone: whoever waited on it finds the
/// directory ready and does nothing.
async fn segment_exclusively(
    lock: &rocket::tokio::sync::Mutex<()>,
    dir: PathBuf,
    object_storage_path: &str,
    state: &State<RocketState>,
) -> Result<PathBuf, Status> {
    let _guard = lock.lock().await;
    if dir.join("playlist.m3u8").exists() {
        return Ok(dir);
    }

    if !probe_cached(object_storage_path, state).await?.is_streamable() {
        return Err(Status::NotFound);
    }
    let (_, file) = load_media_file(object_storage_path.to_owned(), "video/mp4".to_owned(), state).await?;
    let input = file.path().to_owned();
    let out = dir.clone();
    let tmp = PathBuf::from(format!("{}.tmp-{}", dir.display(), Uuid::new_v4()));
    let tmp_for_task = tmp.clone();
    let result = rocket::tokio::task::spawn_blocking(move || -> anyhow::Result<()> {
        hls::segment_video(&input, &tmp_for_task)?;
        std::fs::rename(&tmp_for_task, &out)?;
        Ok(())
    })
    .await;
    match result {
        Ok(Ok(())) => {
            evict_superseded_hls_dirs(&dir, object_storage_path);
            Ok(dir)
        }
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

/// The master playlist: one variant per stored MP4 rendition, for the player to choose between. Only
/// the smallest rendition is downloaded and `ffprobe`d (once -- see `probe_cached`), for the video's
/// duration; the others' resolution and bit rate follow from their stored size and aspect ratio, so a
/// cold request never waits on the large renditions that a viewer who stays on `small` never needs.
#[rocket::get("/media/hls/<id>/master.m3u8?<authorization>")]
pub async fn hls_master_playlist(
    id: &str,
    authorization: Option<String>,
    cookies: &CookieJar<'_>,
    state: &State<RocketState>,
    auth_header: Option<AuthHeader<'_>>,
) -> Result<PlaylistResponse, Status> {
    let token = authorization.clone();
    let access = authorize_media_view(id, authorization, auth_header, cookies, state)?;
    if !hls_enabled(state) {
        return Err(Status::NotFound);
    }
    let candidates = streamable_variants(&access);
    let Some(first) = candidates.first() else {
        return Err(Status::NotFound);
    };
    let first_info = probe_cached(&first.object_storage_path, state).await?;
    if !first_info.is_streamable() {
        return Err(Status::NotFound);
    }
    let mut variants = vec![];
    for variant in &candidates {
        let info = match variant.aspect_ratio {
            _ if std::ptr::eq(variant, first) => first_info.clone(),
            Some(aspect_ratio) => hls::estimate_stream_info(
                aspect_ratio,
                variant.conversion.max_dimension(),
                variant.size_bytes,
                first_info.duration_seconds,
            ),
            // Converted before aspect ratios were recorded: no choice but to look.
            None => probe_cached(&variant.object_storage_path, state).await?,
        };
        if info.is_streamable() {
            let query = uri_suffix(&hls::version_of(&variant.object_storage_path), &token);
            variants.push((variant.name, info, query));
        }
    }
    let body = hls::master_playlist(&variants);
    Ok(playlist_response(&access, body, token.as_deref().is_some_and(|t| !t.is_empty()), state))
}

/// One variant's media playlist (segment list), straight from `ffmpeg` apart from the
/// `?authorization=` each segment URI carries on.
// Explicit ranks: without them Rocket sees `playlist.m3u8` as colliding with `<segment>`.
#[rocket::get("/media/hls/<id>/<variant>/playlist.m3u8?<authorization>&<v>", rank = 1)]
pub async fn hls_media_playlist(
    id: &str,
    variant: &str,
    authorization: Option<String>,
    v: Option<String>,
    cookies: &CookieJar<'_>,
    state: &State<RocketState>,
    auth_header: Option<AuthHeader<'_>>,
) -> Result<PlaylistResponse, Status> {
    let token = authorization.clone();
    let (access, dir, version) = authorized_segments(id, variant, authorization, v, cookies, state, auth_header).await?;
    let playlist = std::fs::read_to_string(dir.join("playlist.m3u8")).map_err(internal_error)?;
    let suffix = uri_suffix(&version, &token);
    Ok(playlist_response(&access, hls::with_uri_suffix(&playlist, &suffix), token.as_deref().is_some_and(|t| !t.is_empty()), state))
}

/// One `.ts` segment of a variant.
#[rocket::get("/media/hls/<id>/<variant>/<segment>?<authorization>&<v>", rank = 2)]
pub async fn hls_segment(
    id: &str,
    variant: &str,
    segment: &str,
    authorization: Option<String>,
    v: Option<String>,
    cookies: &CookieJar<'_>,
    state: &State<RocketState>,
    auth_header: Option<AuthHeader<'_>>,
) -> Result<MediaResponse<CacheResponse<(ContentType, NamedFile)>>, Status> {
    if !hls::is_segment_name(segment) {
        return Err(Status::NotFound);
    }
    let (access, dir, _) = authorized_segments(id, variant, authorization, v, cookies, state, auth_header).await?;
    let file = NamedFile::open(dir.join(segment)).await.map_err(|_| Status::NotFound)?;
    let block_cors = blocks_cors(access.user.as_ref(), state);
    Ok(MediaResponse {
        inner: CacheResponse::new((ContentType::new("video", "mp2t"), file), media_cache_control(access.licensed)),
        block_cors,
        vary_on_auth: access.licensed || block_cors,
        content_disposition: None,
    })
}

/// Checks the viewer may stream `variant` of media `id` and returns its (made if need be) segment directory
/// and version. `v`, if the URL had one, must be that version: a playlist from before the rendition was
/// regenerated is a `404` from then on, rather than quietly receiving the new rendition's segments.
async fn authorized_segments(
    id: &str,
    variant: &str,
    authorization: Option<String>,
    v: Option<String>,
    cookies: &CookieJar<'_>,
    state: &State<RocketState>,
    auth_header: Option<AuthHeader<'_>>,
) -> Result<(MediaAccess, PathBuf, String), Status> {
    let access = authorize_media_view(id, authorization, auth_header, cookies, state)?;
    if !hls_enabled(state) {
        return Err(Status::NotFound);
    }
    let object_storage_path = streamable_variants(&access)
        .into_iter()
        .find(|candidate| candidate.name == variant)
        .map(|candidate| candidate.object_storage_path)
        .ok_or(Status::NotFound)?;
    let version = hls::version_of(&object_storage_path);
    if v.is_some_and(|v| v != version) {
        return Err(Status::NotFound);
    }
    let dir = ensure_segments(&object_storage_path, state).await?;
    Ok((access, dir, version))
}
