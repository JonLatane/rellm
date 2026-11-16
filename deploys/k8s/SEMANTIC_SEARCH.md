# Semantic search deployment

Semantic search (embeddings + hybrid reranking) needs the **`rellm_embeddings` image**
(`docker.io/jonlatane/rellm_embeddings`, built from `deploys/docker/embeddings/Dockerfile`). It is the **only** place an
embedding model is ever loaded: the `rellm` server and `rellm-jobs` images contain no model, ONNX Runtime or USearch code at
all, and have no option or default that would load one. With no embedding service deployed (or reachable), Rellm simply
runs plain Postgres full-text search, and Settings → Search says so.

The image holds two binaries, run as two services:

| service | binary | scope | what it holds | RAM |
|---|---|---|---|---|
| `rellm-central-embedding` | `/opt/embedding_service` | one per **cluster** — **required** for semantic search | ONE embedding model, shared by every namespace | the model (~1GB for the default `multilingual-e5-small`) |
| `rellm-vector` | `/opt/vector_search_service` | one per **namespace** — **optional** | a USearch index of that namespace's embeddings, shared by its servers | ~400 bytes per row |

Both are single-pod, cluster-internal (ClusterIP) and authenticated with a shared secret. The model service is needed for
every embedding (indexing in `generate_embeddings` and each search query). The vector service only speeds up searches over
more candidates than the default Postgres scan covers (full-text matches plus the 10k newest visible rows); if it is down or
still building, searches silently use that scan (no pgvector), and if the model service is unavailable too they use plain
full-text search.

## Enabling

1. **Once per cluster** — the model service (`../central_storage/k8s/k8s-central-embedding-service.yaml`). Create its
   secret (command in that file), then `kubectl -n rellm-storage apply -f` it.
2. **Per namespace** — add the key `embedding-service-secret` (the same value as the model service's) to the namespace's
   `rellm-data-credentials` Secret, and point the `rellm` server Deployment(s) and `rellm-jobs` at the service:

   ```yaml
   - name: RELLM_EMBEDDING_SERVICE_URL
     value: http://rellm-central-embedding.rellm-storage:8090
   - name: RELLM_EMBEDDING_SERVICE_SECRET
     valueFrom:
       secretKeyRef: { name: rellm-data-credentials, key: embedding-service-secret }
   ```

3. **Optional, per namespace** — the vector service: add `vector-service-secret` (any new random value) to the same Secret,
   `kubectl apply -f vector_search_service.yaml`, and on the **servers only** (the jobs don't search) set:

   ```yaml
   - name: RELLM_VECTOR_SERVICE_URL
     value: http://rellm-vector:8091
   - name: RELLM_VECTOR_SERVICE_SECRET
     valueFrom:
       secretKeyRef: { name: rellm-data-credentials, key: vector-service-secret }
   ```

The model is **chosen by the cluster** (Settings → Search shows it read-only); servers and jobs never choose or load one. The
`generate_embeddings` job takes no lock: it only calls the service. Changing the cluster's model
(`RELLM_EMBEDDING_SERVICE_MODEL`) re-embeds every namespace's content in the background.

Image tags: CI builds and pushes `rellm_embeddings:<version>` (and `<version>-<sha>`) but, like all deploys, never applies
manifests. Roll a new image with `kubectl set image` or by editing the tag in the two manifests and applying them.

## Running locally

```bash
make run_embedding_service     # the model service on :8090 (downloads the model on first run)
make run_vector_service        # optional: the vector service on :8091
make run_tmux_with_embeddings  # backend + Elm + both services side by side (see the root Makefile)
```

with `RELLM_EMBEDDING_SERVICE_URL=http://localhost:8090` (and `RELLM_EMBEDDING_SERVICE_SECRET`) in `backend/.env`
(see `backend/.env-example`).

## Changing the cluster's model

The model service hosts one model, chosen by `RELLM_EMBEDDING_SERVICE_MODEL`. To change it, restart that Deployment with a
different value. Nothing else needs to be touched or restarted; each part follows the change on its own:

- **Servers** re-check which model the service runs every minute, and immediately after the service refuses a call for a
  model it no longer runs. Until they notice, searches fall back (full-text, or the Postgres scan) rather than compare
  vectors from two different models; once they do, they switch their query embedder to the new model.
- **`generate_embeddings`** picks the new model up on its next run (it starts a fresh process each time) and re-embeds every
  row the old model made, newest first, over several runs. A run that straddles the switch is refused by the service,
  logs the error, and carries on next time; it can never store a vector from the wrong model.
- **`vector_search_service`** (unless pinned with `RELLM_VECTOR_SERVICE_MODEL`) checks each cycle, drops its indexes
  (freeing the memory) and rebuilds them from the rows the new model has embedded so far. Until a kind is rebuilt its
  searches say "not ready" and servers scan Postgres instead.

While the backfill runs, semantic matches come only from rows the new model has embedded (full-text search is
unaffected), so quality dips and then recovers as the job catches up. A different vector size (e.g. 384 to 768
dimensions) needs no migration: vectors are stored per row with the model that made them.

## Trade-offs

- Private post/profile text is sent to the shared model service. It stores and logs nothing, but only point namespaces
  you operate at it.
- One pod per service: if the vector service restarts, searches use the Postgres scan until it is back (its client skips
  it for ~15 seconds after a failure so the fallback is immediate; the vector service also
  rebuilds its index from Postgres, a few seconds per 100k rows).
- Self-hosters on the Homebrew/Linux packages don't get these services (they are not in those packages): run the
  `rellm_embeddings` image alongside, or search stays full-text.
