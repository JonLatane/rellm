//! The per-namespace vector search service: keeps every embedding of one namespace's Postgres in a USearch
//! index (HNSW graph, vectors quantized to int8) and answers nearest-neighbor queries over gRPC
//! (`internal_protos/rellm_internal.proto`, `VectorSearchService`). One pod per namespace, shared by all the
//! namespace's servers, so the vectors are held once rather than once per server and never scanned out of
//! Postgres per search.
//!
//! It knows nothing about who may see what: it returns the nearest ids and the Rellm server applies its
//! visibility rules to them in Postgres. Postgres stays the source of truth; the index is a rebuildable cache:
//!   * on start (and every `REBUILD_EVERY`) it reads all of a kind's embeddings for its model into a fresh index,
//!     which also drops deleted rows;
//!   * in between it polls `(embedded_at, id)` past its last position (`POLL_EVERY`) to add new and re-embedded
//!     rows. Rows that became un-embeddable in between linger until the next rebuild; the server's visibility
//!     query discards any id that no longer exists.
//! Until a kind's first build finishes `Search` answers `ready: false` and the server just uses the Postgres scan (the
//! service is optional).
use std::sync::{Arc, RwLock};
use std::time::{Duration, Instant, SystemTime};

use diesel::sql_types::{BigInt, Binary, Text, Timestamp};
use diesel::*;
use tonic::transport::Server;
use tonic::{Request, Response, Status};
use usearch::ffi::{IndexOptions, MetricKind, ScalarKind};
use usearch::{new_index, Index};

use super::model_service::SECRET_HEADER;
use super::{EmbeddingKind, ModelSpec};
use crate::db_connection::PgPooledConnection;
use crate::internal_protos::vector_search_service_server::{VectorSearchService, VectorSearchServiceServer};
use crate::internal_protos::{
    KindStatus, Match, StatusRequest, StatusResponse, VectorSearchRequest, VectorSearchResponse,
};

const PAGE: i64 = 2_000;
pub const POLL_EVERY: Duration = Duration::from_secs(10);
pub const REBUILD_EVERY: Duration = Duration::from_secs(30 * 60);
/// Each catch-up starts this far *before* the last row it applied. `embedded_at` is Postgres's `NOW()` -- the start of
/// the writing transaction -- so a row can become visible after a poll has already moved past its timestamp; looking
/// back picks those up. Re-applying a row is idempotent, so the only cost is a few repeated rows per poll.
const OVERLAP: Duration = Duration::from_secs(30);
/// The most matches one `Search` returns, whatever the caller asks.
const MAX_LIMIT: usize = 5_000;

struct KindState {
    index: Option<Index>,
    /// The model this index was built for. An index answers only for that model and is rebuilt when the model changes,
    /// so a stale one can never serve vectors of the wrong model (or the wrong size).
    model: &'static str,
    ready: bool,
    /// `(embedded_at, id)` of the last row applied.
    position: (SystemTime, i64),
    vectors: u64,
    built_at: Instant,
}

impl KindState {
    fn empty() -> Self {
        KindState { index: None, model: "", ready: false, position: (SystemTime::UNIX_EPOCH, 0), vectors: 0, built_at: Instant::now() }
    }
}

/// The indexes of one namespace: one USearch index per `EmbeddingKind`, all for one model.
pub struct VectorIndexes {
    /// The model being indexed. Switchable: when the cluster's model service moves to another model, `switch_model`
    /// points this at it and every kind is rebuilt from the rows that model has embedded so far.
    spec: RwLock<&'static ModelSpec>,
    kinds: Vec<(EmbeddingKind, RwLock<KindState>)>,
}

#[derive(QueryableByName)]
struct Row {
    #[diesel(sql_type = BigInt)]
    id: i64,
    #[diesel(sql_type = Binary)]
    embedding: Vec<u8>,
    #[diesel(sql_type = Timestamp)]
    embedded_at: SystemTime,
}

impl VectorIndexes {
    pub fn new(spec: &'static ModelSpec) -> Arc<VectorIndexes> {
        Arc::new(VectorIndexes {
            spec: RwLock::new(spec),
            kinds: EmbeddingKind::ALL.iter().map(|k| (*k, RwLock::new(KindState::empty()))).collect(),
        })
    }

    pub fn spec(&self) -> &'static ModelSpec {
        *self.spec.read().unwrap()
    }

    /// Follows the cluster to a different model: drops every index (freeing their memory; until a kind is rebuilt its
    /// searches answer "not ready", so clients scan Postgres meanwhile) and indexes the new model's rows from now on.
    /// Rows the new model hasn't embedded yet simply aren't there until the embedding job gets to them.
    pub fn switch_model(&self, new: &'static ModelSpec) {
        {
            let mut spec = self.spec.write().unwrap();
            if spec.id == new.id {
                return;
            }
            log::warn!("Switching the vector index from model {} to {}; rebuilding.", spec.id, new.id);
            *spec = new;
        }
        for (_, lock) in &self.kinds {
            *lock.write().unwrap() = KindState::empty();
        }
    }

    fn new_index(&self, spec: &'static ModelSpec) -> anyhow::Result<Index> {
        let options = IndexOptions {
            dimensions: spec.dimensions as usize,
            metric: MetricKind::Cos,
            // int8 quarters the memory of f32 for a small, measured-by-the-tests loss in accuracy.
            quantization: ScalarKind::I8,
            connectivity: 0,
            expansion_add: 0,
            expansion_search: 0,
            multi: false,
        };
        Ok(new_index(&options)?)
    }

    fn fetch(&self, conn: &mut PgPooledConnection, kind: EmbeddingKind, spec: &'static ModelSpec, after: (SystemTime, i64)) -> anyhow::Result<Vec<Row>> {
        Ok(sql_query(format!(
            "SELECT {id} AS id, embedding, embedded_at FROM {table} \
             WHERE model = $1 AND embedding IS NOT NULL AND (embedded_at, {id}) > ($2, $3) \
             ORDER BY embedded_at, {id} LIMIT $4",
            id = kind.embeddings_id_column(),
            table = kind.embeddings_table(),
        ))
        .bind::<Text, _>(spec.id)
        .bind::<Timestamp, _>(after.0)
        .bind::<BigInt, _>(after.1)
        .bind::<BigInt, _>(PAGE)
        .load::<Row>(conn)?)
    }

    fn add_rows(&self, spec: &'static ModelSpec, index: &Index, rows: &[Row]) -> anyhow::Result<u64> {
        let dims = spec.dimensions as usize;
        let needed = index.size() + rows.len();
        if needed > index.capacity() {
            index.reserve(needed.max(index.capacity() * 2).max(1024))?;
        }
        let mut added = 0;
        for row in rows {
            if row.embedding.len() != dims * 4 {
                continue; // another model's leftovers
            }
            let vector: Vec<f32> = row.embedding.chunks_exact(4).map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]])).collect();
            let key = row.id as u64;
            if index.contains(key) {
                index.remove(key)?; // re-embedded: replace
            }
            index.add(key, &vector)?;
            added += 1;
        }
        Ok(added)
    }

    /// One pass over `kind`: a full (re)build if it has none yet or is due, otherwise catch up with new rows.
    pub fn sync_kind(&self, conn: &mut PgPooledConnection, kind: EmbeddingKind) -> anyhow::Result<()> {
        let spec = self.spec(); // one model for this whole pass, even if the cluster switches meanwhile
        let lock = &self.kinds.iter().find(|(k, _)| *k == kind).expect("every kind has a slot").1;
        let rebuild = {
            let state = lock.read().unwrap();
            !state.ready || state.model != spec.id || state.built_at.elapsed() >= REBUILD_EVERY
        };
        if rebuild {
            // Build off to the side, then swap in: searches keep using the old index meanwhile.
            let index = self.new_index(spec)?;
            let mut position = (SystemTime::UNIX_EPOCH, 0);
            let mut vectors = 0;
            loop {
                let rows = self.fetch(conn, kind, spec, position)?;
                let Some(last) = rows.last() else { break };
                position = (last.embedded_at, last.id);
                vectors += self.add_rows(spec, &index, &rows)?;
                if (rows.len() as i64) < PAGE {
                    break;
                }
            }
            let size = index.size() as u64;
            log::info!("Built the {} index for {}: {} vectors ({} MB).", kind.name(), spec.id, size, index.memory_usage() / (1024 * 1024));
            // If the model switched while this was building, the next pass sees the mismatch and rebuilds again.
            *lock.write().unwrap() = KindState { index: Some(index), model: spec.id, ready: true, position, vectors: size.max(vectors.min(size)), built_at: Instant::now() };
            return Ok(());
        }
        // The first read looks back by `OVERLAP`; later pages of this pass continue from the exact position.
        let start = lock.read().unwrap().position;
        let mut after = (start.0.checked_sub(OVERLAP).unwrap_or(SystemTime::UNIX_EPOCH), 0);
        loop {
            let rows = self.fetch(conn, kind, spec, after)?;
            let Some(last) = rows.last() else { break };
            after = (last.embedded_at, last.id);
            let mut state = lock.write().unwrap();
            if state.model != spec.id {
                break; // switched models under us: the next pass rebuilds
            }
            let index = state.index.as_ref().expect("a ready state has an index");
            self.add_rows(spec, index, &rows)?;
            let size = index.size() as u64;
            state.vectors = size;
            if after > state.position {
                state.position = after;
            }
            if (rows.len() as i64) < PAGE {
                break;
            }
        }
        Ok(())
    }

    /// One `sync_kind` for every kind; errors are logged and the other kinds still run.
    pub fn sync_all(&self, conn: &mut PgPooledConnection) {
        for (kind, _) in &self.kinds {
            if let Err(e) = self.sync_kind(conn, *kind) {
                log::error!("Couldn't sync the {} index: {:?}", kind.name(), e);
            }
        }
    }

    /// Nearest `limit` ids to `vector` at least `min_similarity` cosine-similar. `None` if this kind isn't built
    /// yet, the model isn't the one indexed, or the vector is the wrong size.
    pub fn search(&self, kind: EmbeddingKind, model_id: &str, vector: &[f32], limit: usize, min_similarity: f32) -> Option<Vec<(i64, f32)>> {
        let spec = self.spec();
        if model_id != spec.id || vector.len() != spec.dimensions as usize {
            return None;
        }
        let state = self.kinds.iter().find(|(k, _)| *k == kind)?.1.read().unwrap();
        if !state.ready || state.model != spec.id {
            return None;
        }
        let matches = state.index.as_ref()?.search(vector, limit.clamp(1, MAX_LIMIT)).ok()?;
        let mut found: Vec<(i64, f32)> = matches
            .keys
            .iter()
            .zip(matches.distances.iter())
            .map(|(key, distance)| (*key as i64, 1.0 - *distance))
            .filter(|(_, similarity)| *similarity >= min_similarity)
            .collect();
        found.sort_by(|a, b| b.1.total_cmp(&a.1).then(b.0.cmp(&a.0)));
        Some(found)
    }

    pub fn status(&self) -> StatusResponse {
        StatusResponse {
            model_id: self.spec().id.to_string(),
            kinds: self
                .kinds
                .iter()
                .map(|(kind, lock)| {
                    let state = lock.read().unwrap();
                    KindStatus {
                        kind: kind.name().to_string(),
                        ready: state.ready,
                        vectors: state.vectors,
                        memory_bytes: state.index.as_ref().map_or(0, |i| i.memory_usage() as u64),
                    }
                })
                .collect(),
        }
    }
}

/// Keeps `indexes` in step with Postgres, forever: `sync_all` every `POLL_EVERY`. Run on its own thread.
///
/// With `follow_cluster_model` it also asks the cluster's model service which model it runs each cycle and switches the
/// index to it when that changes (see `VectorIndexes::switch_model`); a service that can't be reached just means "keep
/// the model we have".
pub fn run_indexer(indexes: Arc<VectorIndexes>, mut conn: PgPooledConnection, follow_cluster_model: bool) {
    loop {
        if follow_cluster_model {
            if let Some(model) = super::refresh_cluster_model_blocking() {
                indexes.switch_model(model);
            }
        }
        indexes.sync_all(&mut conn);
        std::thread::sleep(POLL_EVERY);
    }
}

pub struct VectorSearchServiceImpl {
    indexes: Arc<VectorIndexes>,
    secret: Option<String>,
}

impl VectorSearchServiceImpl {
    pub fn new(indexes: Arc<VectorIndexes>, secret: Option<String>) -> Self {
        VectorSearchServiceImpl { indexes, secret }
    }

    fn authorize<T>(&self, request: &Request<T>) -> Result<(), Status> {
        let Some(expected) = &self.secret else { return Ok(()) };
        let given = request.metadata().get(SECRET_HEADER).and_then(|v| v.to_str().ok());
        let matches = given.map_or(false, |g| {
            g.len() == expected.len() && g.bytes().zip(expected.bytes()).fold(0u8, |acc, (a, b)| acc | (a ^ b)) == 0
        });
        if matches { Ok(()) } else { Err(Status::unauthenticated("bad_internal_secret")) }
    }
}

#[tonic::async_trait]
impl VectorSearchService for VectorSearchServiceImpl {
    async fn search(&self, request: Request<VectorSearchRequest>) -> Result<Response<VectorSearchResponse>, Status> {
        self.authorize(&request)?;
        let request = request.into_inner();
        let kind = EmbeddingKind::ALL
            .iter()
            .copied()
            .find(|k| k.name() == request.kind)
            .ok_or_else(|| Status::invalid_argument("unknown_kind"))?;
        let found = self.indexes.search(kind, &request.model_id, &request.vector, request.limit as usize, request.min_similarity);
        Ok(Response::new(match found {
            Some(matches) => VectorSearchResponse {
                ready: true,
                matches: matches.into_iter().map(|(id, similarity)| Match { id, similarity }).collect(),
            },
            None => VectorSearchResponse { ready: false, matches: vec![] },
        }))
    }

    async fn status(&self, request: Request<StatusRequest>) -> Result<Response<StatusResponse>, Status> {
        self.authorize(&request)?;
        Ok(Response::new(self.indexes.status()))
    }
}

pub async fn serve(addr: std::net::SocketAddr, indexes: Arc<VectorIndexes>, secret: Option<String>) -> anyhow::Result<()> {
    log::info!("Vector search service listening on {} (model {}).", addr, indexes.spec().id);
    Server::builder()
        .add_service(VectorSearchServiceServer::new(VectorSearchServiceImpl::new(indexes, secret)))
        .serve(addr)
        .await?;
    Ok(())
}
