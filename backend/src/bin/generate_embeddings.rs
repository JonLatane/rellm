// Keeps the embedding tables (post_embeddings, event_embeddings, media_embeddings,
// user_profile_embeddings) in step with the content they describe -- see `logic::embeddings`.
//
// Built for small hardware:
//   * Does nothing (and never loads the model) unless `SearchSettings.semantic_search_enabled` is on,
//     or when no text needs embedding.
//   * In a cluster (`ClusterResources` configured), takes the `CLUSTER_RESOURCE_EMBEDDINGS` lock
//     from the conductor right before loading the model, so only as many instances as its
//     `ClusterResourceLimit` allows (default 1) embed at once. A denied lock just skips this run.
//   * Stops after `RUN_BUDGET` of work (it runs again every few minutes; a backlog is worked down
//     over several runs) and releases the lock. Each kind (posts, events, media, profiles) gets an
//     even share of what's left, and the kind that goes first rotates every run, so a big backlog in
//     one kind (say, an import of posts) can't starve the others.
//   * The model gets `RELLM_EMBEDDING_THREADS` CPU threads (default 2).
// The first run with something to embed downloads the model into `RELLM_EMBEDDING_CACHE_DIR`
// (default ~/.cache/rellm/embedding_models); later runs reuse it.
extern crate diesel;
extern crate rellm;
use std::time::{Duration, Instant};

use rellm::logic::embeddings::{self, EmbeddingKind, ModelUnavailable, SyncContext};
use rellm::logic::{acquire_cluster_lock, release_cluster_lock};
use rellm::protos::{ClusterResource, ClusterResources};
use rellm::{db_connection, init_bin_logging, init_crypto, rpcs};

const RUN_BUDGET: Duration = Duration::from_secs(240);
const DEFAULT_THREADS: usize = 2;

/// `EmbeddingKind::ALL`, starting from a different kind each run (the run's 5-minute slot, mod 4), so
/// no kind is always first in line.
fn rotated_kinds() -> Vec<EmbeddingKind> {
    let slot = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() / 300)
        .unwrap_or(0) as usize;
    let mut kinds = EmbeddingKind::ALL.to_vec();
    let shift = slot % kinds.len();
    kinds.rotate_left(shift);
    kinds
}

pub fn main() {
    init_crypto();
    init_bin_logging();
    let pool = db_connection::establish_job_pool();
    let mut conn = pool.get().expect("Failed to get DB connection");

    if !embeddings::semantic_search_enabled(&mut conn) {
        log::info!("Semantic search is disabled in the server settings; nothing to do.");
        return;
    }

    let cluster_resources: Option<ClusterResources> = rpcs::get_server_configuration_model(&mut conn)
        .expect("Failed to load server configuration")
        .cluster_resources
        .and_then(|v| serde_json::from_value(v).ok());
    let wanted = [ClusterResource::Embeddings];

    // The lock calls are async; this job isn't (the model and Postgres are blocking), so drive just
    // those from a small runtime. `acquire`/`release` are only ever called from this thread.
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("Failed to start async runtime");
    let mut lock_held = false;

    let threads = std::env::var("RELLM_EMBEDDING_THREADS")
        .ok()
        .and_then(|t| t.parse::<usize>().ok())
        .filter(|t| *t > 0)
        .unwrap_or(DEFAULT_THREADS);
    let spec = embeddings::active_model(&mut conn);
    log::info!("Embedding model: {} ({} dimensions).", spec.id, spec.dimensions);
    let mut ctx = SyncContext {
        spec,
        embedder: None,
        deadline: Instant::now() + RUN_BUDGET,
        threads,
        before_model_load: Box::new(|| match cluster_resources.as_ref() {
            // Single-instance servers skip the cluster lock entirely.
            None => true,
            Some(resources) => {
                log::info!("Cluster resources configured; acquiring embeddings lock from conductor...");
                if runtime.block_on(acquire_cluster_lock(resources, &wanted)) {
                    lock_held = true;
                    true
                } else {
                    log::warn!("Could not acquire the embeddings cluster lock in time; skipping this run.");
                    false
                }
            }
        }),
    };

    let run_deadline = ctx.deadline;
    let kinds = rotated_kinds();
    for (turn, kind) in kinds.iter().copied().enumerate() {
        let now = Instant::now();
        if now >= run_deadline {
            break;
        }
        // An even share of the time left among the kinds still to go.
        ctx.deadline = now + (run_deadline - now) / (kinds.len() - turn) as u32;
        match embeddings::sync_embeddings(&mut conn, kind, &mut ctx) {
            Ok(stats) => {
                log::info!(
                    "{} embeddings: {} embedded, {} unchanged, {} with no text.",
                    kind.name(),
                    stats.embedded,
                    stats.unchanged,
                    stats.empty
                );
                if stats.out_of_time {
                    log::info!("{} embeddings used up their share of this run; the rest happens next run.", kind.name());
                }
            }
            // Someone else holds the cluster's embedding slot: no point asking again for the other kinds.
            Err(e) if e.downcast_ref::<ModelUnavailable>().is_some() => break,
            Err(e) => log::error!(
                "Failed to sync {} embeddings: {:?}. Proceeding through remaining kinds.",
                kind.name(),
                e
            ),
        }
    }

    // Free the model's memory, then the cluster slot.
    ctx.embedder = None;
    drop(ctx);
    if lock_held {
        if let Some(resources) = cluster_resources.as_ref() {
            runtime.block_on(release_cluster_lock(resources, &wanted));
        }
    }
}
