//! The cluster-shared model service: one process per cluster holds ONE embedding model and embeds text for
//! every namespace (see `internal_protos/rellm_internal.proto`, `EmbeddingService`), so the model's RAM is
//! paid once instead of once per namespace server and job. This module has both ends: `serve` (the
//! `embedding_service` binary) and `RemoteEmbedder` (what a Rellm server or job uses instead of loading a
//! model itself -- a `TextEmbedder`, so nothing that embeds knows the difference).
//!
//! Configuration (environment):
//!   * client: `RELLM_EMBEDDING_SERVICE_URL` (e.g. `http://rellm-embedding.rellm-central:8090`) turns it on;
//!     `RELLM_EMBEDDING_SERVICE_SECRET` is sent as `x-rellm-internal-secret`.
//!   * service: `RELLM_EMBEDDING_SERVICE_MODEL` (default `DEFAULT_MODEL_ID`), `RELLM_EMBEDDING_SERVICE_ADDR`
//!     (default `0.0.0.0:8090`), `RELLM_EMBEDDING_SERVICE_SECRET` (required unless
//!     `RELLM_EMBEDDING_SERVICE_INSECURE=1`), `RELLM_EMBEDDING_THREADS`.
//! Because the service hosts one model, every namespace using it uses that model: the admin's own model choice
//! is overridden (`SearchSettings.model_chosen_by_cluster`).
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use tonic::metadata::MetadataValue;
use tonic::transport::{Channel, Server};
use tonic::{Request, Response, Status};

use super::{model_spec, BoxedEmbedder, ModelSpec, TextEmbedder};
use crate::internal_protos::embed_request::Purpose;
use crate::internal_protos::embedding_service_client::EmbeddingServiceClient;
use crate::internal_protos::embedding_service_server::{EmbeddingService, EmbeddingServiceServer};
use crate::internal_protos::{DescribeRequest, EmbedRequest, EmbedResponse, ModelDescription, Vector};

pub const SECRET_HEADER: &str = "x-rellm-internal-secret";
/// Most texts one `Embed` call may carry, and the most bytes in one text -- a request over either is refused
/// (`INVALID_ARGUMENT`) rather than allowed to tie up the one model. (Clients send far fewer, `TEXTS_PER_CALL`; this
/// stays generous so a client from before that change, still sending 64 at a time, keeps working during a rolling deploy.)
pub const MAX_TEXTS_PER_REQUEST: usize = 64;
/// Texts a client puts in one `Embed` call. One model serves every namespace, one request at a time, and every text takes
/// a model run of its own (the service doesn't batch), so a call's length is how long it holds everyone else up: with 64
/// texts a call took long enough that, with several namespaces backfilling at once, calls waited out the client's
/// `CALL_TIMEOUT` in the queue and nothing was ever stored. Short calls finish well inside it and interleave fairly.
pub const TEXTS_PER_CALL: usize = 8;
pub const MAX_TEXT_BYTES: usize = 32 * 1024;
/// Requests allowed to wait for the model at once (it embeds one request at a time). More are refused with
/// `RESOURCE_EXHAUSTED`, so a flood of namespaces degrades to full-text search instead of a growing queue.
const MAX_WAITING: usize = 32;
const CALL_TIMEOUT: Duration = Duration::from_secs(60);

// ---------------------------------------------------------------------------------------------
// Client side
// ---------------------------------------------------------------------------------------------

/// `(url, secret)` if a cluster-shared model service is configured.
pub fn embedding_service_config() -> Option<(String, Option<String>)> {
    let url = std::env::var("RELLM_EMBEDDING_SERVICE_URL").ok().filter(|u| !u.trim().is_empty())?;
    let secret = std::env::var("RELLM_EMBEDDING_SERVICE_SECRET").ok().filter(|s| !s.is_empty());
    Some((url, secret))
}

pub fn embedding_service_configured() -> bool {
    embedding_service_config().is_some()
}

enum Job {
    Embed(Purpose, Vec<String>, mpsc::Sender<anyhow::Result<Vec<Vec<f32>>>>),
}

/// A `TextEmbedder` that embeds through the cluster-shared model service. Calls go through one dedicated thread
/// that owns a small async runtime and the gRPC channel, so this can be used from synchronous code anywhere
/// (a job's `main`, or a request handler already running on a Tokio worker) without touching the caller's runtime.
pub struct RemoteEmbedder {
    spec: &'static ModelSpec,
    jobs: mpsc::Sender<Job>,
}

impl RemoteEmbedder {
    /// Connects (lazily) to `url` and asks which model it runs. Fails if it can't be reached or runs a model
    /// this build doesn't know.
    pub fn connect(url: &str, secret: Option<String>) -> anyhow::Result<RemoteEmbedder> {
        let (jobs, job_rx) = mpsc::channel::<Job>();
        let (ready_tx, ready_rx) = mpsc::channel::<anyhow::Result<&'static ModelSpec>>();
        let url = url.to_string();
        std::thread::Builder::new()
            .name("embedding-service-client".to_string())
            .spawn(move || {
                let runtime = match tokio::runtime::Builder::new_current_thread().enable_all().build() {
                    Ok(r) => r,
                    Err(e) => return drop(ready_tx.send(Err(e.into()))),
                };
                // Creating the channel needs a runtime context (it spawns its connection task).
                let guard = runtime.enter();
                let mut client = match Self::client(&url, &secret) {
                    Ok(c) => c,
                    Err(e) => return drop(ready_tx.send(Err(e))),
                };
                drop(guard);
                let described = runtime.block_on(async {
                    let mut request = Request::new(DescribeRequest {});
                    request.set_timeout(Duration::from_secs(5));
                    attach_secret(&mut request, &secret)?;
                    let described = client.describe(request).await?.into_inner();
                    model_spec(&described.model_id)
                        .ok_or_else(|| anyhow::anyhow!("the model service runs `{}`, which this server doesn't know", described.model_id))
                });
                let spec = match described {
                    Ok(spec) => spec,
                    Err(e) => return drop(ready_tx.send(Err(e))),
                };
                let _ = ready_tx.send(Ok(spec));
                while let Ok(Job::Embed(purpose, texts, reply)) = job_rx.recv() {
                    let result = runtime.block_on(async {
                        let mut request = Request::new(EmbedRequest {
                            purpose: purpose as i32,
                            texts,
                            model_id: spec.id.to_string(),
                        });
                        request.set_timeout(CALL_TIMEOUT);
                        attach_secret(&mut request, &secret)?;
                        let response = client.embed(request).await?.into_inner();
                        Ok(response.vectors.into_iter().map(|v| v.values).collect::<Vec<_>>())
                    });
                    let _ = reply.send(result);
                }
            })?;
        let spec = ready_rx.recv().map_err(|_| anyhow::anyhow!("the embedding client thread died"))??;
        Ok(RemoteEmbedder { spec, jobs })
    }

    fn client(url: &str, _secret: &Option<String>) -> anyhow::Result<EmbeddingServiceClient<Channel>> {
        let channel = Channel::from_shared(url.to_string())?
            .connect_timeout(Duration::from_secs(5))
            .tcp_keepalive(Some(Duration::from_secs(30)))
            .connect_lazy();
        Ok(EmbeddingServiceClient::new(channel))
    }

    fn call(&self, purpose: Purpose, texts: Vec<String>) -> anyhow::Result<Vec<Vec<f32>>> {
        let (reply_tx, reply_rx) = mpsc::channel();
        self.jobs
            .send(Job::Embed(purpose, texts, reply_tx))
            .map_err(|_| anyhow::anyhow!("the embedding client thread is gone"))?;
        let result = reply_rx
            .recv_timeout(CALL_TIMEOUT + Duration::from_secs(5))
            .map_err(|_| anyhow::anyhow!("the model service didn't answer in time"))?;
        // The service runs a different model than the one this embedder was told about (it was restarted with another
        // one): it refuses rather than hand back vectors from the wrong model. Re-check what it runs, so everything
        // following `cluster_model()` -- including a fresh embedder for this process -- moves to the new model.
        if let Err(e) = &result {
            if format!("{:#}", e).contains("model_mismatch") {
                log::warn!("The embedding model service no longer runs {}; re-checking which model it runs.", self.spec.id);
                invalidate_cluster_model();
            }
        }
        result
    }
}

fn attach_secret<T>(request: &mut Request<T>, secret: &Option<String>) -> anyhow::Result<()> {
    if let Some(secret) = secret {
        request.metadata_mut().insert(SECRET_HEADER, MetadataValue::try_from(secret.as_str())?);
    }
    Ok(())
}

impl TextEmbedder for RemoteEmbedder {
    fn spec(&self) -> &'static ModelSpec {
        self.spec
    }
    fn embed_documents(&mut self, texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>> {
        let mut vectors = Vec::with_capacity(texts.len());
        for call in texts.chunks(TEXTS_PER_CALL) {
            vectors.extend(self.call(Purpose::Document, call.to_vec())?);
        }
        Ok(vectors)
    }
    fn embed_query(&mut self, text: &str) -> anyhow::Result<Vec<f32>> {
        self.call(Purpose::Query, vec![text.to_string()])?
            .pop()
            .ok_or_else(|| anyhow::anyhow!("the model service returned no vector"))
    }
}

/// What this process believes the cluster-shared model service runs, and when it last asked. The service hosts ONE
/// model, but an operator can restart it with a different one at any time, so the answer is never final:
///   * it is re-checked every `refresh_every` (the new model is adopted the next time anything asks);
///   * a `model_mismatch` refusal (we sent the old model id) invalidates it, so the very next ask re-checks at once;
///   * until a re-check answers, the last known model stays in force -- a service that is briefly down, or a check
///     that is still in flight, never makes the answer flip to "unknown" and reload everything.
/// Everything that depends on the model (the server's query embedder, the vector service's index) follows
/// `current()` and rebuilds itself when it changes; rows embedded by the old model are simply re-embedded by the job.
pub struct ClusterModelTracker {
    known: Mutex<Option<&'static ModelSpec>>,
    last_asked: Mutex<Option<Instant>>,
    refresh_every: Duration,
    min_gap: Duration,
    invalidated: std::sync::atomic::AtomicBool,
    asking: std::sync::atomic::AtomicBool,
}

/// Even when invalidated, don't ask the service more often than this.
const MIN_GAP_BETWEEN_ASKS: Duration = Duration::from_secs(5);

impl ClusterModelTracker {
    pub const fn new(refresh_every: Duration) -> Self {
        ClusterModelTracker {
            known: Mutex::new(None),
            last_asked: Mutex::new(None),
            refresh_every,
            min_gap: MIN_GAP_BETWEEN_ASKS,
            invalidated: std::sync::atomic::AtomicBool::new(false),
            asking: std::sync::atomic::AtomicBool::new(false),
        }
    }

    /// Overrides the minimum gap between asks (tests use none).
    pub const fn with_min_gap(mut self, min_gap: Duration) -> Self {
        self.min_gap = min_gap;
        self
    }

    /// The model last learned from the service, if any. Never asks.
    pub fn known(&self) -> Option<&'static ModelSpec> {
        *self.known.lock().unwrap()
    }

    /// Forget that the answer is current: the next `current` asks again right away (subject to the minimum gap).
    pub fn invalidate(&self) {
        self.invalidated.store(true, std::sync::atomic::Ordering::SeqCst);
    }

    fn due(&self) -> bool {
        let asked = *self.last_asked.lock().unwrap();
        let since = asked.map(|at| at.elapsed());
        if since.map_or(false, |d| d < self.min_gap) {
            return false;
        }
        self.known().is_none()
            || self.invalidated.load(std::sync::atomic::Ordering::SeqCst)
            || since.map_or(true, |d| d >= self.refresh_every)
    }

    /// The model to use now: the last known one. Never blocks -- if a re-check is due it starts one on a background
    /// thread (at most one at a time) and the answer it finds is adopted by the next call.
    pub fn current(&'static self, url: &str, secret: Option<String>) -> Option<&'static ModelSpec> {
        if self.due() && !self.asking.swap(true, std::sync::atomic::Ordering::SeqCst) {
            let url = url.to_string();
            let spawned = std::thread::Builder::new().name("embedding-service-probe".to_string()).spawn(move || {
                self.refresh_blocking(&url, secret);
                self.asking.store(false, std::sync::atomic::Ordering::SeqCst);
            });
            if spawned.is_err() {
                self.asking.store(false, std::sync::atomic::Ordering::SeqCst);
            }
        }
        self.known()
    }

    /// Asks the service now (a few seconds at most) and records its answer. If it can't be reached the last known
    /// model is kept. Returns what is known afterwards.
    pub fn refresh_blocking(&self, url: &str, secret: Option<String>) -> Option<&'static ModelSpec> {
        *self.last_asked.lock().unwrap() = Some(Instant::now());
        match RemoteEmbedder::connect(url, secret) {
            Ok(embedder) => {
                let mut known = self.known.lock().unwrap();
                match *known {
                    Some(old) if old.id != embedder.spec.id => log::warn!(
                        "The cluster's embedding model service now runs {} (was {}); following it.",
                        embedder.spec.id,
                        old.id
                    ),
                    _ => {}
                }
                *known = Some(embedder.spec);
                self.invalidated.store(false, std::sync::atomic::Ordering::SeqCst);
            }
            Err(e) => log::warn!("The embedding model service isn't available: {:?}", crate::logic::log_redaction::safe_error(&e)),
        }
        self.known()
    }
}

static CLUSTER: ClusterModelTracker = ClusterModelTracker::new(Duration::from_secs(60));

/// The model the cluster-shared service runs, when one is configured and has answered: the last known one, re-checked
/// in the background (see `ClusterModelTracker`). Never blocks; `None` until the service has answered once.
pub fn cluster_model() -> Option<&'static ModelSpec> {
    let (url, secret) = embedding_service_config()?;
    CLUSTER.current(&url, secret)
}

/// Like `cluster_model` but, until a model is known, waits for the service to answer (a few seconds at most): for
/// callers that can't proceed without one (the vector service at startup, tests).
pub fn cluster_model_blocking() -> Option<&'static ModelSpec> {
    let (url, secret) = embedding_service_config()?;
    CLUSTER.known().or_else(|| CLUSTER.refresh_blocking(&url, secret))
}

/// Asks the service right now and returns what it runs (the last known model if it can't be reached): for loops that
/// must notice a model change promptly (the vector service's indexer).
pub fn refresh_cluster_model_blocking() -> Option<&'static ModelSpec> {
    let (url, secret) = embedding_service_config()?;
    CLUSTER.refresh_blocking(&url, secret)
}

/// The service refused us for sending a model id it no longer runs: re-check it at the next opportunity.
pub fn invalidate_cluster_model() {
    CLUSTER.invalidate();
}

// ---------------------------------------------------------------------------------------------
// Service side
// ---------------------------------------------------------------------------------------------

pub struct EmbeddingServiceImpl {
    /// A tokio mutex on purpose: it queues waiters first come, first served (a std mutex makes no such promise), and a
    /// request abandoned while it waits simply leaves the queue instead of running later for nobody.
    embedder: Arc<tokio::sync::Mutex<BoxedEmbedder>>,
    /// The last model read from the embedder. Reading it must never wait for the embedder's mutex (held for the whole of
    /// an inference, which would tie up async workers), so while an inference runs this answers from the cache; a real
    /// service never changes model, so the cache is never stale.
    spec: Mutex<&'static ModelSpec>,
    secret: Option<String>,
    waiting: Arc<tokio::sync::Semaphore>,
}

impl EmbeddingServiceImpl {
    /// `secret: None` disables authentication (only for a service reachable by nothing but trusted callers).
    pub fn new(embedder: BoxedEmbedder, secret: Option<String>) -> Self {
        EmbeddingServiceImpl {
            spec: Mutex::new(embedder.spec()),
            embedder: Arc::new(tokio::sync::Mutex::new(embedder)),
            secret,
            waiting: Arc::new(tokio::sync::Semaphore::new(MAX_WAITING)),
        }
    }

    fn authorize<T>(&self, request: &Request<T>) -> Result<(), Status> {
        let Some(expected) = &self.secret else { return Ok(()) };
        let given = request.metadata().get(SECRET_HEADER).and_then(|v| v.to_str().ok());
        // Constant-time-ish comparison: don't leak the secret's prefix through timing.
        let matches = given.map_or(false, |g| {
            g.len() == expected.len() && g.bytes().zip(expected.bytes()).fold(0u8, |acc, (a, b)| acc | (a ^ b)) == 0
        });
        if matches { Ok(()) } else { Err(Status::unauthenticated("bad_internal_secret")) }
    }

    fn spec(&self) -> &'static ModelSpec {
        match self.embedder.try_lock() {
            Ok(embedder) => {
                let live = embedder.spec();
                *self.spec.lock().unwrap() = live;
                live
            }
            Err(_) => *self.spec.lock().unwrap(),
        }
    }
}

/// Sets its flag when dropped: how a request's blocking run learns the client has gone (tonic drops the handler's future
/// when the client cancels or times out, but a task already running on a blocking thread can't be cancelled from outside).
struct CancelWhenDropped(Arc<AtomicBool>);

impl Drop for CancelWhenDropped {
    fn drop(&mut self) {
        self.0.store(true, Ordering::Relaxed);
    }
}

#[tonic::async_trait]
impl EmbeddingService for EmbeddingServiceImpl {
    async fn describe(&self, request: Request<DescribeRequest>) -> Result<Response<ModelDescription>, Status> {
        self.authorize(&request)?;
        let spec = self.spec();
        Ok(Response::new(ModelDescription { model_id: spec.id.to_string(), dimensions: spec.dimensions }))
    }

    async fn embed(&self, request: Request<EmbedRequest>) -> Result<Response<EmbedResponse>, Status> {
        self.authorize(&request)?;
        let request = request.into_inner();
        let spec = self.spec();
        if !request.model_id.is_empty() && request.model_id != spec.id {
            return Err(Status::failed_precondition("model_mismatch"));
        }
        if request.texts.is_empty() {
            return Ok(Response::new(EmbedResponse { vectors: vec![], model_id: spec.id.to_string() }));
        }
        if request.texts.len() > MAX_TEXTS_PER_REQUEST || request.texts.iter().any(|t| t.len() > MAX_TEXT_BYTES) {
            return Err(Status::invalid_argument("request_too_large"));
        }
        let _slot = self
            .waiting
            .clone()
            .try_acquire_owned()
            .map_err(|_| Status::resource_exhausted("embedding_queue_full"))?;
        let purpose = Purpose::try_from(request.purpose).unwrap_or(Purpose::Document);
        // Wait for the model in line. If the client gives up while we wait (or while we run) this future is dropped:
        // leaving the line costs nothing, and `cancelled` tells a run already under way to stop at its next text.
        let cancelled = Arc::new(AtomicBool::new(false));
        let _cancel_when_dropped = CancelWhenDropped(cancelled.clone());
        let mut embedder = self.embedder.clone().lock_owned().await;
        let vectors = tokio::task::spawn_blocking(move || -> anyhow::Result<Vec<Vec<f32>>> {
            let mut vectors = Vec::with_capacity(request.texts.len());
            for text in &request.texts {
                if cancelled.load(Ordering::Relaxed) {
                    anyhow::bail!("the client stopped waiting");
                }
                vectors.push(match purpose {
                    Purpose::Document => embedder
                        .embed_documents(std::slice::from_ref(text))?
                        .pop()
                        .ok_or_else(|| anyhow::anyhow!("the model returned no vector"))?,
                    Purpose::Query => embedder.embed_query(text)?,
                });
            }
            Ok(vectors)
        })
        .await
        .map_err(|_| Status::internal("embedding_task_failed"))?
        .map_err(|e| {
            log::error!("Embedding failed: {:?}", crate::logic::log_redaction::safe_error(&e));
            Status::internal("embedding_failed")
        })?;
        Ok(Response::new(EmbedResponse {
            vectors: vectors.into_iter().map(|values| Vector { values }).collect(),
            model_id: spec.id.to_string(),
        }))
    }
}

/// Serves `embedder` at `addr` until the process stops.
pub async fn serve(addr: std::net::SocketAddr, embedder: BoxedEmbedder, secret: Option<String>) -> anyhow::Result<()> {
    let service = EmbeddingServiceImpl::new(embedder, secret);
    log::info!("Embedding service listening on {} (model {}).", addr, service.spec().id);
    Server::builder().add_service(EmbeddingServiceServer::new(service)).serve(addr).await?;
    Ok(())
}
