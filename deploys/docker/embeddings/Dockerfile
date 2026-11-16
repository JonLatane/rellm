FROM debian:testing-slim

# The rellm-embeddings image: the ONLY place an embedding model is ever loaded, and the per-namespace vector index.
# The server and jobs images contain no model, ONNX Runtime or USearch code at all -- they reach these services over
# gRPC (RELLM_EMBEDDING_SERVICE_URL / RELLM_VECTOR_SERVICE_URL). See deploys/k8s/SEMANTIC_SEARCH.md.
#
#   /opt/embedding_service      one per cluster: hosts ONE model, embeds text for every namespace's servers and jobs
#   /opt/vector_search_service  one per namespace: a USearch (HNSW) index over that namespace's embeddings (optional)
COPY embeddings-binaries/embedding_service /opt/embedding_service
COPY embeddings-binaries/vector_search_service /opt/vector_search_service

# libstdc++6: ONNX Runtime and USearch are C++. libpq5: the vector service reads embeddings from Postgres.
# ca-certificates: the embedding service downloads its model (once) into RELLM_EMBEDDING_CACHE_DIR.
RUN apt-get update && apt-get -y install libpq5 libstdc++6 libgomp1 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

ENV RELLM_EMBEDDING_CACHE_DIR=/models
EXPOSE 8090 8091

# Default to the model service; the vector service Deployment overrides `command`.
ENTRYPOINT ["/opt/embedding_service"]
