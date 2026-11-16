use fastembed::{TextEmbedding, TextInitOptions};

use super::{model_cache_dir, normalize, ModelSpec, MAX_TOKENS};

/// Turns text into L2-normalized vectors. This is the seam between *what* is embedded and *where the
/// model runs*: `LocalEmbedder` runs it in this process; a client of a cluster-shared model service
/// can implement the same trait, and nothing that calls it (the job, search) changes.
pub trait TextEmbedder: Send {
    /// The model this embedder runs -- its vectors are only comparable with the same model's.
    fn spec(&self) -> &'static ModelSpec;
    /// One vector per document text, in order. Empty texts are the caller's to skip.
    fn embed_documents(&mut self, texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>>;
    /// The vector for a search query (models that tell queries from documents get their query prefix).
    fn embed_query(&mut self, text: &str) -> anyhow::Result<Vec<f32>>;
}

pub type BoxedEmbedder = Box<dyn TextEmbedder>;

/// Loads the embedder for `spec`, downloading the model first if it isn't cached. Blocking, and slow
/// the first time. The one place that decides where the model runs.
pub fn load_embedder(spec: &'static ModelSpec, threads: usize) -> anyhow::Result<BoxedEmbedder> {
    load_embedder_with(
        spec,
        threads,
        super::embedding_service_config(),
        super::embedding_service_required(),
    )
}

/// `load_embedder` with its two environment inputs passed in:
///   * a cluster-shared model service configured -> embed through it (and it is *its* model: `spec` is only what an
///     in-process load would use -- see `search_configuration`, which resolves the cluster's model);
///   * none configured and `required` (`RELLM_EMBEDDING_SERVICE_REQUIRED`) -> refuse: servers and jobs must never
///     load a model of their own, so a missing `RELLM_EMBEDDING_SERVICE_URL` is a loud error, not a silent extra
///     ~1GB copy of the model per process;
///   * otherwise -> load the model in this process.
pub fn load_embedder_with(
    spec: &'static ModelSpec,
    threads: usize,
    service: Option<(String, Option<String>)>,
    required: bool,
) -> anyhow::Result<BoxedEmbedder> {
    match service {
        Some((url, secret)) => Ok(Box::new(super::RemoteEmbedder::connect(&url, secret)?)),
        None if required => Err(anyhow::anyhow!(
            "RELLM_EMBEDDING_SERVICE_REQUIRED is set but RELLM_EMBEDDING_SERVICE_URL is not: refusing to load the {} model in this process",
            spec.id
        )),
        None => Ok(Box::new(LocalEmbedder::load(spec, threads)?)),
    }
}

/// Like `load_embedder` but always runs the model in this process, ignoring any configured model service:
/// what the model service itself uses.
pub fn load_embedder_local(spec: &'static ModelSpec, threads: usize) -> anyhow::Result<BoxedEmbedder> {
    Ok(Box::new(LocalEmbedder::load(spec, threads)?))
}

/// The model run in this process, through `fastembed` (ONNX Runtime).
pub struct LocalEmbedder {
    inner: TextEmbedding,
    spec: &'static ModelSpec,
}

impl LocalEmbedder {
    /// ONNX Runtime uses `threads` CPU threads (it would otherwise take every core, which is rude on
    /// small shared hardware).
    pub fn load(spec: &'static ModelSpec, threads: usize) -> anyhow::Result<LocalEmbedder> {
        let model = TextEmbedding::try_new(
            TextInitOptions::new(spec.model().clone())
                .with_cache_dir(model_cache_dir())
                .with_intra_threads(threads.max(1))
                .with_max_length(MAX_TOKENS)
                .with_show_download_progress(false),
        )?;
        Ok(LocalEmbedder { inner: model, spec })
    }

    fn embed_with_prefix(&mut self, prefix: &str, texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>> {
        let prefixed: Vec<String> = texts.iter().map(|t| format!("{}{}", prefix, t)).collect();
        let mut vectors = self.inner.embed(&prefixed, Some(32))?;
        vectors.iter_mut().for_each(|v| normalize(v));
        Ok(vectors)
    }
}

impl TextEmbedder for LocalEmbedder {
    fn spec(&self) -> &'static ModelSpec {
        self.spec
    }
    fn embed_documents(&mut self, texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>> {
        self.embed_with_prefix(self.spec.document_prefix(), texts)
    }
    fn embed_query(&mut self, text: &str) -> anyhow::Result<Vec<f32>> {
        Ok(self.embed_with_prefix(self.spec.query_prefix(), &[text.to_string()])?.remove(0))
    }
}
