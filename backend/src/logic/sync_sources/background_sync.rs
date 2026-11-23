//! Finishes a just-created/edited paginated StellarWP `SyncSource`'s sync off the request path.
//! `sync_source_after_edit` syncs only the first page inline (a person is waiting) and asks for the
//! rest here.
//!
//! One dedicated worker thread drains a FIFO queue, so background syncs never run more than one at
//! a time however many sources are created or edited at once -- every deploy shares one central
//! Postgres with a small `max_connections` budget (see `db_connection::SERVER_POOL_SIZE`), so this
//! can't be a thread per source. The worker also only holds a database connection for the DB
//! halves of a sync (loading the source, then writing what was fetched); the fetch itself, which
//! can take a minute or more, runs without one. Connections come from a shared one-connection pool
//! (`db_connection::establish_background_pool`) that opens nothing until first used.
//!
//! A thread rather than a child process: the server can't safely `fork` while multi-threaded, and
//! the sync code needs nothing a thread doesn't already have.
//!
//! An edit that lands while its source is syncing marks it for a rerun (see [`SyncQueue`]), so the
//! newest configuration always gets a full sync after the one in flight; that in-flight sync's own
//! fetched data, being for the old configuration, is discarded when it tries to save (see
//! `event_sync::sync_source_calendar`). Failures are logged; the scheduled `bin/sync_sources` job
//! retries.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Condvar, LazyLock, Mutex};

use tonic::{Code, Status};

use super::stellarwp_sync::{
    fetch_stellarwp_pages, is_stellarwp_source, sync_source_stellarwp_fetched, MAX_PAGES,
};
use super::sync_source;
use crate::db_connection::{self, PgPool, PgPooledConnection};
use crate::models;

/// The pending background syncs: sources waiting their turn, the one running now, and whether an
/// edit asked for another sync of it while it ran.
#[derive(Debug, Default)]
pub struct SyncQueue {
    queued: VecDeque<i64>,
    running: Option<i64>,
    rerun: bool,
}

impl SyncQueue {
    /// Asks for a background sync of `source_id`. A source already queued needs nothing more (it
    /// syncs whatever its configuration is by the time its turn comes); one running right now is
    /// marked to sync again when it finishes. Returns whether a worker should be woken.
    pub fn request(&mut self, source_id: i64) -> bool {
        if self.running == Some(source_id) {
            self.rerun = true;
            return false;
        }
        if self.queued.contains(&source_id) {
            return false;
        }
        self.queued.push_back(source_id);
        true
    }

    /// Takes the next source to sync (marking it running), if any.
    pub fn start_next(&mut self) -> Option<i64> {
        let source_id = self.queued.pop_front()?;
        self.running = Some(source_id);
        self.rerun = false;
        Some(source_id)
    }

    /// The running sync is done: requeues its source at the back if an edit asked for another.
    pub fn finish(&mut self) {
        if let Some(source_id) = self.running.take() {
            if std::mem::take(&mut self.rerun) {
                self.queued.push_back(source_id);
            }
        }
    }
}

static QUEUE: LazyLock<(Mutex<SyncQueue>, Condvar)> =
    LazyLock::new(|| (Mutex::new(SyncQueue::default()), Condvar::new()));
static WORKER_RUNNING: AtomicBool = AtomicBool::new(false);
static POOL: LazyLock<PgPool> = LazyLock::new(db_connection::establish_background_pool);

/// Queues a full background sync of `source_id`, starting the worker thread if it isn't running.
pub fn request_background_sync(source_id: i64) {
    let (lock, wake) = &*QUEUE;
    let Ok(mut queue) = lock.lock() else {
        return;
    };
    let should_wake = queue.request(source_id);
    drop(queue);
    ensure_worker();
    if should_wake {
        wake.notify_one();
    }
}

fn ensure_worker() {
    if WORKER_RUNNING
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return;
    }
    let spawned = std::thread::Builder::new()
        .name("sync-source-worker".to_string())
        .spawn(|| {
            worker_loop();
            WORKER_RUNNING.store(false, Ordering::SeqCst);
        });
    if let Err(e) = spawned {
        WORKER_RUNNING.store(false, Ordering::SeqCst);
        log::error!("Failed to spawn the background sync worker: {:?}", crate::logic::log_redaction::safe_error(&e));
    }
}

fn worker_loop() {
    let (lock, wake) = &*QUEUE;
    loop {
        let source_id = {
            let Ok(mut queue) = lock.lock() else {
                return;
            };
            loop {
                if let Some(source_id) = queue.start_next() {
                    break source_id;
                }
                queue = match wake.wait(queue) {
                    Ok(queue) => queue,
                    Err(_) => return,
                };
            }
        };

        // A panic in one source's sync must not take the worker down with it.
        if std::panic::catch_unwind(|| sync_one(source_id)).is_err() {
            log::error!("Background sync of SyncSource {} panicked.", source_id);
        }

        match lock.lock() {
            Ok(mut queue) => queue.finish(),
            Err(_) => return,
        }
    }
}

/// Runs `f` with a pooled connection, which is released as soon as it returns.
fn with_conn<T>(f: impl FnOnce(&mut PgPooledConnection) -> Result<T, Status>) -> Result<T, Status> {
    let mut conn = POOL.get().map_err(|e| {
        log::error!("Background sync couldn't get a DB connection: {:?}", crate::logic::log_redaction::safe_error(&e));
        Status::new(Code::Unavailable, "db_connection_unavailable")
    })?;
    f(&mut conn)
}

fn sync_one(source_id: i64) {
    // Reloaded, so what's synced is whatever configuration is current when this source's turn comes.
    let source = match with_conn(|conn| models::get_sync_source(source_id, conn)) {
        Ok(source) => source,
        // Deleted since the edit that queued this -- nothing to sync.
        Err(e) => {
            log::info!("Background sync of SyncSource {} skipped: {:?}", source_id, crate::logic::log_redaction::safe_error(&e));
            return;
        }
    };
    let result = if is_stellarwp_source(&source) {
        // No connection is held while fetching.
        fetch_stellarwp_pages(&source, MAX_PAGES).and_then(|paged| {
            with_conn(|conn| sync_source_stellarwp_fetched(&source, &paged, conn))
        })
    } else {
        with_conn(|conn| sync_source(&source, conn))
    };
    match result {
        Ok(()) => log::info!("Background sync of SyncSource {} finished.", source_id),
        Err(e) => log::error!("Background sync of SyncSource {} failed: {:?}", source_id, crate::logic::log_redaction::safe_error(&e)),
    }
}
