# Semantic search deployment

Semantic search (embeddings + hybrid reranking; see the PR that added it) works with **no extra infrastructure**: each
Rellm server loads the embedding model itself, the `generate_embeddings` job fills the embedding tables, and searches
scan candidate vectors out of Postgres. That is the default and what self-hosted installs use.

On a cluster with several namespaces (and, say, two servers per namespace) that duplicates the model's RAM in every
server and job. Two **opt-in** services remove that duplication:

| service | scope | what it holds | RAM |
|---|---|---|---|
| `rellm-central-embedding` (`embedding_service`) | one per **cluster** | ONE embedding model, shared by every namespace | the model (~1GB for the default `multilingual-e5-small`) |
| `rellm-vector` (`vector_search_service`) | one per **namespace** | a USearch index of that namespace's embeddings, shared by its servers | ~400 bytes per row |

Both are single-pod, cluster-internal (ClusterIP), authenticated with a shared secret, and **optional at runtime**: if a
service is down or still starting, searches keep working: if the vector service can't answer they use the Postgres scan
(no extra service, no pgvector), and if the model service is also unavailable they use plain full-text search.

## Enabling

1. **Once per cluster** — the model service (`../central_storage/k8s/k8s-central-embedding-service.yaml`). Create its
   secret (command in that file), then `kubectl -n rellm-storage apply -f` it.
2. **Per namespace** — add two keys to the namespace's `rellm-data-credentials` Secret: `embedding-service-secret` (the
   same value as the model service's) and `vector-service-secret` (any new random value). Then
   `kubectl apply -f vector_search_service.yaml`.
3. **Point the namespace's servers and jobs at them.** Add these environment variables to the `rellm` server
   Deployment(s) and to `rellm-jobs`:

   ```yaml
   - name: RELLM_EMBEDDING_SERVICE_URL
     value: http://rellm-central-embedding.rellm-storage:8090
   - name: RELLM_EMBEDDING_SERVICE_SECRET
     valueFrom:
       secretKeyRef: { name: rellm-data-credentials, key: embedding-service-secret }
   ```

   and, on the **servers only** (the jobs don't search):

   ```yaml
   - name: RELLM_VECTOR_SERVICE_URL
     value: http://rellm-vector:8091
   - name: RELLM_VECTOR_SERVICE_SECRET
     valueFrom:
       secretKeyRef: { name: rellm-data-credentials, key: vector-service-secret }
   ```

With the model service configured the model is **chosen by the cluster** (Settings → Search shows it read-only), the
`generate_embeddings` job loads no model and takes no per-namespace lock, and servers don't load one either. Changing the
cluster's model (`RELLM_EMBEDDING_SERVICE_MODEL`) re-embeds every namespace's content in the background.

## Trade-offs

- Private post/profile text is sent to the shared model service. It stores and logs nothing, but only point namespaces
  you operate at it.
- One pod per service: if the vector service restarts, searches use the Postgres scan until it is back (its client skips
  it for ~15 seconds after a failure so the fallback is immediate; the vector service also
  rebuilds its index from Postgres, a few seconds per 100k rows).
- The vector service must be built with `--features vector-service` (the server Docker image is).
