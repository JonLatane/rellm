//! The one place a model is loaded and run: the embedding service's `LocalEmbedder`, through `fastembed` (ONNX
//! Runtime). Compiled only with the `embedding-service` cargo feature, so the Rellm server and its jobs contain none
//! of it. Everything model-specific that the *server* needs (names, sizes, similarity thresholds, query/passage
//! prefixes) lives in the registry in `mod.rs`; this file only maps a registry id to its `fastembed` model.
use std::path::PathBuf;

use fastembed::{EmbeddingModel, TextEmbedding, TextInitOptions};

use super::{BoxedEmbedder, ModelSpec, TextEmbedder};

// Longer input is truncated by the tokenizer; documents list their most important text first.
const MAX_TOKENS: usize = 256;

/// The `fastembed` model behind a registry id. Every `MODELS` entry has one (a test checks).
pub fn fastembed_model(id: &str) -> Option<EmbeddingModel> {
    Some(match id {
        "embeddinggemma-300m-int8" => EmbeddingModel::EmbeddingGemma300MQ,
        "embeddinggemma-300m-q4" => EmbeddingModel::EmbeddingGemma300MQ4,
        "embeddinggemma-300m" => EmbeddingModel::EmbeddingGemma300M,
        "multilingual-e5-small" => EmbeddingModel::MultilingualE5Small,
        "paraphrase-multilingual-minilm-l12-v2" => EmbeddingModel::ParaphraseMLMiniLML12V2Q,
        "bge-small-en-v1.5" => EmbeddingModel::BGESmallENV15Q,
        "all-minilm-l6-v2" => EmbeddingModel::AllMiniLML6V2Q,
        _ => return None,
    })
}

/// Where models are cached (and so downloaded to, once): `RELLM_EMBEDDING_CACHE_DIR`, else
/// `~/.cache/rellm/embedding_models`, else `./.embedding_models`. Give the embedding service a volume here so a restart
/// doesn't download the model again.
pub fn model_cache_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("RELLM_EMBEDDING_CACHE_DIR").filter(|d| !d.is_empty()) {
        return PathBuf::from(dir);
    }
    match std::env::var_os("HOME").filter(|h| !h.is_empty()) {
        Some(home) => PathBuf::from(home).join(".cache/rellm/embedding_models"),
        None => PathBuf::from(".embedding_models"),
    }
}

fn normalize(vector: &mut [f32]) {
    let norm = vector.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm > 0.0 {
        vector.iter_mut().for_each(|x| *x /= norm);
    }
}

/// The model run in this process, through `fastembed` (ONNX Runtime).
pub struct LocalEmbedder {
    inner: TextEmbedding,
    spec: &'static ModelSpec,
}

impl LocalEmbedder {
    /// Loads (downloading into `model_cache_dir()` first if need be) the model `spec` names. Blocking, and slow the
    /// first time. ONNX Runtime uses `threads` CPU threads (it would otherwise take every core).
    pub fn load(spec: &'static ModelSpec, threads: usize) -> anyhow::Result<LocalEmbedder> {
        let model = fastembed_model(spec.id).ok_or_else(|| anyhow::anyhow!("no fastembed model for `{}`", spec.id))?;
        let inner = TextEmbedding::try_new(
            TextInitOptions::new(model)
                .with_cache_dir(model_cache_dir())
                .with_intra_threads(threads.max(1))
                .with_max_length(MAX_TOKENS)
                .with_show_download_progress(false),
        )?;
        Ok(LocalEmbedder { inner, spec })
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
        self.embed_with_prefix(self.spec.document_prefix, texts)
    }
    fn embed_query(&mut self, text: &str) -> anyhow::Result<Vec<f32>> {
        Ok(self.embed_with_prefix(self.spec.query_prefix, &[text.to_string()])?.remove(0))
    }
}

/// `LocalEmbedder::load`, boxed: what the embedding service binary serves.
pub fn load_embedder_local(spec: &'static ModelSpec, threads: usize) -> anyhow::Result<BoxedEmbedder> {
    Ok(Box::new(LocalEmbedder::load(spec, threads)?))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_registered_model_has_a_fastembed_model_and_nothing_else_does() {
        for spec in super::super::MODELS.iter() {
            assert!(fastembed_model(spec.id).is_some(), "{} has no fastembed model", spec.id);
        }
        assert!(fastembed_model("not-a-model").is_none());
    }

    #[test]
    fn vectors_are_unit_length_after_normalizing() {
        let mut v = vec![3.0, 4.0, 0.0];
        normalize(&mut v);
        assert!((v.iter().map(|x| x * x).sum::<f32>() - 1.0).abs() < 1e-6);
    }
}
