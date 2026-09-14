extern crate diesel;
extern crate rellm;

use rellm::logic::{media_with_quicktime_resized_sizes, strip_quicktime_resized_sizes};
use rellm::{db_connection, init_bin_logging, init_crypto, minio_connection};

/// Rows scanned per DB round-trip -- just a page size (see `media_with_quicktime_resized_sizes`'s
/// `min_id` paging), not a retry-friendly batch: unlike `convert_media_sizes`, this isn't
/// re-invoked on any schedule, so a whole backlog is worked down within one run.
const BATCH_SIZE: i64 = 50;

/// One-off, manually-run cleanup for `Media` rows whose resized (`small`/`medium`/`large`) copies
/// are still tagged `video/quicktime` from before `logic::media_conversion::resized_content_type`
/// started re-muxing them to `video/mp4`. Chrome refuses to play `video/quicktime` inline when a
/// media URL is navigated to directly (e.g. opened/shared in its own tab), downloading it instead
/// regardless of the actual codec inside -- so those rows currently trigger a download in Chrome
/// instead of playing.
///
/// Strips the stale `video/quicktime` sizes (deleting their MinIO objects) and marks each affected
/// row unprocessed, so the ordinary `convert_media_sizes` job -- already re-invoked on an interval
/// by `background_jobs.sh`, and fixed by the same change that added `resized_content_type` -- picks
/// it back up and regenerates correctly-tagged MP4 copies on its next pass. Rows whose original is
/// no longer downloadable from MinIO are left untouched, since there'd be no source to regenerate
/// from.
///
/// Not wired into any schedule or the server image -- run it by hand once per affected deployment,
/// e.g.:
/// ```sh
/// DATABASE_URL=... MINIO_ENDPOINT=... cargo run --release --bin reencode_quicktime_media
/// ```
#[tokio::main]
async fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Finding Media with QuickTime-tagged resized copies...");

    log::info!("Connecting to DB and MinIO...");
    let pool = db_connection::establish_pool();
    let mut conn = pool.get().expect("Failed to get DB connection");
    let bucket = minio_connection::get_and_test_bucket()
        .await
        .expect("Failed to connect to MinIO");

    let mut min_id = 0i64;
    let mut stripped = 0;
    let mut skipped = 0;

    loop {
        let pending = media_with_quicktime_resized_sizes(&mut conn, min_id, BATCH_SIZE)
            .expect("Failed to load Media with QuickTime-tagged resized sizes");
        if pending.is_empty() {
            break;
        }
        min_id = pending.last().expect("just checked non-empty").id;

        for item in &pending {
            match strip_quicktime_resized_sizes(item, &bucket, &mut conn).await {
                Ok(true) => stripped += 1,
                Ok(false) => {
                    log::warn!(
                        "Media {}: original unavailable (or nothing to strip); leaving as-is.",
                        item.id
                    );
                    skipped += 1;
                }
                Err(e) => {
                    log::error!("Media {}: failed to strip resized sizes: {:?}", item.id, e);
                    skipped += 1;
                }
            }
        }
    }

    log::info!(
        "Done. Stripped {} Media item(s) (now queued for regeneration by convert_media_sizes); \
         skipped {} (original unavailable, nothing to strip, or errored).",
        stripped,
        skipped
    );
}
