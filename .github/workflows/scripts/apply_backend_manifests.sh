#!/usr/bin/env bash
# Rolls a namespace's Rellm deployments to a new image tag by APPLYING the checked-in manifests at
# that tag (a single rollout: manifest changes and the new image land together).
#
# Usage: apply_backend_manifests.sh <server|preview|embedding|vector> <namespace> <tag> <dockerhub-user>
#   server    -> deploys/k8s/server_internal_central_data.yaml   (deployment/rellm, deployment/rellm-jobs)
#   preview   -> deploys/k8s/preview_generator_central_data.yaml (deployment/rellm-preview-generator)
#   embedding -> deploys/central_storage/k8s/k8s-central-embedding-service.yaml (the cluster's
#                deployment/rellm-central-embedding, in the storage namespace)
#   vector    -> deploys/k8s/vector_search_service_central_data.yaml (a namespace's optional deployment/rellm-vector)
#
# This is what CI runs. It replaced set_backend_images.sh (`kubectl set image` only), which stays as
# the manual one-off. Safety rails, since this touches production:
#   * `replicas` is NEVER written. It's stripped from the applied manifest and the apply is
#     server-side, so the live replica count is left exactly as it is: a site parked at 0 for a
#     storage transition stays parked (it still gets the new manifest and image), and an operator's
#     `stop_backend`/`kubectl scale` can't be undone by a CI deploy, even one racing with it.
#     (A check-then-apply would have a race; not writing the field has none.) Consequence: changing a
#     replica count in a manifest is NOT rolled out by CI -- scale by hand.
#   * Only manifests for namespaces on CENTRAL storage are applied (every CI namespace is). A namespace
#     with its own Postgres/object storage uses other manifests -- roll those out by hand
#     (deploys/README.md, "Rolling out manifest changes").
#   * It only updates what already exists -- the Deployments must have been provisioned by the deploys/
#     Makefile (server and preview fail if they're missing; embedding and vector are optional and skip).
#   * Credentials Secrets and PVC contents are never in these manifests; nothing is deleted (no
#     `--prune`), so a resource removed from a manifest has to be removed by hand.
#   * The image in each applied manifest is rewritten to <dockerhub-user>/<image>:<tag>; nothing else
#     in the manifest is edited besides the ${NAMESPACE}/${STORAGE_NAMESPACE} substitution that
#     deploys/Makefile also does.
#   * Server-side apply runs as field manager `rellm-ci` with --force-conflicts: it takes over the
#     fields it sets (image, env, ...) from earlier `kubectl apply`/`set image` managers, and leaves
#     the ones it doesn't (replicas) with whoever set them.
set -euo pipefail

USAGE="Usage: $0 <server|preview|embedding|vector> <namespace> <tag> <dockerhub-user>"
COMPONENT="${1:?$USAGE}"
NAMESPACE="${2:?$USAGE}"
TAG="${3:?$USAGE}"
DOCKERHUB_USER="${4:?$USAGE}"
STORAGE_NAMESPACE="${STORAGE_NAMESPACE:-rellm-storage}"

printf '%s' "$NAMESPACE" | grep -Eq '^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$' || { echo "Invalid namespace '$NAMESPACE'" >&2; exit 1; }
printf '%s' "$STORAGE_NAMESPACE" | grep -Eq '^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$' || { echo "Invalid storage namespace '$STORAGE_NAMESPACE'" >&2; exit 1; }
printf '%s' "$TAG" | grep -Eq '^[A-Za-z0-9._-]{1,128}$' || { echo "Invalid image tag '$TAG'" >&2; exit 1; }
printf '%s' "$DOCKERHUB_USER" | grep -Eq '^[A-Za-z0-9._-]+$' || { echo "Invalid DockerHub user" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYS="$HERE/../../../deploys"

OPTIONAL=""
case "$COMPONENT" in
  server)    FILE="$DEPLOYS/k8s/server_internal_central_data.yaml";                    IMAGE_NAME=rellm;                   DEPLOYMENTS="rellm rellm-jobs" ;;
  preview)   FILE="$DEPLOYS/k8s/preview_generator_central_data.yaml";                  IMAGE_NAME=rellm_preview_generator; DEPLOYMENTS="rellm-preview-generator" ;;
  embedding) FILE="$DEPLOYS/central_storage/k8s/k8s-central-embedding-service.yaml";   IMAGE_NAME=rellm_embeddings;         DEPLOYMENTS="rellm-central-embedding"; OPTIONAL=1 ;;
  vector)    FILE="$DEPLOYS/k8s/vector_search_service_central_data.yaml";              IMAGE_NAME=rellm_embeddings;         DEPLOYMENTS="rellm-vector"; OPTIONAL=1 ;;
  *) echo "Unknown component '$COMPONENT' (expected server, preview, embedding or vector)" >&2; exit 1 ;;
esac
[ -f "$FILE" ] || { echo "ERROR: manifest $FILE not found" >&2; exit 1; }

# Check everything first so nothing is applied if a required Deployment is missing.
PRESENT=0
for d in $DEPLOYMENTS; do
  if [ -z "$(kubectl get deployment "$d" -n "$NAMESPACE" --ignore-not-found -o 'jsonpath={.metadata.name}')" ]; then
    if [ -n "$OPTIONAL" ]; then echo "$NAMESPACE/$d: not deployed (optional) -- skipping"; continue; fi
    echo "ERROR: deployment/$d doesn't exist in $NAMESPACE -- provision the namespace first (see deploys/README.md); CI only updates what exists." >&2; exit 1
  fi
  PRESENT=$((PRESENT + 1))
done
[ "$PRESENT" -gt 0 ] || exit 0

IMAGE="docker.io/$DOCKERHUB_USER/$IMAGE_NAME:$TAG"
echo "$NAMESPACE ($COMPONENT): applying $(basename "$FILE") with image $IMAGE (replicas left as they are)"
sed -e 's/${NAMESPACE}/'"$NAMESPACE"'/g' -e 's/${STORAGE_NAMESPACE}/'"$STORAGE_NAMESPACE"'/g' "$FILE" \
  | sed -E -e '/^  replicas: [0-9]+$/d' -e "s#(image: )docker\.io/[^/ ]+/$IMAGE_NAME:[^ ]+#\1$IMAGE#" \
  | kubectl apply --server-side --force-conflicts --field-manager=rellm-ci -f - -n "$NAMESPACE"
