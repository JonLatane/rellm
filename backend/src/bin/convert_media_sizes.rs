extern crate diesel;
extern crate rellm;

use rellm::logic::{
    acquire_cluster_lock, convert_media, media_pending_conversion, release_cluster_lock, FFmpeg,
    ImageMagick, VIDEO_CONVERTIBLE_CONTENT_TYPES,
};
use rellm::protos::{ClusterResource, ClusterResources};
use rellm::{db_connection, init_bin_logging, init_crypto, minio_connection, rpcs};

/// Processes Media in batches of this size per run -- background_jobs.sh re-invokes this binary
/// on an interval, so a large backlog just gets worked down over several runs rather than one
/// long-running process.
const BATCH_SIZE: i64 = 20;

#[tokio::main]
async fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Converting Media sizes...");

    let imagemagick = ImageMagick::detect();
    if imagemagick.is_none() {
        log::error!(
            "ImageMagick not found on $PATH (tried 'magick', and 'convert'+'identify'). \
             Install it to enable automatic image size conversion; skipping images this run."
        );
    }
    let ffmpeg = FFmpeg::detect();
    if ffmpeg.is_none() {
        log::error!(
            "ffmpeg not found on $PATH (tried 'ffmpeg' and 'ffprobe'). \
             Install it to enable automatic video size conversion; skipping videos this run."
        );
    }
    if imagemagick.is_none() && ffmpeg.is_none() {
        log::error!("Neither ImageMagick nor ffmpeg found on $PATH; skipping this run entirely.");
        std::process::exit(1);
    }

    log::info!("Connecting to DB and MinIO...");
    let pool = db_connection::establish_pool();
    let mut conn = pool.get().expect("Failed to get DB connection");

    let pending = media_pending_conversion(&mut conn, BATCH_SIZE)
        .expect("Failed to load Media pending conversion");
    log::info!("Got {} Media item(s) to convert.", pending.len());

    if pending.is_empty() {
        log::info!("No Media pending conversion, exiting.");
        return;
    }

    // If this server is part of a cluster (see `ClusterResources`'s own doc in
    // server_configuration.proto), only up to each resource's configured `ClusterResourceLimit`
    // instances may run `ffmpeg`/ImageMagick conversions at once -- acquire whichever of those
    // this batch actually needs from the conductor before touching MinIO/running either tool
    // below. Servers not configured with `cluster_resources` skip this entirely (single-instance
    // mode, unchanged from before this existed).
    let cluster_resources: Option<ClusterResources> = rpcs::get_server_configuration_model(&mut conn)
        .expect("Failed to load server configuration")
        .cluster_resources
        .and_then(|v| serde_json::from_value(v).ok());

    let mut wanted_resources = Vec::new();
    if ffmpeg.is_some()
        && pending.iter().any(|m| {
            m.original()
                .is_some_and(|o| VIDEO_CONVERTIBLE_CONTENT_TYPES.contains(&o.content_type.as_str()))
        })
    {
        wanted_resources.push(ClusterResource::Ffmpeg);
    }
    if imagemagick.is_some()
        && pending.iter().any(|m| {
            m.original()
                .is_some_and(|o| !VIDEO_CONVERTIBLE_CONTENT_TYPES.contains(&o.content_type.as_str()))
        })
    {
        wanted_resources.push(ClusterResource::Imagemagick);
    }

    if let Some(resources) = cluster_resources.as_ref().filter(|_| !wanted_resources.is_empty()) {
        log::info!(
            "Cluster resources configured; acquiring {:?} lock(s) from conductor...",
            wanted_resources
        );
        if !acquire_cluster_lock(resources, &wanted_resources).await {
            log::warn!("Could not acquire cluster resource lock(s) in time; skipping this run.");
            return;
        }
    }

    let bucket = minio_connection::get_and_test_bucket()
        .await
        .expect("Failed to connect to MinIO");

    let tmp_dir = tempfile::tempdir().expect("Failed to create temp dir");

    for item in pending.iter() {
        log::info!(
            "Converting Media {}: {}",
            item.id,
            item.original().map(|o| o.minio_path).unwrap_or_default()
        );
        match convert_media(
            item,
            imagemagick.as_ref(),
            ffmpeg.as_ref(),
            &bucket,
            tmp_dir.path(),
            &mut conn,
        )
        .await
        {
            Ok(_) => log::info!("Converted Media {}.", item.id),
            Err(e) => log::error!("Failed to convert Media {}: {:?}", item.id, e),
        }
    }

    if let Some(resources) = cluster_resources.as_ref().filter(|_| !wanted_resources.is_empty()) {
        release_cluster_lock(resources, &wanted_resources).await;
    }

    log::info!("Done converting Media sizes.");
}
