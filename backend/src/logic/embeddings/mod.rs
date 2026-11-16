// Semantic search: text embeddings of the same "search documents" Postgres full-text search indexes,
// and the hybrid (full-text + embedding similarity) ranking built on them.
//
// Moving parts:
//   * The *document* (what gets embedded) is defined in SQL, next to the tsvector builders -- see
//     migration 2026-11-15-000000_add_embeddings: `post_search_document`, `event_search_document`,
//     `media_search_document`, `user_search_document`, all derived from the same `*_search_fields`
//     functions the `search_text` columns come from. Nothing here builds document text itself.
//   * The *model* is one of a few small ONNX sentence embedders (`MODELS`) run locally through
//     `fastembed`, chosen by the admin (`SearchSettings.embedding_model`; default `DEFAULT_MODEL_ID`).
//     Vectors are L2-normalized, so cosine similarity is a dot product. Every stored vector records
//     which model made it; switching models re-embeds everything in the background and, until a row
//     has been redone, it simply isn't a semantic candidate (full-text still finds it).
//   * *Storage* is one table per `EmbeddingKind`, vectors as little-endian f32 `bytea` -- no
//     pgvector, because self-hosted Postgres installs can't be assumed to have it. Similarity is
//     computed here, over a bounded candidate set (see `semantic_ranking`), not by Postgres.
//   * *Who runs the model*: the `generate_embeddings` job (`sync_embeddings`) fills and refreshes
//     the tables; the server only embeds search queries, on a model it loads in the background
//     (`server_embedder`) and only while `SearchSettings.semantic_search_enabled` is on. Until
//     that model is ready (or if it can't be loaded) searches are plain full-text.
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant};

use diesel::sql_types::{BigInt, Binary, Nullable, Text};
use diesel::*;
use fastembed::EmbeddingModel;

use crate::db_connection::PgPooledConnection;

mod embedder;
mod index;
mod vector_client;
pub mod model_service;
#[cfg(feature = "vector-service")]
pub mod vector_service;
pub use embedder::{load_embedder, load_embedder_local, BoxedEmbedder, LocalEmbedder, TextEmbedder};
pub use model_service::{cluster_model, cluster_model_blocking, embedding_service_config, embedding_service_configured, RemoteEmbedder};
pub use index::{install_semantic_index, reset_semantic_index, semantic_index, IndexQuery, PostgresScanIndex, SemanticIndex};
pub use vector_client::{vector_service_config, RemoteIndex};

// Longer input is truncated by the tokenizer; documents list their most important text first.
pub(self) const MAX_TOKENS: usize = 256;

/// One embedding model an admin can choose. `id` is what's stored in `SearchSettings.embedding_model`
/// and in every embedding row's `model` column. See the PR description for how these compare.
pub struct ModelSpec {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub dimensions: u32,
    /// Approximate size of the one-time model download.
    pub download_megabytes: u32,
    /// Approximate resident memory with the model loaded (measured per process).
    pub memory_megabytes: u32,
    pub multilingual: bool,
    model: EmbeddingModel,
    /// Some models are trained to see queries and documents differently (E5: "query: "/"passage: ");
    /// the symmetric ones use empty prefixes.
    query_prefix: &'static str,
    document_prefix: &'static str,
    /// Matches below this cosine similarity aren't "semantically related" and are ignored, so a query
    /// doesn't drag in its nearest-but-unrelated neighbors. Cosine scales differ a lot between models
    /// (E5 scores unrelated text around 0.7), so each model has its own, calibrated by
    /// `embeddings_tests::with_model::compare_models`. A ranking knob, not a correctness one.
    pub min_similarity: f32,
}

/// The default is the multilingual, search-tuned model: Rellm servers are not English-only, and it was the
/// best multilingual retriever in `compare_models`. It is also the heaviest (~1GB resident, ~465MB download), so
/// a host that can't spare that should pick a lighter model, or share one model service across namespaces.
pub const DEFAULT_MODEL_ID: &str = "multilingual-e5-small";

// Download/RAM/threshold figures are measured by `embeddings_tests::with_model::compare_models`.
pub static MODELS: [ModelSpec; 7] = [
    ModelSpec {
        id: DEFAULT_MODEL_ID,
        name: "multilingual-e5-small",
        description: "Multilingual (100 languages), search-tuned (queries vs. passages), not quantized. The default. The heaviest option: ~1GB of memory.",
        dimensions: 384,
        download_megabytes: 465,
        memory_megabytes: 980,
        multilingual: true,
        model: EmbeddingModel::MultilingualE5Small,
        query_prefix: "query: ",
        document_prefix: "passage: ",
        min_similarity: 0.81,
    },
    ModelSpec {
        id: "paraphrase-multilingual-minilm-l12-v2",
        name: "paraphrase-multilingual-MiniLM-L12-v2 (quantized)",
        description: "Multilingual (50+ languages), including cross-language matches. Best quality in our small test and lighter than e5, but still ~750MB of memory.",
        dimensions: 384,
        download_megabytes: 240,
        memory_megabytes: 750,
        multilingual: true,
        model: EmbeddingModel::ParaphraseMLMiniLML12V2Q,
        query_prefix: "",
        document_prefix: "",
        min_similarity: 0.36,
    },
    ModelSpec {
        id: "bge-small-en-v1.5",
        name: "bge-small-en-v1.5 (quantized)",
        description: "English only. Search-tuned and light (~110MB of memory). For an English-language server on small hardware.",
        dimensions: 384,
        download_megabytes: 64,
        memory_megabytes: 110,
        multilingual: false,
        model: EmbeddingModel::BGESmallENV15Q,
        query_prefix: "Represent this sentence for searching relevant passages: ",
        document_prefix: "",
        min_similarity: 0.60,
    },
    ModelSpec {
        id: "all-minilm-l6-v2",
        name: "all-MiniLM-L6-v2 (quantized)",
        description: "English only. The smallest and fastest (~70MB of memory); general sentence similarity rather than search-tuned. For the very smallest hosts.",
        dimensions: 384,
        download_megabytes: 23,
        memory_megabytes: 70,
        multilingual: false,
        model: EmbeddingModel::AllMiniLML6V2Q,
        query_prefix: "",
        document_prefix: "",
        min_similarity: 0.33,
    },
    // EmbeddingGemma (Google): multilingual, 768 dimensions (twice the vector size of the 384-dimension models), search-tuned
    // with documented task prompts. Gemma's terms of use apply to the weights (not Apache/MIT like the others). Unlike
    // every other model here its right answers and no-answer queries don't overlap in `compare_models`, with a wide
    // gap (~0.17-0.29), so its threshold is the middle of that gap and has real margin. Figures from `compare_models`.
    ModelSpec {
        id: "embeddinggemma-300m",
        name: "EmbeddingGemma 300M",
        description: "Multilingual (100+ languages), search-tuned, full precision. Perfect on our test set with a clean margin between matches and non-matches. Large download (~1.2GB) and ~5x slower to embed than e5-small, with 768-dimension vectors; the int8 and 4-bit variants are far smaller.",
        dimensions: 768,
        download_megabytes: 1198,
        memory_megabytes: 734,
        multilingual: true,
        model: EmbeddingModel::EmbeddingGemma300M,
        query_prefix: "task: search result | query: ",
        document_prefix: "title: none | text: ",
        min_similarity: 0.22,
    },
    ModelSpec {
        id: "embeddinggemma-300m-int8",
        name: "EmbeddingGemma 300M (int8)",
        description: "Multilingual (100+ languages), search-tuned, 8-bit weights. Matched the best quality in our test with the smallest memory of any multilingual option (~330MB) and a clean margin between matches and non-matches. ~5x slower to embed than e5-small, with 768-dimension vectors (twice the storage).",
        dimensions: 768,
        download_megabytes: 295,
        memory_megabytes: 331,
        multilingual: true,
        model: EmbeddingModel::EmbeddingGemma300MQ,
        query_prefix: "task: search result | query: ",
        document_prefix: "title: none | text: ",
        min_similarity: 0.23,
    },
    ModelSpec {
        id: "embeddinggemma-300m-q4",
        name: "EmbeddingGemma 300M (4-bit)",
        description: "Multilingual (100+ languages), search-tuned, 4-bit weights. Smallest download of the multilingual options (~190MB), ~420MB of memory, and the same clean test result as the larger variants (4-bit may lose more on real content than int8). ~4x slower to embed than e5-small, with 768-dimension vectors.",
        dimensions: 768,
        download_megabytes: 188,
        memory_megabytes: 421,
        multilingual: true,
        model: EmbeddingModel::EmbeddingGemma300MQ4,
        query_prefix: "task: search result | query: ",
        document_prefix: "title: none | text: ",
        min_similarity: 0.24,
    },
];

impl ModelSpec {
    fn model(&self) -> &EmbeddingModel {
        &self.model
    }
    fn query_prefix(&self) -> &'static str {
        self.query_prefix
    }
    fn document_prefix(&self) -> &'static str {
        self.document_prefix
    }
}

/// The model with this id; `None` for an unknown id.
pub fn model_spec(id: &str) -> Option<&'static ModelSpec> {
    MODELS.iter().find(|m| m.id == id)
}

pub fn default_model() -> &'static ModelSpec {
    model_spec(DEFAULT_MODEL_ID).expect("the default model is registered")
}

/// `SearchSettings.available_models` -- what the Settings tab offers.
pub fn available_models() -> Vec<crate::protos::EmbeddingModel> {
    MODELS
        .iter()
        .map(|m| crate::protos::EmbeddingModel {
            id: m.id.to_string(),
            name: m.name.to_string(),
            description: m.description.to_string(),
            dimensions: m.dimensions,
            download_megabytes: m.download_megabytes,
            memory_megabytes: m.memory_megabytes,
            multilingual: m.multilingual,
        })
        .collect()
}

/// How many semantically similar results `semantic_ranking` returns at most.
pub const SEMANTIC_RESULT_LIMIT: usize = 500;
/// How many of the newest visible rows a search scans for semantic matches *in addition to* the
/// full-text matches (so a query can surface rows that share no words with it). Bounds the work and
/// data transfer per search (~1.5KB per row): the cost of not having a vector index.
pub const SEMANTIC_SCAN_LIMIT: i64 = 10_000;
/// Reciprocal-rank-fusion constant (the standard 60): larger flattens the difference between ranks.
const RRF_K: f64 = 60.0;

/// The four things that get embedded, each in its own table. Posts and Events both come from a Post,
/// but an Event's document also covers its Occasions (`event_search_document`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EmbeddingKind {
    Post,
    Event,
    Media,
    UserProfile,
}

impl EmbeddingKind {
    pub const ALL: [EmbeddingKind; 4] = [
        EmbeddingKind::Post,
        EmbeddingKind::Event,
        EmbeddingKind::Media,
        EmbeddingKind::UserProfile,
    ];

    pub fn name(self) -> &'static str {
        match self {
            EmbeddingKind::Post => "post",
            EmbeddingKind::Event => "event",
            EmbeddingKind::Media => "media",
            EmbeddingKind::UserProfile => "user_profile",
        }
    }

    // The names below are interpolated into SQL: they are compile-time constants, never user input.
    fn embeddings_table(self) -> &'static str {
        match self {
            EmbeddingKind::Post => "post_embeddings",
            EmbeddingKind::Event => "event_embeddings",
            EmbeddingKind::Media => "media_embeddings",
            EmbeddingKind::UserProfile => "user_profile_embeddings",
        }
    }
    fn embeddings_id_column(self) -> &'static str {
        match self {
            EmbeddingKind::Post => "post_id",
            EmbeddingKind::Event => "event_id",
            EmbeddingKind::Media => "media_id",
            EmbeddingKind::UserProfile => "user_id",
        }
    }
    fn source_table(self) -> &'static str {
        match self {
            EmbeddingKind::Post => "posts",
            EmbeddingKind::Event => "events",
            EmbeddingKind::Media => "media",
            EmbeddingKind::UserProfile => "users",
        }
    }
    fn source_id_column(self) -> &'static str {
        match self {
            EmbeddingKind::Event => "post_id",
            _ => "id",
        }
    }
    fn document_function(self) -> &'static str {
        match self {
            EmbeddingKind::Post => "post_search_document",
            EmbeddingKind::Event => "event_search_document",
            EmbeddingKind::Media => "media_search_document",
            EmbeddingKind::UserProfile => "user_search_document",
        }
    }
}

// ---------------------------------------------------------------------------------------------
// The model
// ---------------------------------------------------------------------------------------------

/// Where models are cached (and so downloaded to, once): `RELLM_EMBEDDING_CACHE_DIR`, else
/// `~/.cache/rellm/embedding_models`, else `./.embedding_models`. The server and the job each
/// download into it if the model isn't there yet, so give them the same directory to share one copy.
pub fn model_cache_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("RELLM_EMBEDDING_CACHE_DIR").filter(|d| !d.is_empty()) {
        return PathBuf::from(dir);
    }
    match std::env::var_os("HOME").filter(|h| !h.is_empty()) {
        Some(home) => PathBuf::from(home).join(".cache/rellm/embedding_models"),
        None => PathBuf::from(".embedding_models"),
    }
}

pub(self) fn normalize(vector: &mut [f32]) {
    let norm = vector.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm > 0.0 {
        vector.iter_mut().for_each(|x| *x /= norm);
    }
}

pub fn vector_to_bytes(vector: &[f32]) -> Vec<u8> {
    vector.iter().flat_map(|x| x.to_le_bytes()).collect()
}

// ---------------------------------------------------------------------------------------------
// The server's query embedder
// ---------------------------------------------------------------------------------------------

// `None` until loaded, and again after `unload_server_embedder` (setting turned off) so a small host gets
// the model's memory back without a restart. Searches hold their own `Arc` while using it.
static SERVER_EMBEDDER: RwLock<Option<Arc<Mutex<BoxedEmbedder>>>> = RwLock::new(None);
// What the last `search_configuration` check saw, so a load that finishes after the setting was turned
// off (or the model changed) discards the model instead of keeping the wrong one.
static LAST_KNOWN_ENABLED: AtomicBool = AtomicBool::new(true);
static LAST_KNOWN_MODEL_ID: Mutex<&'static str> = Mutex::new(DEFAULT_MODEL_ID);
static LOADING: AtomicBool = AtomicBool::new(false);
// Whether `server_embedder` may start loading (downloading) a model by itself. Always, except in the
// crate's own tests: nearly every test that searches or saves the configuration would otherwise kick off
// a background model download. Tests that really want the model call `enable_model_loading`.
static AUTO_LOAD: AtomicBool = AtomicBool::new(!cfg!(test));
// Which model failed to load, and when: a cooldown only applies to *that* model, so an admin who
// switches to a working one isn't stuck on full-text search until the failed model's timer expires.
static LAST_LOAD_FAILURE: Mutex<Option<(&'static str, Instant)>> = Mutex::new(None);
const RETRY_LOAD_AFTER: Duration = Duration::from_secs(600);
// Embedding one short search query needs no more than this.
const SERVER_THREADS: usize = 1;

/// Lets `server_embedder` load models in the crate's own tests (see `AUTO_LOAD`).
pub fn enable_model_loading() {
    AUTO_LOAD.store(true, Ordering::SeqCst);
}

/// The server's embedder for `spec`, once it's loaded. The first call (when semantic search is on)
/// starts loading it on a background thread -- downloading the model if need be -- and returns `None`
/// until that finishes, so a search never waits on a download: it's just full-text until then. A
/// model loaded for a *different* choice is dropped (the admin switched models). A failed load is
/// retried at most every ten minutes.
pub fn server_embedder(spec: &'static ModelSpec) -> Option<Arc<Mutex<BoxedEmbedder>>> {
    if let Some(embedder) = SERVER_EMBEDDER.read().unwrap().as_ref() {
        if embedder.lock().map(|e| e.spec().id == spec.id).unwrap_or(false) {
            return Some(embedder.clone());
        }
    }
    // Loaded, but for another model: free it and load the right one.
    if SERVER_EMBEDDER.read().unwrap().is_some() {
        unload_server_embedder();
    }
    if let Some((failed_model, failed_at)) = *LAST_LOAD_FAILURE.lock().unwrap() {
        if failed_model == spec.id && failed_at.elapsed() < RETRY_LOAD_AFTER {
            return None;
        }
    }
    if !AUTO_LOAD.load(Ordering::SeqCst) {
        return None;
    }
    if !LOADING.swap(true, Ordering::SeqCst) {
        std::thread::spawn(move || {
            log::info!("Loading embedding model {} for semantic search...", spec.id);
            match load_embedder(spec, SERVER_THREADS) {
                Ok(embedder)
                    if LAST_KNOWN_ENABLED.load(Ordering::SeqCst)
                        && *LAST_KNOWN_MODEL_ID.lock().unwrap() == spec.id =>
                {
                    *SERVER_EMBEDDER.write().unwrap() = Some(Arc::new(Mutex::new(embedder)));
                    *LAST_LOAD_FAILURE.lock().unwrap() = None;
                    log::info!("Embedding model {} ready; semantic search is active.", spec.id);
                }
                Ok(_) => log::info!("Semantic search was turned off or its model changed while {} loaded; dropping it.", spec.id),
                Err(e) => {
                    log::error!("Couldn't load embedding model {}; search stays full-text only: {:?}", spec.id, e);
                    *LAST_LOAD_FAILURE.lock().unwrap() = Some((spec.id, Instant::now()));
                }
            }
            LOADING.store(false, Ordering::SeqCst);
        });
    }
    None
}

/// Installs `embedder` as the server's query embedder, replacing whatever is loaded. For embedders that
/// aren't loaded on demand by `server_embedder` -- a client of a shared model service set up at startup,
/// or a deterministic fake in tests. It is used for as long as its `spec()` is the configured model.
pub fn install_server_embedder(embedder: BoxedEmbedder) {
    *SERVER_EMBEDDER.write().unwrap() = Some(Arc::new(Mutex::new(embedder)));
}

/// Frees the server's query model (the setting was turned off, or the model changed). A search
/// already using it finishes first; the memory is released when its last `Arc` drops.
pub fn unload_server_embedder() {
    *SERVER_EMBEDDER.write().unwrap() = None;
}

/// Brings the server's query model in line with the settings: starts loading the chosen model when
/// semantic search is on, frees it when off. Called when the configuration is saved (and at startup),
/// so a change takes effect immediately instead of on the next search.
pub fn apply_semantic_search_setting(conn: &mut PgPooledConnection) {
    match search_configuration(conn) {
        (true, spec) => {
            let _ = server_embedder(spec);
        }
        (false, _) => unload_server_embedder(),
    }
}

/// Whether `ServerConfiguration.search_settings.semantic_search_enabled` is on (the default,
/// including for rows saved before the setting existed).
pub fn semantic_search_enabled(conn: &mut PgPooledConnection) -> bool {
    search_configuration(conn).0
}

/// The model `SearchSettings.embedding_model` selects (the default when unset or unrecognized).
pub fn active_model(conn: &mut PgPooledConnection) -> &'static ModelSpec {
    search_configuration(conn).1
}

/// `(semantic_search_enabled, chosen model)` from the active server configuration.
fn search_configuration(conn: &mut PgPooledConnection) -> (bool, &'static ModelSpec) {
    use crate::schema::server_configurations::dsl::*;
    let stored = server_configurations
        .filter(active.eq(true))
        .select(search_settings)
        .first::<Option<serde_json::Value>>(conn)
        .ok()
        .flatten();
    let enabled = stored
        .as_ref()
        .and_then(|v| v.get("semantic_search_enabled").and_then(|b| b.as_bool()))
        .unwrap_or(true);
    let spec = stored
        .as_ref()
        .and_then(|v| v.get("embedding_model").and_then(|m| m.as_str()))
        .and_then(model_spec)
        .unwrap_or_else(default_model);
    // A cluster-shared model service hosts one model for everyone: it wins over the admin's own choice. (If it's
    // configured but not answering we keep the configured model; embedding fails and search stays full-text.)
    let spec = if embedding_service_configured() { cluster_model().unwrap_or(spec) } else { spec };
    LAST_KNOWN_ENABLED.store(enabled, Ordering::SeqCst);
    *LAST_KNOWN_MODEL_ID.lock().unwrap() = spec.id;
    (enabled, spec)
}

// ---------------------------------------------------------------------------------------------
// Searching
// ---------------------------------------------------------------------------------------------

/// Whether a search can use semantic ranking right now (enabled, and the server's model is loaded).
/// Callers check this before doing the extra work of gathering `semantic_ranking`'s candidate ids.
pub fn semantic_search_ready(conn: &mut PgPooledConnection) -> bool {
    let (enabled, spec) = search_configuration(conn);
    if !enabled {
        // Turned off (maybe by another instance's `ConfigureServer`): give the memory back.
        unload_server_embedder();
        return false;
    }
    server_embedder(spec).is_some()
}

/// Ids of the rows of `kind` (among `scope_ids`) most semantically similar to `query`, best first,
/// with their cosine similarity -- only those at least `MIN_SIMILARITY` similar, at most
/// `SEMANTIC_RESULT_LIMIT`. `None` when semantic search can't be used right now (it's turned off, or
/// the server's model isn't loaded yet / failed to load), in which case callers just keep their
/// full-text results. Rows with no embedding yet are simply absent from the result.
///
/// `scope_ids` is the caller's job to make *visible* ids (the full-text candidates plus the newest
/// visible rows up to `SEMANTIC_SCAN_LIMIT`): this never widens what a user can see.
pub fn semantic_ranking(
    conn: &mut PgPooledConnection,
    kind: EmbeddingKind,
    query_text: &str,
    scope_ids: &[i64],
) -> Option<Vec<(i64, f32)>> {
    if scope_ids.is_empty() || query_text.trim().is_empty() {
        return None;
    }
    let (enabled, spec) = search_configuration(conn);
    if !enabled {
        return None;
    }
    let embedder = server_embedder(spec)?;
    let query = embedder
        .lock()
        .ok()?
        .embed_query(query_text.trim())
        .map_err(|e| log::error!("Couldn't embed search query: {:?}", e))
        .ok()?;
    // Scoped search is always the Postgres scan: it reads only `scope_ids`' vectors and needs nothing else running.
    // It is also the fallback when the optional vector search service can't answer a "search anywhere" query.
    PostgresScanIndex.search(
        conn,
        &IndexQuery {
            kind,
            spec,
            vector: &query,
            scope: Some(scope_ids),
            limit: SEMANTIC_RESULT_LIMIT,
        },
    )
}

/// How many nearest ids a global search asks the index for. Visibility is applied to them afterwards (in Postgres),
/// so this is deliberately well above the 500 a scoped search keeps: most of them can be invisible to a viewer.
pub const GLOBAL_RESULT_LIMIT: usize = 2_000;

/// Whether `semantic_ranking_global` can be used: the configured index holds every vector. When true, callers
/// pass no candidate scope and filter the returned ids for visibility themselves.
pub fn semantic_global_available() -> bool {
    semantic_index().supports_global()
}

/// The ids (best first, with cosine similarity) of `kind` nearest to `query_text` *anywhere in the index* -- NOT
/// filtered for visibility: the caller MUST restrict them to what the viewer may see (an `id = ANY(...)` filter
/// on its visibility-checked query) before using them. `None` when semantic search can't be used right now.
pub fn semantic_ranking_global(conn: &mut PgPooledConnection, kind: EmbeddingKind, query_text: &str) -> Option<Vec<(i64, f32)>> {
    if query_text.trim().is_empty() {
        return None;
    }
    let (enabled, spec) = search_configuration(conn);
    if !enabled {
        return None;
    }
    let embedder = server_embedder(spec)?;
    let query = embedder
        .lock()
        .ok()?
        .embed_query(query_text.trim())
        .map_err(|e| log::error!("Couldn't embed search query: {:?}", e))
        .ok()?;
    semantic_index().search(
        conn,
        &IndexQuery { kind, spec, vector: &query, scope: None, limit: GLOBAL_RESULT_LIMIT },
    )
}

/// Reranks by reciprocal rank fusion: each id scores `1/(k + rank)` in every list it appears in
/// (full-text order, then semantic order) and the scores add. An id both lists like beats one only
/// a single list likes; an id only the semantic list found (no shared words) still appears, and a
/// full-text match with no embedding keeps its full-text standing. Ties keep full-text order first.
pub fn fuse_rankings(full_text: &[i64], semantic: &[(i64, f32)]) -> Vec<i64> {
    let mut scores: HashMap<i64, f64> = HashMap::new();
    let mut first_seen: Vec<i64> = Vec::new();
    for (rank, id) in full_text.iter().enumerate() {
        if !scores.contains_key(id) {
            first_seen.push(*id);
        }
        *scores.entry(*id).or_default() += 1.0 / (RRF_K + rank as f64 + 1.0);
    }
    for (rank, (id, _)) in semantic.iter().enumerate() {
        if !scores.contains_key(id) {
            first_seen.push(*id);
        }
        *scores.entry(*id).or_default() += 1.0 / (RRF_K + rank as f64 + 1.0);
    }
    // `sort_by` is stable, so equal scores keep `first_seen` order (full-text matches first).
    first_seen.sort_by(|a, b| scores[b].total_cmp(&scores[a]));
    first_seen
}

// ---------------------------------------------------------------------------------------------
// Keeping the tables up to date (the `generate_embeddings` job)
// ---------------------------------------------------------------------------------------------

#[derive(QueryableByName)]
struct SourceDocument {
    #[diesel(sql_type = BigInt)]
    id: i64,
    #[diesel(sql_type = Text)]
    document: String,
    #[diesel(sql_type = BigInt)]
    document_hash: i64,
    // Only meaningful (and only `true`) for the sweep of existing rows: the stored embedding is
    // from the current model and of the current document, so there's nothing to redo.
    #[diesel(sql_type = diesel::sql_types::Bool)]
    up_to_date: bool,
}

#[derive(Default, Debug, Clone, Copy)]
pub struct SyncStats {
    pub embedded: usize,
    pub unchanged: usize,
    pub empty: usize,
    /// The run's time budget ran out with work left over; the next run picks it up.
    pub out_of_time: bool,
}

/// `before_model_load` said no (see `SyncContext`): the cluster's embedding slot is taken.
#[derive(Debug)]
pub struct ModelUnavailable;

impl std::fmt::Display for ModelUnavailable {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "the embedding model isn't available to this run right now")
    }
}
impl std::error::Error for ModelUnavailable {}

/// How a `sync_embeddings` run is allowed to use the machine -- built for small, shared hardware:
///   * `before_model_load` is asked once, right before the (RAM- and CPU-hungry) model would be
///     loaded, and only if some text actually needs embedding -- the `generate_embeddings` job
///     takes the `CLUSTER_RESOURCE_EMBEDDINGS` cluster lock here. Returning `false` ends the run
///     with `ModelUnavailable`, having embedded nothing.
///   * `deadline` bounds the run: work stops at the next batch boundary once it passes, so a big
///     backlog is worked down over several runs (taking turns) instead of one long hold.
///   * `threads` is how many CPU threads the model may use.
///   * `spec` is the model: rows embedded by another one are redone, so a model change is just a long
///     backlog worked down over runs (their old vectors are ignored by search in the meantime).
pub struct SyncContext<'a> {
    /// The model to embed with (`active_model`): rows made by any other model count as missing.
    pub spec: &'static ModelSpec,
    pub embedder: Option<BoxedEmbedder>,
    pub deadline: Instant,
    pub threads: usize,
    pub before_model_load: Box<dyn FnMut() -> bool + 'a>,
}

impl SyncContext<'static> {
    /// No gate and an hour's budget -- for tests and one-off tools.
    pub fn unrestricted() -> Self {
        SyncContext {
            spec: default_model(),
            embedder: None,
            deadline: Instant::now() + Duration::from_secs(3600),
            threads: 2,
            before_model_load: Box::new(|| true),
        }
    }
}

/// How many existing embeddings per kind each run re-checks against their current document
/// (oldest-checked first), so edits and renames get re-embedded without rescanning everything.
pub const SWEEP_BATCH: i64 = 500;
const WRITE_BATCH: i64 = 128;

/// One pass of the `generate_embeddings` job for `kind`:
///   1. embeds every row that has no embedding yet (newest first), until none are left;
///   2. re-checks the `SWEEP_BATCH` least recently checked embeddings: unchanged ones just get
///      `checked_at` bumped, ones whose document changed (or from another model) are re-embedded.
/// The model is loaded lazily, on the first text that needs embedding (see `SyncContext`), so a pass
/// with nothing to do never touches it.
pub fn sync_embeddings(
    conn: &mut PgPooledConnection,
    kind: EmbeddingKind,
    ctx: &mut SyncContext,
) -> anyhow::Result<SyncStats> {
    let mut stats = SyncStats::default();

    // The staleness sweep goes first: it is bounded (`SWEEP_BATCH` rows), so edits and renames are always
    // refreshed, even while a large backlog of never-embedded rows is being worked down below.
    let sweep = sql_query(format!(
        "SELECT e.{eid} AS id, d.document, hashtextextended(d.document, 0) AS document_hash, \
                (e.document_hash = hashtextextended(d.document, 0) AND e.model = $2) AS up_to_date \
         FROM {table} e \
         CROSS JOIN LATERAL (SELECT coalesce({doc}(e.{eid}), '') AS document) d \
         ORDER BY e.checked_at ASC LIMIT $1",
        table = kind.embeddings_table(),
        eid = kind.embeddings_id_column(),
        doc = kind.document_function(),
    ))
    .bind::<BigInt, _>(SWEEP_BATCH)
    .bind::<Text, _>(ctx.spec.id)
    .load::<SourceDocument>(conn)?;
    let (current, stale): (Vec<_>, Vec<_>) = sweep.into_iter().partition(|row| row.up_to_date);
    if !current.is_empty() {
        sql_query(format!(
            "UPDATE {table} SET checked_at = NOW() WHERE {eid} = ANY($1)",
            table = kind.embeddings_table(),
            eid = kind.embeddings_id_column(),
        ))
        .bind::<diesel::sql_types::Array<BigInt>, _>(current.iter().map(|r| r.id).collect::<Vec<_>>())
        .execute(conn)?;
        stats.unchanged += current.len();
    }
    for chunk in stale.chunks(WRITE_BATCH as usize) {
        if Instant::now() >= ctx.deadline {
            stats.out_of_time = true;
            break;
        }
        store_embeddings(conn, kind, chunk, ctx, &mut stats)?;
    }

    loop {
        if Instant::now() >= ctx.deadline {
            stats.out_of_time = true;
            return Ok(stats);
        }
        let batch = sql_query(format!(
            "SELECT s.{sid} AS id, d.document, hashtextextended(d.document, 0) AS document_hash, false AS up_to_date \
             FROM {source} s \
             CROSS JOIN LATERAL (SELECT coalesce({doc}(s.{sid}), '') AS document) d \
             WHERE NOT EXISTS (SELECT 1 FROM {table} e WHERE e.{eid} = s.{sid} AND e.model = $2) \
             ORDER BY s.{sid} DESC LIMIT $1",
            sid = kind.source_id_column(),
            source = kind.source_table(),
            doc = kind.document_function(),
            table = kind.embeddings_table(),
            eid = kind.embeddings_id_column(),
        ))
        .bind::<BigInt, _>(WRITE_BATCH)
        .bind::<Text, _>(ctx.spec.id)
        .load::<SourceDocument>(conn)?;
        if batch.is_empty() {
            break;
        }
        store_embeddings(conn, kind, &batch, ctx, &mut stats)?;
    }

    Ok(stats)
}

/// Embeds `rows` (a blank document gets a row with a NULL embedding -- "nothing to embed", so it
/// isn't picked up as missing again) and upserts them.
fn store_embeddings(
    conn: &mut PgPooledConnection,
    kind: EmbeddingKind,
    rows: &[SourceDocument],
    ctx: &mut SyncContext,
    stats: &mut SyncStats,
) -> anyhow::Result<()> {
    let to_embed: Vec<&SourceDocument> = rows.iter().filter(|r| !r.document.trim().is_empty()).collect();
    let mut vectors: HashMap<i64, Vec<f32>> = HashMap::new();
    if !to_embed.is_empty() {
        if ctx.embedder.is_none() {
            if !(ctx.before_model_load)() {
                return Err(ModelUnavailable.into());
            }
            log::info!("Loading embedding model {} (downloads it the first time)...", ctx.spec.id);
            ctx.embedder = Some(load_embedder(ctx.spec, ctx.threads)?);
        }
        let texts: Vec<String> = to_embed.iter().map(|r| r.document.clone()).collect();
        let embedded = ctx.embedder.as_mut().unwrap().embed_documents(&texts)?;
        vectors = to_embed.iter().map(|r| r.id).zip(embedded).collect();
    }
    for row in rows {
        let bytes = vectors.get(&row.id).map(|v| vector_to_bytes(v));
        if bytes.is_some() {
            stats.embedded += 1;
        } else {
            stats.empty += 1;
        }
        sql_query(format!(
            "INSERT INTO {table} ({eid}, model, document_hash, embedding) VALUES ($1, $2, $3, $4) \
             ON CONFLICT ({eid}) DO UPDATE SET model = EXCLUDED.model, \
               document_hash = EXCLUDED.document_hash, embedding = EXCLUDED.embedding, \
               embedded_at = NOW(), checked_at = NOW()",
            table = kind.embeddings_table(),
            eid = kind.embeddings_id_column(),
        ))
        .bind::<BigInt, _>(row.id)
        .bind::<Text, _>(ctx.spec.id)
        .bind::<BigInt, _>(row.document_hash)
        .bind::<Nullable<Binary>, _>(bytes)
        .execute(conn)?;
    }
    Ok(())
}

#[cfg(test)]
mod unit_tests {
    use super::index::similarity;
    use super::*;

    #[test]
    fn vectors_round_trip_through_bytes_and_similarity_is_the_dot_product() {
        let mut a = vec![3.0, 4.0, 0.0];
        normalize(&mut a);
        assert!((a.iter().map(|x| x * x).sum::<f32>() - 1.0).abs() < 1e-6);
        let stored = vector_to_bytes(&a);
        assert!((similarity(&a, &stored).unwrap() - 1.0).abs() < 1e-6);
        // Orthogonal vectors have no similarity; a different dimension never matches.
        assert!(similarity(&[0.0, 0.0, 1.0], &stored).unwrap().abs() < 1e-6);
        assert_eq!(similarity(&[1.0, 0.0], &stored), None);
    }

    #[test]
    fn fusion_prefers_what_both_rankings_like_and_keeps_either_rankings_solo_finds() {
        // 1 and 2 are the full-text top two; 3 is semantic-only; 2 is also the semantic favorite.
        let fused = fuse_rankings(&[1, 2], &[(2, 0.9), (3, 0.8)]);
        assert_eq!(fused, vec![2, 1, 3]);
        // Without a semantic ranking, full-text order is untouched.
        assert_eq!(fuse_rankings(&[5, 4, 3], &[]), vec![5, 4, 3]);
        // Without full-text matches, semantic order stands alone.
        assert_eq!(fuse_rankings(&[], &[(9, 0.7), (8, 0.6)]), vec![9, 8]);
    }
}
