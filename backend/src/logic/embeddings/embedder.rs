use super::ModelSpec;

/// Turns text into L2-normalized vectors. This is the seam between *what* is embedded and *where the model runs*. The
/// model only ever runs in the cluster-shared model service (`RemoteEmbedder` is how a server or job reaches it); the
/// service itself is built around `LocalEmbedder` (cargo feature `embedding-service`), which is the one implementation
/// that loads a model. Tests use fakes.
pub trait TextEmbedder: Send {
    /// The model this embedder runs -- its vectors are only comparable with the same model's.
    fn spec(&self) -> &'static ModelSpec;
    /// One vector per document text, in order. Empty texts are the caller's to skip.
    fn embed_documents(&mut self, texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>>;
    /// The vector for a search query (models that tell queries from documents get their query prefix).
    fn embed_query(&mut self, text: &str) -> anyhow::Result<Vec<f32>>;
}

pub type BoxedEmbedder = Box<dyn TextEmbedder>;

/// What a server or job says when it has no embedding service to talk to.
pub const EMBEDDING_SERVICE_NEEDED: &str = "Semantic search needs the embedding service: set RELLM_EMBEDDING_SERVICE_URL \
     (and RELLM_EMBEDDING_SERVICE_SECRET) to a running `embedding_service` -- Rellm servers and jobs never load a model themselves";

/// The embedder for this process: a client of the embedding service (`RELLM_EMBEDDING_SERVICE_URL`), whose model is
/// whatever the service runs. There is deliberately no in-process fallback: without the service this is an error, and
/// semantic search is simply unavailable (full-text only) until one is configured.
pub fn load_embedder() -> anyhow::Result<BoxedEmbedder> {
    match super::embedding_service_config() {
        Some((url, secret)) => Ok(Box::new(super::RemoteEmbedder::connect(&url, secret)?)),
        None => Err(anyhow::anyhow!(EMBEDDING_SERVICE_NEEDED)),
    }
}
