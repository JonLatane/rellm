//! The one place a model is loaded and run: the embedding service's `LocalEmbedder`, on ONNX Runtime -- through `fastembed`
//! for the models it knows, or through `OnnxEngine` (ONNX Runtime directly) for the ones it doesn't. Compiled only with
//! the `embedding-service` cargo feature, so the Rellm server and its jobs contain none of it. Everything model-specific
//! that the *server* needs (names, sizes, similarity thresholds, query/passage prefixes) lives in the registry in
//! `mod.rs`; this file only maps a registry id to a way of running it.
use std::path::PathBuf;

use fastembed::{EmbeddingModel, QuantizationMode, TextEmbedding, TextInitOptions};
use ort::{environment::Environment, session::Session, value::Tensor};
use tokenizers::{Tokenizer, TruncationParams};

use super::{BoxedEmbedder, ModelSpec, TextEmbedder};

/// ONNX Runtime allows one environment per process, and a process (the service, or a test run) can load models both
/// through fastembed and through `OnnxEngine`, so they all share this one.
fn environment() -> anyhow::Result<Environment> {
    static ENVIRONMENT: std::sync::Mutex<Option<Environment>> = std::sync::Mutex::new(None);
    let mut guard = ENVIRONMENT.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
    if let Some(environment) = guard.as_ref() {
        return Ok(environment.clone());
    }
    let environment = ort::init().build().map_err(|e| anyhow::anyhow!("initializing ONNX Runtime: {e}"))?;
    *guard = Some(environment.clone());
    Ok(environment)
}

// Longer input is truncated by the tokenizer; documents list their most important text first.
const MAX_TOKENS: usize = 256;

/// Texts per ONNX Runtime run for models that can batch.
const BATCH_SIZE: usize = 32;

/// Texts per ONNX Runtime run for `model`. A dynamically quantized model (`embeddinggemma-300m-int8`, the default, and
/// `all-minilm-l6-v2`) can't be batched: fastembed fails any call with more texts than the batch size, because dynamic
/// quantization scales each batch by its own data range, so a text's vector would depend on which others shared its
/// batch. It's embedded one text at a time instead, which makes its vector the same wherever it's embedded (a query
/// embedded alone matches the same text embedded in a document batch) and keeps memory flat: ONNX Runtime's working
/// set grows with texts-per-run (a 64-text run peaked ~3GB above one text per run in a local measurement), which is the
/// likely reason the 900Mi service was being OOMKilled while backfilling.
fn batch_size_for(model: &EmbeddingModel) -> usize {
    match TextEmbedding::get_quantization_mode(model) {
        QuantizationMode::Dynamic => 1,
        _ => BATCH_SIZE,
    }
}

/// A registry model fastembed has no built-in entry for: its ONNX export and tokenizer come from the Hugging Face Hub and
/// run on `OnnxEngine`. Revisions are pinned to commits so a change to either repository can't alter what a deployed
/// service loads (the ONNX export is a third party's).
struct OnnxModel {
    /// Hub repo with `tokenizer.json`.
    tokenizer_repo: &'static str,
    tokenizer_revision: &'static str,
    /// Hub repo with the ONNX export, the model file in it, and the external weights file the model file refers to (it has
    /// to sit next to the model file, which the Hub cache layout guarantees).
    onnx_repo: &'static str,
    onnx_revision: &'static str,
    onnx_file: &'static str,
    onnx_data_file: &'static str,
    /// The graph's output that is already the pooled, normalized sentence embedding.
    output_name: &'static str,
}

/// Microsoft's Harrier (MIT): last-token pooling and normalization are inside the ONNX graph (`sentence_embedding`), which
/// fastembed's own pooling modes (CLS, mean) couldn't do. The int8 export is dynamically quantized, so it is run one
/// text at a time (see `batch_size_for`).
const HARRIER_270M: OnnxModel = OnnxModel {
    tokenizer_repo: "microsoft/harrier-oss-v1-270m",
    tokenizer_revision: "31de22b673913c7d658c0f03f792d77c2dcf8ebd",
    onnx_repo: "onnx-community/harrier-oss-v1-270m-ONNX",
    onnx_revision: "d59c919d0159aea2c19ed7d04288fcdd048d0f9c",
    onnx_file: "onnx/model_quantized.onnx",
    onnx_data_file: "onnx/model_quantized.onnx_data",
    output_name: "sentence_embedding",
};

/// The custom ONNX model behind a registry id, for the ones `fastembed_model` has no entry for.
fn onnx_model(id: &str) -> Option<&'static OnnxModel> {
    match id {
        // Harrier's vectors are 640-dimensional; the registry entry cuts them to the first 384 (see `embed_with_prefix`).
        "harrier-oss-v1-270m-384" => Some(&HARRIER_270M),
        _ => None,
    }
}

/// ONNX Runtime running an `OnnxModel`, one text per run. The model is loaded straight from its cached file, so ONNX Runtime
/// maps the weights (a ~330MB external file) instead of holding a copy in memory: through fastembed's in-memory loader
/// the same model needed >1GiB just to start and sat at ~715MiB afterwards, against ~400MiB this way.
struct OnnxEngine {
    session: Session,
    tokenizer: Tokenizer,
    output_name: &'static str,
}

impl OnnxEngine {
    /// Downloads (once, into `model_cache_dir()`; later loads read the cache) and loads the model.
    fn load(model: &OnnxModel, threads: usize) -> anyhow::Result<OnnxEngine> {
        use hf_hub::{api::sync::ApiBuilder, Repo, RepoType};
        let api = ApiBuilder::new().with_cache_dir(model_cache_dir()).with_progress(false).build()?;
        let fetch = |repo: &str, revision: &str, file: &str| -> anyhow::Result<PathBuf> {
            api.repo(Repo::with_revision(repo.to_string(), RepoType::Model, revision.to_string()))
                .get(file)
                .map_err(|e| anyhow::anyhow!("fetching {repo}/{file}: {e}"))
        };
        let tokenizer_path = fetch(model.tokenizer_repo, model.tokenizer_revision, "tokenizer.json")?;
        let onnx_path = fetch(model.onnx_repo, model.onnx_revision, model.onnx_file)?;
        fetch(model.onnx_repo, model.onnx_revision, model.onnx_data_file)?;

        let mut tokenizer = Tokenizer::from_file(&tokenizer_path).map_err(|e| anyhow::anyhow!("loading the tokenizer: {e}"))?;
        tokenizer.with_padding(None); // one text per run: nothing to pad
        tokenizer
            .with_truncation(Some(TruncationParams { max_length: MAX_TOKENS, ..Default::default() }))
            .map_err(|e| anyhow::anyhow!("configuring the tokenizer: {e}"))?;

        let mut builder = Session::builder(&environment()?)
            .map_err(|e| anyhow::anyhow!("creating the ONNX Runtime session: {e}"))?
            .with_intra_threads(threads.max(1))
            .map_err(|e| anyhow::anyhow!("configuring the ONNX Runtime session: {e}"))?;
        let session = builder.commit_from_file(&onnx_path).map_err(|e| anyhow::anyhow!("loading {}: {e}", model.onnx_file))?;
        Ok(OnnxEngine { session, tokenizer, output_name: model.output_name })
    }

    fn embed(&mut self, text: &str) -> anyhow::Result<Vec<f32>> {
        let encoding = self.tokenizer.encode(text, true).map_err(|e| anyhow::anyhow!("tokenizing: {e}"))?;
        let length = encoding.get_ids().len();
        let ids: Vec<i64> = encoding.get_ids().iter().map(|&id| id as i64).collect();
        let mask: Vec<i64> = encoding.get_attention_mask().iter().map(|&m| m as i64).collect();
        let outputs = self.session.run(ort::inputs![
            "input_ids" => Tensor::from_array(([1usize, length], ids))?,
            "attention_mask" => Tensor::from_array(([1usize, length], mask))?,
        ])?;
        let (_, vector) = outputs[self.output_name].try_extract_tensor::<f32>()?;
        Ok(vector.to_vec())
    }
}

/// How a `LocalEmbedder` runs its model.
enum Engine {
    Fastembed(TextEmbedding),
    Onnx(OnnxEngine),
}

/// The `fastembed` model behind a registry id (the built-in ones; see `onnx_model` for the rest). Every `MODELS` entry has one (a test checks).
pub fn fastembed_model(id: &str) -> Option<EmbeddingModel> {
    Some(match id {
        // Same model as `embeddinggemma-300m-int8`; `embed_with_prefix` cuts its vectors to the registry's `dimensions`.
        "embeddinggemma-300m-int8-384" | "embeddinggemma-300m-int8" => EmbeddingModel::EmbeddingGemma300MQ,
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

/// The model run in this process (ONNX Runtime, through fastembed or `OnnxEngine`).
pub struct LocalEmbedder {
    inner: Engine,
    spec: &'static ModelSpec,
    /// See `batch_size_for`.
    batch_size: usize,
}

impl LocalEmbedder {
    /// Loads (downloading into `model_cache_dir()` first if need be) the model `spec` names. Blocking, and slow the
    /// first time. ONNX Runtime uses `threads` CPU threads (it would otherwise take every core).
    pub fn load(spec: &'static ModelSpec, threads: usize) -> anyhow::Result<LocalEmbedder> {
        let (inner, batch_size) = if let Some(model) = fastembed_model(spec.id) {
            let batch_size = batch_size_for(&model);
            let inner = TextEmbedding::try_new(
                TextInitOptions::new(model)
                    .with_environment(environment()?)
                    .with_cache_dir(model_cache_dir())
                    .with_intra_threads(threads.max(1))
                    .with_max_length(MAX_TOKENS)
                    .with_show_download_progress(false),
            )?;
            (Engine::Fastembed(inner), batch_size)
        } else if let Some(model) = onnx_model(spec.id) {
            // One text per ONNX run, as for every dynamically quantized model: see `batch_size_for`.
            (Engine::Onnx(OnnxEngine::load(model, threads)?), 1)
        } else {
            anyhow::bail!("no model to run for `{}`", spec.id);
        };
        Ok(LocalEmbedder { inner, spec, batch_size })
    }

    fn embed_with_prefix(&mut self, prefix: &str, texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>> {
        let prefixed: Vec<String> = texts.iter().map(|t| format!("{}{}", prefix, t)).collect();
        // Chunking here (rather than passing a batch size for all of `prefixed`) is what makes a request bigger than one
        // batch work for dynamically quantized models; see `batch_size_for`.
        let mut vectors = Vec::with_capacity(prefixed.len());
        for chunk in prefixed.chunks(self.batch_size) {
            match &mut self.inner {
                Engine::Fastembed(model) => vectors.extend(model.embed(chunk, Some(self.batch_size))?),
                Engine::Onnx(engine) => {
                    for text in chunk {
                        vectors.push(engine.embed(text)?);
                    }
                }
            }
        }
        // Matryoshka models keep their best information in the leading dimensions, so a registry entry asking for fewer
        // dimensions than the model makes is served by keeping the first N and re-normalizing.
        let dimensions = self.spec.dimensions as usize;
        if let Some(short) = vectors.iter().find(|v| v.len() < dimensions) {
            anyhow::bail!("{} makes {}-dimensional vectors, fewer than the {} its registry entry promises", self.spec.id, short.len(), dimensions);
        }
        for v in vectors.iter_mut() {
            v.truncate(dimensions);
            normalize(v);
        }
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
    fn every_registered_model_has_exactly_one_way_to_be_loaded_and_nothing_else_does() {
        for spec in super::super::MODELS.iter() {
            let (builtin, custom) = (fastembed_model(spec.id).is_some(), onnx_model(spec.id).is_some());
            assert!(builtin ^ custom, "{} must be either a fastembed model or a custom ONNX one (builtin {builtin}, custom {custom})", spec.id);
        }
        assert!(fastembed_model("not-a-model").is_none() && onnx_model("not-a-model").is_none());
    }

    #[test]
    fn the_384_gemma_entry_runs_the_same_model_as_the_full_one() {
        assert_eq!(
            format!("{:?}", fastembed_model("embeddinggemma-300m-int8-384")),
            format!("{:?}", fastembed_model("embeddinggemma-300m-int8"))
        );
    }

    #[test]
    fn only_dynamically_quantized_models_are_embedded_one_text_at_a_time() {
        for spec in super::super::MODELS.iter() {
            let Some(model) = fastembed_model(spec.id) else { continue }; // custom ONNX models always run one at a time
            let dynamic = matches!(TextEmbedding::get_quantization_mode(&model), QuantizationMode::Dynamic);
            assert_eq!(batch_size_for(&model), if dynamic { 1 } else { BATCH_SIZE }, "{}", spec.id);
        }
        // The default model is a custom ONNX one, which `OnnxEngine` always runs one text at a time.
        assert!(onnx_model(super::super::default_model().id).is_some());
    }

    #[test]
    fn vectors_are_unit_length_after_normalizing() {
        let mut v = vec![3.0, 4.0, 0.0];
        normalize(&mut v);
        assert!((v.iter().map(|x| x * x).sum::<f32>() - 1.0).abs() < 1e-6);
    }
}
