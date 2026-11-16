// The per-namespace vector search service -- see `logic::embeddings::vector_service`. One pod per namespace:
// keeps all of the namespace's embeddings in a USearch index and answers nearest-neighbor queries for its
// Rellm servers, so they neither hold nor scan the vectors themselves.
//
//   DATABASE_URL                     the namespace's Postgres (read-only access is enough)
//   RELLM_VECTOR_SERVICE_ADDR        listen address (default 0.0.0.0:8091)
//   RELLM_VECTOR_SERVICE_SECRET      callers must send it (required unless RELLM_VECTOR_SERVICE_INSECURE=1)
//   RELLM_VECTOR_SERVICE_MODEL       the model whose vectors to index; by default the cluster model service's
//                                    (RELLM_EMBEDDING_SERVICE_URL), else the registry default
// Don't expose it outside the namespace's network. Built with `--features vector-service`.
extern crate diesel;
extern crate rellm;
use std::time::Duration;

use rellm::logic::embeddings::vector_service::{run_indexer, serve, VectorIndexes};
use rellm::logic::embeddings::{cluster_model_blocking, default_model, embedding_service_configured, model_spec};
use rellm::{db_connection, init_bin_logging, init_crypto};

#[tokio::main]
async fn main() {
    init_crypto();
    init_bin_logging();

    let spec = match std::env::var("RELLM_VECTOR_SERVICE_MODEL") {
        Ok(id) if !id.is_empty() => model_spec(&id).unwrap_or_else(|| panic!("RELLM_VECTOR_SERVICE_MODEL `{}` isn't a known model", id)),
        _ if embedding_service_configured() => loop {
            // Index whatever the cluster's model service runs -- wait for it rather than guess.
            match tokio::task::spawn_blocking(cluster_model_blocking).await.expect("probe task") {
                Some(spec) => break spec,
                None => {
                    log::warn!("Waiting for the cluster's embedding model service to say which model it runs...");
                    tokio::time::sleep(Duration::from_secs(10)).await;
                }
            }
        },
        _ => default_model(),
    };
    let addr = std::env::var("RELLM_VECTOR_SERVICE_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:8091".to_string())
        .parse()
        .expect("RELLM_VECTOR_SERVICE_ADDR must be host:port");
    let secret = std::env::var("RELLM_VECTOR_SERVICE_SECRET").ok().filter(|s| !s.is_empty());
    if secret.is_none() && std::env::var("RELLM_VECTOR_SERVICE_INSECURE").as_deref() != Ok("1") {
        panic!("Set RELLM_VECTOR_SERVICE_SECRET (or RELLM_VECTOR_SERVICE_INSECURE=1 for a trusted network)");
    }

    let pool = db_connection::establish_job_pool();
    let conn = pool.get().expect("Failed to get DB connection");
    let indexes = VectorIndexes::new(spec);
    log::info!("Indexing {} vectors (building in the background; searches say 'not ready' until each kind is built).", spec.id);
    {
        let indexes = indexes.clone();
        std::thread::Builder::new()
            .name("vector-indexer".to_string())
            .spawn(move || run_indexer(indexes, conn))
            .expect("failed to start the indexer thread");
    }
    serve(addr, indexes, secret).await.expect("vector search service failed");
}
