extern crate diesel;
extern crate rellm;
use rellm::logic::recompute_server_media_usage_bytes;
use rellm::{db_connection, init_bin_logging, init_crypto};

/// Runs every 3 minutes (see `background_jobs.sh`) to fully recompute
/// `MediaSettings.server_media_usage_bytes`/`server_media_usage_calculated_at` from the `media`
/// table, self-healing any drift the incremental `adjust_server_media_usage_bytes` call sites
/// (`CreateMedia`, deletes, size conversions -- see `logic::server_storage_usage`'s own doc)
/// missed, e.g. a cascading delete that doesn't go through them at all.
pub fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Calculating server Media usage...");

    let pool = db_connection::establish_pool();
    let mut conn = pool.get().expect("Failed to get DB connection");
    match recompute_server_media_usage_bytes(&mut conn) {
        Ok(()) => log::info!("Done calculating server Media usage."),
        Err(e) => log::error!("Failed to calculate server Media usage: {:?}", e),
    }
}
