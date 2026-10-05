extern crate diesel;
extern crate rellm;

use rellm::logic::{
    audio_media, backfill_audio_metadata, strip_derived_audio_sizes, FFmpeg, MetadataBackfill,
};
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
/// With either flag below, it instead leaves sizes alone and only seeds *unset* metadata from each
/// item's original (see `backfill_audio_metadata`) -- much cheaper, safe to re-run, and nothing is
/// ever overwritten. Give both to do both in one download per item.
///   * `--stored-metadata-only`: extract what's stored in the file's tags -- artist, album, composer,
///     director, ..., and any BPM/key tag. (Fills a credit an owner deliberately cleared, too.)
///   * `--calculated-metadata-only`: estimate `start_bpm`/`end_bpm`/`min_bpm`/`max_bpm`/`start_key`/
///     `end_key` from the audio itself. Run it *after* (or together with) `--stored-metadata-only`:
///     a file's own BPM/key tag then wins over the estimate, since only unset fields are filled.
///
/// Not wired into any schedule -- run it by hand, e.g.:
/// ```sh
/// DATABASE_URL=... OBJECT_STORAGE_ENDPOINT=... cargo run --release --bin reconvert_audio_media
/// DATABASE_URL=... OBJECT_STORAGE_ENDPOINT=... cargo run --release --bin reconvert_audio_media -- \
///     --stored-metadata-only --calculated-metadata-only
/// ```
#[tokio::main]
async fn main() {
    let mut which = MetadataBackfill { stored: false, calculated: false };
    for arg in std::env::args().skip(1) {
        match arg.as_str() {
            "--stored-metadata-only" => which.stored = true,
            "--calculated-metadata-only" => which.calculated = true,
            other => {
                eprintln!(
                    "Unknown argument {other:?}. Usage: reconvert_audio_media [--stored-metadata-only] [--calculated-metadata-only]"
                );
                std::process::exit(2);
            }
        }
    }
    let metadata_only = which.stored || which.calculated;

    init_crypto();
    init_bin_logging();
    log::info!(
        "Finding processed audio Media to {}...",
        if metadata_only { "backfill metadata for" } else { "reconvert" }
    );

    let ffmpeg = if metadata_only {
        Some(FFmpeg::detect().expect("ffmpeg/ffprobe not found on $PATH; cannot read or analyze audio"))
    } else {
        None
    };
    let tmp_dir = std::env::temp_dir();

    let pool = db_connection::establish_job_pool();
    let mut conn = pool.get().expect("Failed to get DB connection");
    let bucket = object_storage_connection::get_and_test_bucket()
        .await
        .expect("Failed to connect to object storage");

    let mut min_id = 0i64;
    let mut queued = 0;
    let mut updated = 0;
    let mut skipped = 0;

    loop {
        let batch = audio_media(&mut conn, min_id, BATCH_SIZE).expect("Failed to load audio Media");
        if batch.is_empty() {
            break;
        }
        min_id = batch.last().expect("just checked non-empty").id;

        for item in &batch {
            if let Some(ffmpeg) = &ffmpeg {
                match backfill_audio_metadata(item, which, ffmpeg, &bucket, &tmp_dir, &mut conn).await {
                    Ok(true) => {
                        log::info!("Media {}: metadata updated.", item.id);
                        updated += 1;
                    }
                    Ok(false) => {}
                    Err(e) => {
                        log::error!("Media {}: failed to backfill metadata: {:#}", item.id, e);
                        skipped += 1;
                    }
                }
                continue;
            }
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

    if metadata_only {
        log::info!("Done. Updated metadata of {} audio Media item(s); failed {}.", updated, skipped);
    } else {
        log::info!(
            "Done. Queued {} audio Media item(s) for regeneration by convert_media_sizes; skipped {}.",
            queued,
            skipped
        );
    }
}
