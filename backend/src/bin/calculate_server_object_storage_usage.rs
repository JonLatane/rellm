extern crate diesel;
extern crate rellm;
use rellm::logic::recompute_server_object_storage_usage_bytes;
use rellm::{db_connection, init_bin_logging, init_crypto, object_storage_connection};

/// Runs every 4h, at a randomized offset within that interval (see `background_jobs.sh`'s
/// `random` delay support), to fully list+sum every object in the server's object storage bucket
/// and write the total to `MediaSettings.server_object_storage_usage_bytes`/
/// `server_object_storage_usage_calculated_at` -- an independent drift check against
/// `server_media_usage_bytes` (which is derived from the `media` table, not object storage
/// itself). The randomized offset avoids every instance in a multi-instance cluster hitting object
/// storage's list API at the same wall-clock moment (e.g. right after a rolling deploy restarts
/// every instance's `background_jobs.sh` together).
#[tokio::main]
async fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Calculating server object storage usage...");

    let pool = db_connection::establish_pool();
    let mut conn = pool.get().expect("Failed to get DB connection");
    let bucket = match object_storage_connection::get_and_test_bucket().await {
        Ok(bucket) => bucket,
        Err(e) => {
            log::error!("Failed to connect to object storage: {:?}", e);
            std::process::exit(1);
        }
    };

    match recompute_server_object_storage_usage_bytes(&mut conn, &bucket).await {
        Ok(()) => log::info!("Done calculating server object storage usage."),
        Err(e) => log::error!("Failed to calculate server object storage usage: {:?}", e),
    }
}
