extern crate diesel;
extern crate rellm;

use rellm::logic::{audio_media, strip_derived_audio_sizes};
use rellm::{db_connection, init_bin_logging, init_crypto, object_storage_connection};

/// Rows scanned per DB round-trip -- just a page size (see `audio_media`'s `min_id` paging).
const BATCH_SIZE: i64 = 50;

/// One-off, manually-run: queues every already-converted audio `Media` item for regeneration, so
/// audio uploaded before the current conversion recipe gets what newer uploads do -- compressed
/// AAC `small`/`medium`/`large` copies, waveforms (WAV/FLAC never had any), embedded cover art
/// (`AUDIO_COVER_ART_*`), and tag seeding of blank credits and a still-default name from the file's
/// `title` tag (see `logic::media::media_conversion::convert_media`).
///
/// Strips each item's derived sizes (deleting their object storage objects) and marks it
/// unprocessed, so the ordinary `convert_media_sizes` job -- already re-invoked on an interval by
/// `background_jobs.sh` -- regenerates them on its next passes. Items whose original is no longer
/// downloadable are left untouched. Not idempotent in effect: re-running requeues everything again
/// (including items that legitimately end up with no extra sizes, e.g. low-bitrate files with no
/// art), so run it once per deployment.
///
/// Not wired into any schedule -- run it by hand, e.g.:
/// ```sh
/// DATABASE_URL=... OBJECT_STORAGE_ENDPOINT=... cargo run --release --bin reconvert_audio_media
/// ```
#[tokio::main]
async fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Finding processed audio Media to reconvert...");

    let pool = db_connection::establish_job_pool();
    let mut conn = pool.get().expect("Failed to get DB connection");
    let bucket = object_storage_connection::get_and_test_bucket()
        .await
        .expect("Failed to connect to object storage");

    let mut min_id = 0i64;
    let mut queued = 0;
    let mut skipped = 0;

    loop {
        let batch = audio_media(&mut conn, min_id, BATCH_SIZE).expect("Failed to load audio Media");
        if batch.is_empty() {
            break;
        }
        min_id = batch.last().expect("just checked non-empty").id;

        for item in &batch {
            match strip_derived_audio_sizes(item, &bucket, &mut conn).await {
                Ok(true) => queued += 1,
                Ok(false) => {
                    log::warn!("Media {}: original unavailable; leaving as-is.", item.id);
                    skipped += 1;
                }
                Err(e) => {
                    log::error!("Media {}: failed to queue for reconversion: {:?}", item.id, e);
                    skipped += 1;
                }
            }
        }
    }

    log::info!(
        "Done. Queued {} audio Media item(s) for regeneration by convert_media_sizes; skipped {}.",
        queued,
        skipped
    );
}
