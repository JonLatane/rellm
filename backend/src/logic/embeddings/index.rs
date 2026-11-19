use diesel::sql_types::{BigInt, Binary, Text};
use diesel::*;

use super::{search_timing, EmbeddingKind, ModelSpec};
use crate::db_connection::PgPooledConnection;

/// One nearest-neighbor question: which rows of `kind` are most like `vector` (made by `spec`'s model).
pub struct IndexQuery<'a> {
    pub kind: EmbeddingKind,
    pub spec: &'static ModelSpec,
    /// L2-normalized, from `TextEmbedder::embed_query`.
    pub vector: &'a [f32],
    /// If set, only these ids may be returned -- the caller's *visible* ids, so an index never widens
    /// what a viewer can see. `None` means "anywhere in the index", which only an index that holds
    /// every vector (not one that scans Postgres per query) can answer.
    pub scope: Option<&'a [i64]>,
    pub limit: usize,
}

/// Answers `IndexQuery`s: the seam between *how* similar rows are found and what's done with them.
/// `PostgresScanIndex` reads the vectors from Postgres per query; an in-memory or out-of-process
/// vector index implements the same trait.
pub trait SemanticIndex: Send + Sync {
    /// Whether this index holds every vector and so can answer a query with no `scope` ("anywhere"). Callers
    /// that get `true` skip gathering a candidate scope and instead apply visibility to the ids returned.
    fn supports_global(&self) -> bool {
        false
    }

    /// `(id, cosine similarity)` best first, only at least `spec.min_similarity` similar, at most
    /// `limit`. `None` when this index can't answer the query right now (not built yet, unreachable,
    /// or it needs a `scope` and got none) -- callers then keep their full-text results.
    fn search(&self, conn: &mut PgPooledConnection, query: &IndexQuery) -> Option<Vec<(i64, f32)>>;
}

static CONFIGURED_INDEX: std::sync::RwLock<Option<std::sync::Arc<dyn SemanticIndex>>> = std::sync::RwLock::new(None);

/// The index everything searches through: the namespace's vector search service when `RELLM_VECTOR_SERVICE_URL`
/// is set, otherwise the Postgres scan. Created on first use.
pub fn semantic_index() -> std::sync::Arc<dyn SemanticIndex> {
    if let Some(index) = CONFIGURED_INDEX.read().unwrap().as_ref() {
        return index.clone();
    }
    let mut slot = CONFIGURED_INDEX.write().unwrap();
    if let Some(index) = slot.as_ref() {
        return index.clone();
    }
    let index: std::sync::Arc<dyn SemanticIndex> = match super::vector_client::vector_service_config() {
        Some((url, secret)) => match super::vector_client::RemoteIndex::new(&url, secret) {
            Ok(remote) => std::sync::Arc::new(remote),
            Err(e) => {
                log::error!("Couldn't set up the vector search client; scanning Postgres instead: {:?}", crate::logic::log_redaction::safe_error(&e));
                std::sync::Arc::new(PostgresScanIndex)
            }
        },
        None => std::sync::Arc::new(PostgresScanIndex),
    };
    *slot = Some(index.clone());
    index
}

/// Replaces the index everything searches through (a test double, or one built at startup).
pub fn install_semantic_index(index: Box<dyn SemanticIndex>) {
    *CONFIGURED_INDEX.write().unwrap() = Some(std::sync::Arc::from(index));
}

/// Forgets the installed index, so the next `semantic_index()` picks one from the environment again.
pub fn reset_semantic_index() {
    *CONFIGURED_INDEX.write().unwrap() = None;
}

#[derive(QueryableByName)]
struct StoredVector {
    #[diesel(sql_type = BigInt)]
    id: i64,
    #[diesel(sql_type = Binary)]
    embedding: Vec<u8>,
}

/// Reads the candidate rows' vectors from Postgres (by primary key, so only `scope`'s rows) and scores
/// them here. No index structure and nothing resident, at the cost of reading every candidate per
/// query -- which is why callers cap the scope (`SEMANTIC_SCAN_LIMIT`). Needs a `scope`.
pub struct PostgresScanIndex;

impl SemanticIndex for PostgresScanIndex {
    fn search(&self, conn: &mut PgPooledConnection, query: &IndexQuery) -> Option<Vec<(i64, f32)>> {
        let scope = query.scope?;
        if scope.is_empty() {
            return None;
        }
        let load_started = std::time::Instant::now();
        let rows = sql_query(format!(
            "SELECT {id} AS id, embedding FROM {table} \
             WHERE {id} = ANY($1) AND embedding IS NOT NULL AND model = $2",
            id = query.kind.embeddings_id_column(),
            table = query.kind.embeddings_table(),
        ))
        .bind::<diesel::sql_types::Array<BigInt>, _>(scope.to_vec())
        .bind::<Text, _>(query.spec.id)
        .load::<StoredVector>(conn)
        .map_err(|e| log::error!("Couldn't load {} embeddings: {:?}", query.kind.name(), crate::logic::log_redaction::safe_error(&e)))
        .ok()?;
        // How much comes out of Postgres and into this process for every scoped search: the candidates' vectors.
        let megabytes = rows.iter().map(|row| row.embedding.len()).sum::<usize>() as f64 / (1024.0 * 1024.0);
        search_timing::record_with(search_timing::Stage::VectorLoad, load_started, format!("{} vectors, {:.1}MB", rows.len(), megabytes));

        let scoring_started = std::time::Instant::now();
        let mut matches: Vec<(i64, f32)> = rows
            .iter()
            .filter_map(|row| Some((row.id, similarity(query.vector, &row.embedding)?)))
            .filter(|(_, similarity)| *similarity >= query.spec.min_similarity)
            .collect();
        matches.sort_by(|a, b| b.1.total_cmp(&a.1).then(b.0.cmp(&a.0)));
        matches.truncate(query.limit);
        search_timing::record(search_timing::Stage::Similarity, scoring_started);
        Some(matches)
    }
}

/// Dot product of a vector and stored bytes -- cosine similarity, both being normalized. `None` if
/// the stored vector has a different dimension (a different model's leftovers).
pub(super) fn similarity(query: &[f32], stored: &[u8]) -> Option<f32> {
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

