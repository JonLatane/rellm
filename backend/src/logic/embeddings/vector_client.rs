//! The Rellm server's end of the per-namespace vector search service (`RemoteIndex`): a `SemanticIndex` that asks
//! that service for the nearest ids instead of scanning vectors out of Postgres. Because the service holds *every*
//! vector, it can answer without a `scope` ("anywhere"), which lifts the "newest 10k rows" window of
//! `PostgresScanIndex`; the caller then applies visibility to the ids it gets back.
//!
//! The service is OPTIONAL: without it (not configured, down, or still building) searches use the existing Postgres
//! scan, which needs nothing but Postgres.
//!
//! Configuration: `RELLM_VECTOR_SERVICE_URL` (e.g. `http://rellm-vector:8091`) turns it on;
//! `RELLM_VECTOR_SERVICE_SECRET` is sent as `x-rellm-internal-secret`. Calls go through one dedicated thread that
//! owns a small async runtime and the gRPC channel, so this works from any synchronous context.
use std::sync::mpsc;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use tonic::metadata::MetadataValue;
use tonic::transport::Channel;
use tonic::Request;

use super::index::{IndexQuery, SemanticIndex};
use crate::db_connection::PgPooledConnection;
use crate::internal_protos::vector_search_service_client::VectorSearchServiceClient;
use crate::internal_protos::{VectorSearchRequest, VectorSearchResponse};

const SEARCH_TIMEOUT: Duration = Duration::from_secs(3);
/// After the service fails (unreachable, refused, timed out) the client stops asking for this long and says it can't
/// answer, so callers use the Postgres scan straight away instead of waiting out `SEARCH_TIMEOUT` on every search.
const DOWN_FOR: Duration = Duration::from_secs(15);
/// The same, when the service answered "still building": it is up, just not ready, so look again sooner.
const NOT_READY_FOR: Duration = Duration::from_secs(5);

pub fn vector_service_config() -> Option<(String, Option<String>)> {
    let url = std::env::var("RELLM_VECTOR_SERVICE_URL").ok().filter(|u| !u.trim().is_empty())?;
    let secret = std::env::var("RELLM_VECTOR_SERVICE_SECRET").ok().filter(|s| !s.is_empty());
    Some((url, secret))
}

struct Job {
    request: VectorSearchRequest,
    reply: mpsc::Sender<Result<VectorSearchResponse, String>>,
}

/// The vector search service is OPTIONAL at runtime: whenever it can't answer, this index reports so (`supports_global`
/// is false, `search` is `None`) and every search falls back to the Postgres scan -- the pgvector-free path that works
/// with no extra service at all. `skip_until` is the circuit breaker that keeps that fallback fast.
pub struct RemoteIndex {
    jobs: Mutex<mpsc::Sender<Job>>,
    skip_until: Mutex<Option<Instant>>,
}

impl RemoteIndex {
    /// Starts the client thread; the connection itself is lazy, so an unreachable service just makes searches
    /// answer `None` -- callers then use the Postgres scan -- until it's back.
    pub fn new(url: &str, secret: Option<String>) -> anyhow::Result<RemoteIndex> {
        let (jobs, job_rx) = mpsc::channel::<Job>();
        let (ready_tx, ready_rx) = mpsc::channel::<anyhow::Result<()>>();
        let url = url.to_string();
        std::thread::Builder::new().name("vector-service-client".to_string()).spawn(move || {
            let runtime = match tokio::runtime::Builder::new_current_thread().enable_all().build() {
                Ok(r) => r,
                Err(e) => return drop(ready_tx.send(Err(e.into()))),
            };
            let guard = runtime.enter(); // creating the channel needs a runtime context
            let channel: Result<Channel, anyhow::Error> = Channel::from_shared(url)
                .map(|c| c.connect_timeout(Duration::from_secs(3)).tcp_keepalive(Some(Duration::from_secs(30))).connect_lazy())
                .map_err(Into::into);
            drop(guard);
            let mut client = match channel {
                Ok(channel) => VectorSearchServiceClient::new(channel),
                Err(e) => return drop(ready_tx.send(Err(e))),
            };
            let _ = ready_tx.send(Ok(()));
            while let Ok(Job { request, reply }) = job_rx.recv() {
                let result = runtime.block_on(async {
                    let mut req = Request::new(request);
                    req.set_timeout(SEARCH_TIMEOUT);
                    if let Some(secret) = &secret {
                        req.metadata_mut().insert(
                            super::model_service::SECRET_HEADER,
                            MetadataValue::try_from(secret.as_str()).map_err(|e| e.to_string())?,
                        );
                    }
                    client.search(req).await.map(|r| r.into_inner()).map_err(|e| e.to_string())
                });
                let _ = reply.send(result);
            }
        })?;
        ready_rx.recv().map_err(|_| anyhow::anyhow!("the vector client thread died"))??;
        Ok(RemoteIndex { jobs: Mutex::new(jobs), skip_until: Mutex::new(None) })
    }

    /// Whether the breaker is open (the service failed or was still building a moment ago).
    fn skipping(&self) -> bool {
        self.skip_until.lock().unwrap().map_or(false, |until| Instant::now() < until)
    }

    fn skip_for(&self, how_long: Duration) {
        *self.skip_until.lock().unwrap() = Some(Instant::now() + how_long);
    }
}

impl SemanticIndex for RemoteIndex {
    fn supports_global(&self) -> bool {
        // Only while the service is believed to be up: when it isn't, callers take the Postgres-scan path directly.
        !self.skipping()
    }

    fn search(&self, _conn: &mut PgPooledConnection, query: &IndexQuery) -> Option<Vec<(i64, f32)>> {
        if self.skipping() {
            return None;
        }
        let (reply_tx, reply_rx) = mpsc::channel();
        self.jobs
            .lock()
            .ok()?
            .send(Job {
                request: VectorSearchRequest {
                    kind: query.kind.name().to_string(),
                    model_id: query.spec.id.to_string(),
                    vector: query.vector.to_vec(),
                    limit: query.limit as u32,
                    min_similarity: query.spec.min_similarity,
                },
                reply: reply_tx,
            })
            .ok()?;
        let response = match reply_rx.recv_timeout(SEARCH_TIMEOUT + Duration::from_secs(1)) {
            Ok(Ok(response)) => response,
            Ok(Err(e)) => {
                log::warn!("The vector search service failed ({}); using the Postgres scan for {}s.", crate::logic::log_redaction::safe_error(&e), DOWN_FOR.as_secs());
                self.skip_for(DOWN_FOR);
                return None;
            }
            Err(_) => {
                log::warn!("The vector search service didn't answer in time; using the Postgres scan for {}s.", DOWN_FOR.as_secs());
                self.skip_for(DOWN_FOR);
                return None;
            }
        };
        if !response.ready {
            // Still building (or indexing another model): scan Postgres for now, and look again shortly.
            self.skip_for(NOT_READY_FOR);
            return None;
        }
        let mut matches: Vec<(i64, f32)> = response.matches.into_iter().map(|m| (m.id, m.similarity)).collect();
        // A scoped query keeps only the caller's ids (they are its visible ids); the service answered globally.
        if let Some(scope) = query.scope {
            let allowed: std::collections::HashSet<i64> = scope.iter().copied().collect();
            matches.retain(|(id, _)| allowed.contains(id));
        }
        Some(matches)
    }
}
