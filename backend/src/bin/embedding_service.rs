// The cluster-shared model service -- the ONLY place a Rellm deployment loads an embedding model (cargo feature
// `embedding-service`; the server and job binaries are built without it, so they can't). Loads ONE model and serves it
// over gRPC to every namespace's Rellm servers and `generate_embeddings` jobs, so a cluster pays the model's RAM once --
// see `logic::embeddings::model_service` and `internal_protos/rellm_internal.proto`. Required: without it there are no
// embeddings and search is full-text only.
//
//   RELLM_EMBEDDING_SERVICE_MODEL   model id (default: the registry default, harrier-oss-v1-270m-384)
//   RELLM_EMBEDDING_SERVICE_ADDR    listen address (default 0.0.0.0:8090)
//   RELLM_EMBEDDING_SERVICE_SECRET  callers must send it (required unless RELLM_EMBEDDING_SERVICE_INSECURE=1)
//   RELLM_EMBEDDING_THREADS         CPU threads for the model that embeds documents (default 2; the Deployment sets 4)
//   RELLM_EMBEDDING_QUERY_THREADS   CPU threads for the second copy of the model that answers search queries, so a search never
//                                   waits for a document being embedded (default 2; 0 = no second copy, one model does both)
//   RELLM_EMBEDDING_CACHE_DIR       where the model is downloaded (give it a volume to survive restarts)
// It stores nothing and never logs text. Don't expose it outside the cluster network.
extern crate rellm;
use rellm::logic::embeddings::{default_model, load_embedder_local, model_spec, model_service};
use rellm::{init_bin_logging, init_crypto};

#[tokio::main]
async fn main() {
    init_crypto();
    init_bin_logging();

    let spec = match std::env::var("RELLM_EMBEDDING_SERVICE_MODEL") {
        Ok(id) if !id.is_empty() => model_spec(&id).unwrap_or_else(|| {
            panic!("RELLM_EMBEDDING_SERVICE_MODEL `{}` isn't a known model", id)
        }),
        _ => default_model(),
    };
    let addr = std::env::var("RELLM_EMBEDDING_SERVICE_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:8090".to_string())
        .parse()
        .expect("RELLM_EMBEDDING_SERVICE_ADDR must be host:port");
    let secret = std::env::var("RELLM_EMBEDDING_SERVICE_SECRET").ok().filter(|s| !s.is_empty());
    if secret.is_none() && std::env::var("RELLM_EMBEDDING_SERVICE_INSECURE").as_deref() != Ok("1") {
        panic!("Set RELLM_EMBEDDING_SERVICE_SECRET (or RELLM_EMBEDDING_SERVICE_INSECURE=1 for a trusted network)");
    }
    let threads = std::env::var("RELLM_EMBEDDING_THREADS")
        .ok()
        .and_then(|t| t.parse::<usize>().ok())
        .filter(|t| *t > 0)
        .unwrap_or(2);

    let query_threads = std::env::var("RELLM_EMBEDDING_QUERY_THREADS").ok().and_then(|t| t.parse::<usize>().ok()).unwrap_or(2);

    log::info!("Loading embedding model {} (downloads it the first time)...", spec.id);
    // Always in-process here: this *is* the model service.
    let embedder = tokio::task::spawn_blocking(move || load_embedder_local(spec, threads))
        .await
        .expect("model loading task")
        .expect("failed to load the embedding model");
    if query_threads == 0 {
        model_service::serve(addr, embedder, secret).await.expect("embedding service failed");
        return;
    }
    // A second copy for search queries (the weights are a mapped file, so they are not held twice).
    let queries = tokio::task::spawn_blocking(move || load_embedder_local(spec, query_threads))
        .await
        .expect("model loading task")
        .expect("failed to load the embedding model for queries");
    model_service::serve_with_query_model(addr, embedder, queries, secret).await.expect("embedding service failed");
}
