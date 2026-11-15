// Semantic search: text embeddings of the same "search documents" Postgres full-text search indexes,
// and the hybrid (full-text + embedding similarity) ranking built on them.
//
// Moving parts:
//   * The *document* (what gets embedded) is defined in SQL, next to the tsvector builders -- see
//     migration 2026-11-15-000000_add_embeddings: `post_search_document`, `event_search_document`,
//     `media_search_document`, `user_search_document`, all derived from the same `*_search_fields`
//     functions the `search_text` columns come from. Nothing here builds document text itself.
//   * The *model* is a small multilingual ONNX sentence embedder run locally through `fastembed`
//     (`MODEL`). Vectors are L2-normalized, so cosine similarity is a dot product.
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
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use diesel::sql_types::{BigInt, Binary, Nullable, Text};
use diesel::*;
use fastembed::{EmbeddingModel, TextEmbedding, TextInitOptions};

use crate::db_connection::PgPooledConnection;

/// Human-readable description of `MODEL`, served as `SearchSettings.embedding_model` and shown on
/// the Settings tab. Keep in step with `MODEL`/`MODEL_NAME`.
pub const MODEL_DESCRIPTION: &str =
    "paraphrase-multilingual-MiniLM-L12-v2 (quantized ONNX, 384 dimensions, multilingual), run locally via fastembed";

/// Stored in every embedding row's `model` column. A row whose `model` differs is stale and gets
/// re-embedded, so switching `MODEL` (and bumping this name with it) re-embeds everything.
pub const MODEL_NAME: &str = "paraphrase-multilingual-MiniLM-L12-v2-onnx-Q";
// Quantized (~120MB), multilingual (the app's content isn't English-only), 384 dimensions, and
// symmetric -- queries and documents embed the same way, no instruction prefixes.
const MODEL: EmbeddingModel = EmbeddingModel::ParaphraseMLMiniLML12V2Q;
// Longer input is truncated by the tokenizer; documents list their most important text first.
const MAX_TOKENS: usize = 256;

/// Matches below this cosine similarity aren't "semantically related" and are ignored, so every
/// query doesn't drag in its nearest-but-unrelated neighbors. A ranking knob, not a correctness one.
pub const MIN_SIMILARITY: f32 = 0.35;
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

pub struct Embedder(TextEmbedding);

impl Embedder {
    /// Loads the model, downloading it into `model_cache_dir()` first if it isn't there. Blocking,
    /// and slow the first time. ONNX Runtime uses `threads` CPU threads (it would otherwise take
    /// every core, which is rude on small shared hardware).
    pub fn load(threads: usize) -> anyhow::Result<Embedder> {
        let model = TextEmbedding::try_new(
            TextInitOptions::new(MODEL)
                .with_cache_dir(model_cache_dir())
                .with_intra_threads(threads.max(1))
                .with_max_length(MAX_TOKENS)
                .with_show_download_progress(false),
        )?;
        Ok(Embedder(model))
    }

    /// One L2-normalized vector per text, in order. Empty texts are the caller's to skip.
    pub fn embed(&mut self, texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>> {
        let mut vectors = self.0.embed(texts, Some(32))?;
        vectors.iter_mut().for_each(|v| normalize(v));
        Ok(vectors)
    }
}

fn normalize(vector: &mut [f32]) {
    let norm = vector.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm > 0.0 {
        vector.iter_mut().for_each(|x| *x /= norm);
    }
}

pub fn vector_to_bytes(vector: &[f32]) -> Vec<u8> {
    vector.iter().flat_map(|x| x.to_le_bytes()).collect()
}

/// Dot product of a vector and stored bytes -- cosine similarity, both being normalized. `None` if
/// the stored vector has a different dimension (a different model's leftovers).
fn similarity(query: &[f32], stored: &[u8]) -> Option<f32> {
    if stored.len() != query.len() * 4 {
        return None;
    }
    Some(
        query
            .iter()
            .zip(stored.chunks_exact(4))
            .map(|(q, b)| q * f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
            .sum(),
    )
}

// ---------------------------------------------------------------------------------------------
// The server's query embedder
// ---------------------------------------------------------------------------------------------

static SERVER_EMBEDDER: OnceLock<Mutex<Embedder>> = OnceLock::new();
static LOADING: AtomicBool = AtomicBool::new(false);
static LAST_LOAD_FAILURE: Mutex<Option<Instant>> = Mutex::new(None);
const RETRY_LOAD_AFTER: Duration = Duration::from_secs(600);
// Embedding one short search query needs no more than this.
const SERVER_THREADS: usize = 1;

/// The server's embedder, once it's loaded. The first call (when semantic search is on) starts
/// loading it on a background thread -- downloading the model if need be -- and returns `None`
/// until that finishes, so a search never waits on a download: it's just full-text until then. A
/// failed load is retried at most every ten minutes.
pub fn server_embedder() -> Option<&'static Mutex<Embedder>> {
    if let Some(embedder) = SERVER_EMBEDDER.get() {
        return Some(embedder);
    }
    if let Some(failed_at) = *LAST_LOAD_FAILURE.lock().unwrap() {
        if failed_at.elapsed() < RETRY_LOAD_AFTER {
            return None;
        }
    }
    if !LOADING.swap(true, Ordering::SeqCst) {
        std::thread::spawn(|| {
            log::info!("Loading embedding model {} for semantic search...", MODEL_NAME);
            match Embedder::load(SERVER_THREADS) {
                Ok(embedder) => {
                    let _ = SERVER_EMBEDDER.set(Mutex::new(embedder));
                    log::info!("Embedding model ready; semantic search is active.");
                }
                Err(e) => {
                    log::error!("Couldn't load the embedding model; search stays full-text only: {:?}", e);
                    *LAST_LOAD_FAILURE.lock().unwrap() = Some(Instant::now());
                }
            }
            LOADING.store(false, Ordering::SeqCst);
        });
    }
    None
}

/// Whether `ServerConfiguration.search_settings.semantic_search_enabled` is on (the default,
/// including for rows saved before the setting existed).
pub fn semantic_search_enabled(conn: &mut PgPooledConnection) -> bool {
    use crate::schema::server_configurations::dsl::*;
    server_configurations
        .filter(active.eq(true))
        .select(search_settings)
        .first::<Option<serde_json::Value>>(conn)
        .ok()
        .flatten()
        .and_then(|v| v.get("semantic_search_enabled").and_then(|b| b.as_bool()))
        .unwrap_or(true)
}

// ---------------------------------------------------------------------------------------------
// Searching
// ---------------------------------------------------------------------------------------------

/// Whether a search can use semantic ranking right now (enabled, and the server's model is loaded).
/// Callers check this before doing the extra work of gathering `semantic_ranking`'s candidate ids.
pub fn semantic_search_ready(conn: &mut PgPooledConnection) -> bool {
    semantic_search_enabled(conn) && server_embedder().is_some()
}

#[derive(QueryableByName)]
struct StoredVector {
    #[diesel(sql_type = BigInt)]
    id: i64,
    #[diesel(sql_type = Binary)]
    embedding: Vec<u8>,
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
    if scope_ids.is_empty() || query_text.trim().is_empty() || !semantic_search_enabled(conn) {
        return None;
    }
    let embedder = server_embedder()?;
    let query = embedder
        .lock()
        .ok()?
        .embed(&[query_text.trim().to_string()])
        .map_err(|e| log::error!("Couldn't embed search query: {:?}", e))
        .ok()?
        .pop()?;

    let rows = sql_query(format!(
        "SELECT {id} AS id, embedding FROM {table} \
         WHERE {id} = ANY($1) AND embedding IS NOT NULL AND model = $2",
        id = kind.embeddings_id_column(),
        table = kind.embeddings_table(),
    ))
    .bind::<diesel::sql_types::Array<BigInt>, _>(scope_ids.to_vec())
    .bind::<Text, _>(MODEL_NAME)
    .load::<StoredVector>(conn)
    .map_err(|e| log::error!("Couldn't load {} embeddings: {:?}", kind.name(), e))
    .ok()?;

    let mut matches: Vec<(i64, f32)> = rows
        .iter()
        .filter_map(|row| Some((row.id, similarity(&query, &row.embedding)?)))
        .filter(|(_, similarity)| *similarity >= MIN_SIMILARITY)
        .collect();
    matches.sort_by(|a, b| b.1.total_cmp(&a.1).then(b.0.cmp(&a.0)));
    matches.truncate(SEMANTIC_RESULT_LIMIT);
    Some(matches)
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
pub struct SyncContext<'a> {
    pub embedder: Option<Embedder>,
    pub deadline: Instant,
    pub threads: usize,
    pub before_model_load: Box<dyn FnMut() -> bool + 'a>,
}

impl SyncContext<'static> {
    /// No gate and an hour's budget -- for tests and one-off tools.
    pub fn unrestricted() -> Self {
        SyncContext {
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

    loop {
        if Instant::now() >= ctx.deadline {
            stats.out_of_time = true;
            return Ok(stats);
        }
        let batch = sql_query(format!(
            "SELECT s.{sid} AS id, d.document, hashtextextended(d.document, 0) AS document_hash, false AS up_to_date \
             FROM {source} s \
             CROSS JOIN LATERAL (SELECT coalesce({doc}(s.{sid}), '') AS document) d \
             WHERE NOT EXISTS (SELECT 1 FROM {table} e WHERE e.{eid} = s.{sid}) \
             ORDER BY s.{sid} DESC LIMIT $1",
            sid = kind.source_id_column(),
            source = kind.source_table(),
            doc = kind.document_function(),
            table = kind.embeddings_table(),
            eid = kind.embeddings_id_column(),
        ))
        .bind::<BigInt, _>(WRITE_BATCH)
        .load::<SourceDocument>(conn)?;
        if batch.is_empty() {
            break;
        }
        store_embeddings(conn, kind, &batch, ctx, &mut stats)?;
    }

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
    .bind::<Text, _>(MODEL_NAME)
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
            log::info!("Loading embedding model {} (downloads it the first time)...", MODEL_NAME);
            ctx.embedder = Some(Embedder::load(ctx.threads)?);
        }
        let texts: Vec<String> = to_embed.iter().map(|r| r.document.clone()).collect();
        let embedded = ctx.embedder.as_mut().unwrap().embed(&texts)?;
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
        .bind::<Text, _>(MODEL_NAME)
        .bind::<BigInt, _>(row.document_hash)
        .bind::<Nullable<Binary>, _>(bytes)
        .execute(conn)?;
    }
    Ok(())
}

#[cfg(test)]
mod unit_tests {
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
