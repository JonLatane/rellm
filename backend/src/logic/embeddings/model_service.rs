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
use std::collections::{hash_map::Entry, HashMap, VecDeque};
use std::sync::mpsc;
use std::sync::{Arc, Condvar, Mutex};
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

/// Where a text's vector goes. The error is a plain message so that one failed run can be sent to everyone waiting on it.
type Reply = tokio::sync::oneshot::Sender<Result<Vec<f32>, String>>;

/// A document text for the model. The reply channel is also how the worker learns the request is gone: when the client
/// gives up, tonic drops the handler's future, the receiver goes with it, and the worker skips the job.
struct DocumentJob {
    /// The request it belongs to (see `RequestGuard`).
    request: u64,
    text: String,
    reply: Reply,
}

/// What the model is waiting to do: search queries first (somebody is waiting on a page), then documents in arrival order.
#[derive(Default)]
struct Queues {
    /// Distinct query texts waiting for the model, oldest first.
    queries: VecDeque<String>,
    /// Everyone waiting on each distinct query text, from when it is queued until its vector is ready: identical queries
    /// (several Rellm servers answering the same search) share one run of the model.
    query_waiters: HashMap<String, Vec<Reply>>,
    documents: VecDeque<DocumentJob>,
    closed: bool,
}

/// The vectors of recent search queries, so a query asked again (by another server, or the same search repeated) is
/// answered without the model. Only queries: documents are almost never repeated, and each would sit in memory. Bounded
/// both ways: a fixed number of entries, and only short texts (a search is a few words; a text of kilobytes is not
/// worth keeping). Oldest-first eviction. Keyed by the model too, so it can't hand out a vector from another model.
struct QueryCache {
    model: &'static str,
    vectors: HashMap<String, Vec<f32>>,
    order: VecDeque<String>,
}

/// Entries kept: about 2048 x (a short text + a 1.5KB vector), a few MB.
const QUERY_CACHE_ENTRIES: usize = 2048;
/// Longest query text worth caching.
const QUERY_CACHE_MAX_TEXT_BYTES: usize = 512;

impl QueryCache {
    fn get(&self, model: &'static str, text: &str) -> Option<Vec<f32>> {
        if self.model != model {
            return None;
        }
        self.vectors.get(text).cloned()
    }

    fn put(&mut self, model: &'static str, text: &str, vector: Vec<f32>) {
        if text.len() > QUERY_CACHE_MAX_TEXT_BYTES {
            return;
        }
        if self.model != model {
            self.model = model;
            self.vectors.clear();
            self.order.clear();
        }
        if self.vectors.contains_key(text) {
            return;
        }
        if self.order.len() >= QUERY_CACHE_ENTRIES {
            if let Some(oldest) = self.order.pop_front() {
                self.vectors.remove(&oldest);
            }
        }
        self.order.push_back(text.to_string());
        self.vectors.insert(text.to_string(), vector);
    }
}

/// What one worker thread takes from the queues. With a model of its own for queries (`serve_with_query_model`) the two
/// kinds of work run on different threads; sharing one model, a single thread does both, queries first.
#[derive(Clone, Copy)]
struct Role {
    queries: bool,
    documents: bool,
}

impl Role {
    const BOTH: Role = Role { queries: true, documents: true };
    const QUERIES: Role = Role { queries: true, documents: false };
    const DOCUMENTS: Role = Role { queries: false, documents: true };
}

/// The model's next piece of work.
enum Next {
    Query(String),
    Document(DocumentJob),
}

/// The model's work queue and the thread that works through it.
struct Scheduler {
    queues: Mutex<Queues>,
    /// Always locked after `queues` when both are held.
    cache: Mutex<QueryCache>,
    /// Woken with `notify_all`: with two workers, a single notification could reach the one that has nothing to take.
    wake: Condvar,
    next_request: std::sync::atomic::AtomicU64,
}

impl Scheduler {
    /// The vector for a search query: straight from the cache, or by joining the run of the model that is already queued
    /// (or under way) for the same text, or by starting one.
    fn submit_query(&self, model: &'static str, text: String) -> tokio::sync::oneshot::Receiver<Result<Vec<f32>, String>> {
        let (reply, receiver) = tokio::sync::oneshot::channel();
        let mut guard = self.queues.lock().unwrap();
        // Checked under the queues lock, like the worker's insert, so a run can't finish between the check and the join.
        if let Some(vector) = self.cache.lock().unwrap().get(model, &text) {
            let _ = reply.send(Ok(vector));
            return receiver;
        }
        let queues = &mut *guard;
        match queues.query_waiters.entry(text) {
            Entry::Occupied(mut joined) => joined.get_mut().push(reply),
            Entry::Vacant(first) => {
                queues.queries.push_back(first.key().clone());
                first.insert(vec![reply]);
                self.wake.notify_all();
            }
        }
        receiver
    }

    fn submit_document(&self, request: u64, text: String) -> tokio::sync::oneshot::Receiver<Result<Vec<f32>, String>> {
        let (reply, receiver) = tokio::sync::oneshot::channel();
        self.queues.lock().unwrap().documents.push_back(DocumentJob { request, text, reply });
        self.wake.notify_all();
        receiver
    }

    /// Starts tracking one request's jobs (see `RequestGuard`).
    fn begin(self: &Arc<Self>) -> RequestGuard {
        RequestGuard {
            scheduler: self.clone(),
            id: self.next_request.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
            queries: Vec::new(),
            finished: false,
        }
    }

    /// A request ended before its work was done (its client gave up): take its jobs out of the queues now, instead of
    /// leaving them for the worker to find -- with queries always going first, that could be a long time, and meanwhile
    /// repeated timeouts and retries would keep adding texts that nobody is waiting for. A query other requests are also
    /// waiting on stays queued for them.
    fn cancel(&self, request: u64, query_texts: &[String]) {
        let mut guard = self.queues.lock().unwrap();
        let queues = &mut *guard;
        queues.documents.retain(|job| job.request != request);
        for text in query_texts {
            let Some(waiters) = queues.query_waiters.get_mut(text) else { continue };
            waiters.retain(|reply| !reply.is_closed());
            if waiters.is_empty() {
                queues.query_waiters.remove(text);
                queues.queries.retain(|queued| queued != text);
            }
        }
    }

    /// The next job for `role`, blocking until there is one; `None` once the service is gone. Work nobody is waiting for any
    /// more (every client that asked has given up) is dropped here.
    fn next(&self, role: Role) -> Option<Next> {
        let mut guard = self.queues.lock().unwrap();
        loop {
            let queues = &mut *guard;
            if let Some(text) = role.queries.then(|| queues.queries.pop_front()).flatten() {
                let abandoned = queues.query_waiters.get(&text).map_or(true, |waiters| waiters.iter().all(|w| w.is_closed()));
                if abandoned {
                    queues.query_waiters.remove(&text);
                    continue;
                }
                return Some(Next::Query(text));
            }
            if let Some(job) = role.documents.then(|| queues.documents.pop_front()).flatten() {
                if job.reply.is_closed() {
                    continue;
                }
                return Some(Next::Document(job));
            }
            if queues.closed {
                return None;
            }
            guard = self.wake.wait(guard).unwrap();
        }
    }

    /// A query's run is over: remember a good vector, and answer everyone who was waiting on it.
    fn finish_query(&self, model: &'static str, text: String, result: Result<Vec<f32>, String>) {
        let mut queues = self.queues.lock().unwrap();
        if let Ok(vector) = &result {
            self.cache.lock().unwrap().put(model, &text, vector.clone());
        }
        for reply in queues.query_waiters.remove(&text).unwrap_or_default() {
            let _ = reply.send(result.clone());
        }
    }
}

/// One request's jobs. Dropped before `finish()` (the handler's future was dropped because the client gave up, or the
/// request failed), it removes whatever of the request is still queued. Declare it BEFORE the receivers of its jobs so that
/// they are dropped first: a job whose receiver is gone is how `cancel` tells this request's waiters from other requests'.
struct RequestGuard {
    scheduler: Arc<Scheduler>,
    id: u64,
    queries: Vec<String>,
    finished: bool,
}

impl RequestGuard {
    fn query(&mut self, model: &'static str, text: String) -> tokio::sync::oneshot::Receiver<Result<Vec<f32>, String>> {
        self.queries.push(text.clone());
        self.scheduler.submit_query(model, text)
    }

    fn document(&mut self, text: String) -> tokio::sync::oneshot::Receiver<Result<Vec<f32>, String>> {
        self.scheduler.submit_document(self.id, text)
    }

    /// Everything the request asked for has been answered: nothing to clean up.
    fn finish(mut self) {
        self.finished = true;
    }
}

impl Drop for RequestGuard {
    fn drop(&mut self) {
        if !self.finished {
            self.scheduler.cancel(self.id, &self.queries);
        }
    }
}

pub struct EmbeddingServiceImpl {
    /// Locked by the worker for one text at a time, so `spec()` can read the live model between texts.
    embedder: Arc<Mutex<BoxedEmbedder>>,
    scheduler: Arc<Scheduler>,
    /// The last model read from the embedder. Reading it must never wait for a text to finish being embedded, so while one
    /// runs this answers from the cache; a real service never changes model, so the cache is never stale.
    spec: Mutex<&'static ModelSpec>,
    secret: Option<String>,
    waiting: Arc<tokio::sync::Semaphore>,
}

impl Drop for EmbeddingServiceImpl {
    fn drop(&mut self) {
        self.scheduler.queues.lock().unwrap().closed = true;
        self.scheduler.wake.notify_all();
    }
}

impl EmbeddingServiceImpl {
    /// `secret: None` disables authentication (only for a service reachable by nothing but trusted callers).
    ///
    /// One worker thread runs the model, one text at a time, always taking a waiting search query before any document: with
    /// the cluster backfilling, a search used to wait behind every document call in the line (15-19s measured), and now waits
    /// for at most the text being embedded. Documents are served first come, first served, and a request that is abandoned
    /// (its client timed out) costs nothing: its jobs are skipped. See `with_query_model` to not wait even for that text.
    pub fn new(embedder: BoxedEmbedder, secret: Option<String>) -> Self {
        Self::build(embedder, None, secret)
    }

    /// `new`, with a second copy of the model (`queries`, the same model as `documents`) that answers search queries on a
    /// thread of its own: a query then never waits for the document being embedded (up to ~2.3s for a long one), only for
    /// other queries. The cost is that model's working memory, and the two threads share the CPU while both are busy.
    pub fn with_query_model(documents: BoxedEmbedder, queries: BoxedEmbedder, secret: Option<String>) -> Self {
        assert_eq!(documents.spec().id, queries.spec().id, "the query model must be the same model as the document one");
        Self::build(documents, Some(queries), secret)
    }

    fn build(embedder: BoxedEmbedder, queries: Option<BoxedEmbedder>, secret: Option<String>) -> Self {
        let spec = embedder.spec();
        let embedder = Arc::new(Mutex::new(embedder));
        let scheduler = Arc::new(Scheduler {
            queues: Mutex::new(Queues::default()),
            cache: Mutex::new(QueryCache { model: spec.id, vectors: HashMap::new(), order: VecDeque::new() }),
            wake: Condvar::new(),
            next_request: std::sync::atomic::AtomicU64::new(0),
        });
        match queries {
            None => Self::spawn_worker("embedding-worker", &scheduler, &embedder, Role::BOTH),
            Some(queries) => {
                Self::spawn_worker("embedding-worker", &scheduler, &embedder, Role::DOCUMENTS);
                Self::spawn_worker("embedding-query-worker", &scheduler, &Arc::new(Mutex::new(queries)), Role::QUERIES);
            }
        }
        EmbeddingServiceImpl {
            spec: Mutex::new(spec),
            embedder,
            scheduler,
            secret,
            waiting: Arc::new(tokio::sync::Semaphore::new(MAX_WAITING)),
        }
    }

    fn spawn_worker(name: &str, scheduler: &Arc<Scheduler>, embedder: &Arc<Mutex<BoxedEmbedder>>, role: Role) {
        let (embedder, scheduler) = (embedder.clone(), scheduler.clone());
        std::thread::Builder::new()
            .name(name.to_string())
            .spawn(move || {
                let failed = |e: anyhow::Error| {
                    log::error!("Embedding failed: {:?}", crate::logic::log_redaction::safe_error(&e));
                    "embedding_failed".to_string()
                };
                while let Some(next) = scheduler.next(role) {
                    match next {
                        Next::Document(job) => {
                            let result = {
                                let mut embedder = embedder.lock().unwrap();
                                embedder
                                    .embed_documents(std::slice::from_ref(&job.text))
                                    .and_then(|mut vectors| vectors.pop().ok_or_else(|| anyhow::anyhow!("the model returned no vector")))
                            };
                            let _ = job.reply.send(result.map_err(failed));
                        }
                        Next::Query(text) => {
                            let (model, result) = {
                                let mut embedder = embedder.lock().unwrap();
                                (embedder.spec().id, embedder.embed_query(&text))
                            };
                            scheduler.finish_query(model, text, result.map_err(failed));
                        }
                    }
                }
            })
            .expect("starting an embedding worker thread");
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
        // One job per text. If the client gives up, this future is dropped and `replies` with it, which tells the worker to
        // skip whatever of the request hasn't run yet.
        let mut guard = self.scheduler.begin(); // declared before `replies`: see `RequestGuard`
        let replies: Vec<_> = request
            .texts
            .into_iter()
            .map(|text| match purpose {
                Purpose::Query => guard.query(spec.id, text),
                Purpose::Document => guard.document(text),
            })
            .collect();
        let mut vectors = Vec::with_capacity(replies.len());
        for receiver in replies {
            let vector = receiver
                .await
                .map_err(|_| Status::internal("embedding_task_failed"))?
                .map_err(|message| Status::internal(message))?;
            vectors.push(vector);
        }
        guard.finish();
        Ok(Response::new(EmbedResponse {
            vectors: vectors.into_iter().map(|values| Vector { values }).collect(),
            model_id: spec.id.to_string(),
        }))
    }
}

/// Serves `embedder` at `addr` until the process stops.
pub async fn serve(addr: std::net::SocketAddr, embedder: BoxedEmbedder, secret: Option<String>) -> anyhow::Result<()> {
    serve_service(addr, EmbeddingServiceImpl::new(embedder, secret)).await
}

/// `serve`, with `queries` (a second copy of the same model) answering search queries on its own thread: see
/// `EmbeddingServiceImpl::with_query_model`.
pub async fn serve_with_query_model(addr: std::net::SocketAddr, documents: BoxedEmbedder, queries: BoxedEmbedder, secret: Option<String>) -> anyhow::Result<()> {
    serve_service(addr, EmbeddingServiceImpl::with_query_model(documents, queries, secret)).await
}

async fn serve_service(addr: std::net::SocketAddr, service: EmbeddingServiceImpl) -> anyhow::Result<()> {
    log::info!("Embedding service listening on {} (model {}).", addr, service.spec().id);
    Server::builder().add_service(EmbeddingServiceServer::new(service)).serve(addr).await?;
    Ok(())
}

#[cfg(test)]
mod scheduler_tests {
    use super::*;

    fn scheduler() -> Arc<Scheduler> {
        Arc::new(Scheduler {
            queues: Mutex::new(Queues::default()),
            cache: Mutex::new(QueryCache { model: "m", vectors: HashMap::new(), order: VecDeque::new() }),
            wake: Condvar::new(),
            next_request: std::sync::atomic::AtomicU64::new(0),
        })
    }

    fn queued(scheduler: &Scheduler) -> (usize, usize, usize) {
        let queues = scheduler.queues.lock().unwrap();
        (queues.documents.len(), queues.queries.len(), queues.query_waiters.len())
    }

    #[test]
    fn a_request_that_is_dropped_takes_its_queued_jobs_with_it() {
        let scheduler = scheduler();
        let mut gone = scheduler.begin();
        let mut stays = scheduler.begin();
        let replies: Vec<_> = (0..5).map(|i| gone.document(format!("gone {i}"))).collect();
        let kept: Vec<_> = (0..2).map(|i| stays.document(format!("stays {i}"))).collect();
        let query = gone.query("m", "a query".to_string());
        assert_eq!(queued(&scheduler), (7, 1, 1));

        // The client gives up: the handler's future is dropped (receivers first, then the guard, as in the handler).
        drop(replies);
        drop(query);
        drop(gone);
        assert_eq!(queued(&scheduler), (2, 0, 0), "only the request that is still waiting keeps its jobs");
        drop(kept);
        stays.finish();
        assert_eq!(queued(&scheduler), (2, 0, 0), "a finished request leaves nothing to clean up");
    }

    #[test]
    fn a_query_other_requests_still_wait_on_stays_queued() {
        let scheduler = scheduler();
        let (mut first, mut second) = (scheduler.begin(), scheduler.begin());
        let first_reply = first.query("m", "xyz".to_string());
        let second_reply = second.query("m", "xyz".to_string());
        assert_eq!(queued(&scheduler), (0, 1, 1), "identical queries share one queued run");

        drop(first_reply);
        drop(first);
        assert_eq!(queued(&scheduler), (0, 1, 1), "the second request is still waiting on it");
        drop(second_reply);
        drop(second);
        assert_eq!(queued(&scheduler), (0, 0, 0));
    }
}
