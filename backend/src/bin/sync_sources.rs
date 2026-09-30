extern crate diesel;
extern crate rellm;
use std::time::{Duration, SystemTime};

use diesel::*;
use rellm::logic::sync_source;
use rellm::models::SyncSource;
use rellm::schema::sync_sources;
use rellm::{db_connection, init_bin_logging, init_crypto};

pub fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Syncing Sync Sources...");
    log::info!("Connecting to DB...");
    let pool = db_connection::establish_job_pool();
    let mut conn = pool.get().expect("Failed to get DB connection");

    let sources = sync_sources::table
        .load::<SyncSource>(&mut conn)
        .expect("Failed to load SyncSources");

    let now = SystemTime::now();
    let due_sources: Vec<SyncSource> = sources
        .into_iter()
        .filter(|source| is_due(source, now))
        .collect();
    log::info!("{} SyncSource(s) due for sync.", due_sources.len());

    for source in due_sources {
        log::info!("Syncing SyncSource {}...", source.id);
        match sync_source(&source, &mut conn) {
            Ok(()) => log::info!("Synced SyncSource {}.", source.id),
            Err(e) => log::error!(
                "Failed to sync SyncSource {}: {:?}. Proceeding through remaining sources.",
                source.id,
                e
            ),
        }
    }
    log::info!("Done Syncing Sync Sources.");
}

/// A source with no prior sync is always due. Otherwise it's due once
/// `sync_interval_seconds` has elapsed since `last_synced_at`.
fn is_due(source: &SyncSource, now: SystemTime) -> bool {
    match source.last_synced_at {
        None => true,
        Some(last_synced_at) => {
            let interval = Duration::from_secs(source.sync_interval_seconds as u64);
            match last_synced_at.checked_add(interval) {
                Some(next_sync_at) => now >= next_sync_at,
                None => true,
            }
        }
    }
}
