use diesel::sql_types::{BigInt, Binary, Text};
use diesel::*;

use super::{EmbeddingKind, ModelSpec};
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
    /// `(id, cosine similarity)` best first, only at least `spec.min_similarity` similar, at most
    /// `limit`. `None` when this index can't answer the query right now (not built yet, unreachable,
    /// or it needs a `scope` and got none) -- callers then keep their full-text results.
    fn search(&self, conn: &mut PgPooledConnection, query: &IndexQuery) -> Option<Vec<(i64, f32)>>;
}

/// The index everything searches through: the Postgres scan unless another one is configured.
pub fn semantic_index() -> &'static dyn SemanticIndex {
    &PostgresScanIndex
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
        let rows = sql_query(format!(
            "SELECT {id} AS id, embedding FROM {table} \
             WHERE {id} = ANY($1) AND embedding IS NOT NULL AND model = $2",
            id = query.kind.embeddings_id_column(),
            table = query.kind.embeddings_table(),
        ))
        .bind::<diesel::sql_types::Array<BigInt>, _>(scope.to_vec())
        .bind::<Text, _>(query.spec.id)
        .load::<StoredVector>(conn)
        .map_err(|e| log::error!("Couldn't load {} embeddings: {:?}", query.kind.name(), e))
        .ok()?;

        let mut matches: Vec<(i64, f32)> = rows
            .iter()
            .filter_map(|row| Some((row.id, similarity(query.vector, &row.embedding)?)))
            .filter(|(_, similarity)| *similarity >= query.spec.min_similarity)
            .collect();
        matches.sort_by(|a, b| b.1.total_cmp(&a.1).then(b.0.cmp(&a.0)));
        matches.truncate(query.limit);
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

