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
/// (`INVALID_ARGUMENT`) rather than allowed to tie up the one model.
pub const MAX_TEXTS_PER_REQUEST: usize = 64;
pub const MAX_TEXT_BYTES: usize = 32 * 1024;
/// Requests allowed to wait for the model at once (it embeds one batch at a time). More are refused with
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
        reply_rx
            .recv_timeout(CALL_TIMEOUT + Duration::from_secs(5))
            .map_err(|_| anyhow::anyhow!("the model service didn't answer in time"))?
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
        for batch in texts.chunks(MAX_TEXTS_PER_REQUEST) {
            vectors.extend(self.call(Purpose::Document, batch.to_vec())?);
        }
        Ok(vectors)
    }
    fn embed_query(&mut self, text: &str) -> anyhow::Result<Vec<f32>> {
        self.call(Purpose::Query, vec![text.to_string()])?
            .pop()
            .ok_or_else(|| anyhow::anyhow!("the model service returned no vector"))
    }
}

// The model the cluster's service runs, once known. `None` until a probe succeeds (service not configured,
// unreachable, or not yet asked).
static CLUSTER_MODEL: Mutex<Option<&'static ModelSpec>> = Mutex::new(None);
static LAST_PROBE: Mutex<Option<Instant>> = Mutex::new(None);
const PROBE_EVERY: Duration = Duration::from_secs(30);

/// The model the cluster-shared service runs, when one is configured and has answered. Never blocks: if the answer
/// isn't known yet it starts a background probe (at most one every 30 seconds) and returns `None` for now -- so a
/// service that is down costs a request nothing, and searches are full-text until it has been reached once. Once
/// known, the answer is remembered for the life of the process.
pub fn cluster_model() -> Option<&'static ModelSpec> {
    let (url, secret) = embedding_service_config()?;
    if let Some(spec) = *CLUSTER_MODEL.lock().unwrap() {
        return Some(spec);
    }
    {
        let mut last = LAST_PROBE.lock().unwrap();
        if last.map_or(false, |at| at.elapsed() < PROBE_EVERY) {
            return None;
        }
        *last = Some(Instant::now());
    }
    std::thread::Builder::new()
        .name("embedding-service-probe".to_string())
        .spawn(move || {
            probe(&url, secret);
        })
        .ok();
    None
}

/// Like `cluster_model` but waits for the answer (a few seconds at most) and asks every time it isn't known: for
/// callers that can't proceed without it (the vector service at startup, tests).
pub fn cluster_model_blocking() -> Option<&'static ModelSpec> {
    let (url, secret) = embedding_service_config()?;
    if let Some(spec) = *CLUSTER_MODEL.lock().unwrap() {
        return Some(spec);
    }
    probe(&url, secret)
}

fn probe(url: &str, secret: Option<String>) -> Option<&'static ModelSpec> {
    match RemoteEmbedder::connect(url, secret) {
        Ok(embedder) => {
            *CLUSTER_MODEL.lock().unwrap() = Some(embedder.spec);
            Some(embedder.spec)
        }
        Err(e) => {
            log::warn!("The embedding model service isn't available: {:?}", e);
            None
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Service side
// ---------------------------------------------------------------------------------------------

pub struct EmbeddingServiceImpl {
    embedder: Arc<Mutex<BoxedEmbedder>>,
    secret: Option<String>,
    waiting: Arc<tokio::sync::Semaphore>,
}

impl EmbeddingServiceImpl {
    /// `secret: None` disables authentication (only for a service reachable by nothing but trusted callers).
    pub fn new(embedder: BoxedEmbedder, secret: Option<String>) -> Self {
        EmbeddingServiceImpl {
            embedder: Arc::new(Mutex::new(embedder)),
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
        self.embedder.lock().unwrap().spec()
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
        let embedder = self.embedder.clone();
        let vectors = tokio::task::spawn_blocking(move || {
            let mut embedder = embedder.lock().unwrap();
            match purpose {
                Purpose::Document => embedder.embed_documents(&request.texts),
                Purpose::Query => request.texts.iter().map(|t| embedder.embed_query(t)).collect(),
            }
        })
        .await
        .map_err(|_| Status::internal("embedding_task_failed"))?
        .map_err(|e| {
            log::error!("Embedding failed: {:?}", e);
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
