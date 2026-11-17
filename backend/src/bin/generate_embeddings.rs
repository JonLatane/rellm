// Keeps the embedding tables (post_embeddings, event_embeddings, media_embeddings,
// user_profile_embeddings) in step with the content they describe -- see `logic::embeddings`.
//
// This job never loads a model. It sends documents to the embedding service (RELLM_EMBEDDING_SERVICE_URL) and stores the
// vectors that come back; without a service there is nothing it can do, so it says so and exits.
//   * Does nothing unless `SearchSettings.semantic_search_enabled` is on, or when no text needs embedding.
//   * The model is whatever the service runs (it can change; the job follows on its next run and re-embeds).
//   * Stops after `RUN_BUDGET` of work (it runs again every few minutes; a backlog is worked down over several runs).
//     Each kind (posts, events, media, profiles) gets an even share of what's left, and the kind that goes first rotates
//     every run, so a big backlog in one kind (say, an import of posts) can't starve the others.
extern crate diesel;
extern crate rellm;
use std::time::{Duration, Instant};

use rellm::logic::embeddings::{self, EmbeddingKind, EmbeddingServiceUnavailable, SyncContext};
use rellm::{db_connection, init_bin_logging, init_crypto};

const RUN_BUDGET: Duration = Duration::from_secs(240);

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
    if !embeddings::embedding_service_configured() {
        log::error!("{}", embeddings::EMBEDDING_SERVICE_NEEDED);
        return;
    }

    // The model the service runs right now (the registry default if it hasn't answered): rows made by any other model
    // are re-embedded. Waits a few seconds for the service on a fresh start rather than guessing.
    let spec = embeddings::cluster_model_blocking().unwrap_or_else(|| embeddings::active_model(&mut conn));
    log::info!("Embedding with {} ({} dimensions), through the embedding service.", spec.id, spec.dimensions);
    let run_deadline = Instant::now() + RUN_BUDGET;
    let mut ctx = SyncContext { spec, embedder: None, deadline: run_deadline };

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
            // No service to talk to: asking again for the other kinds would just fail the same way.
            Err(e) if e.downcast_ref::<EmbeddingServiceUnavailable>().is_some() => break,
            Err(e) => log::error!(
                "Failed to sync {} embeddings: {:?}. Proceeding through remaining kinds.",
                kind.name(),
                e
            ),
        }
    }
}
