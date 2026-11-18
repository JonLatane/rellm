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
# this script's fallback and as the manual one-off. Safety rails, since this touches production:
#   * Only manifests for namespaces on CENTRAL storage are applied (every CI namespace is). A namespace
#     with its own Postgres/object storage uses other manifests -- roll those out by hand
#     (deploys/README.md, "Rolling out manifest changes").
#   * It only updates what already exists -- the Deployments must have been provisioned by the deploys/
#     Makefile (server and preview fail if they're missing; embedding and vector are optional and skip).
#   * If ANY of the component's Deployments is scaled to 0 (a site parked during a storage transition),
#     it falls back to image-only so applying can't scale the site back up.
#   * Credentials Secrets and PVC contents are never in these manifests; nothing is deleted (no
#     `--prune`), so a resource removed from a manifest has to be removed by hand.
#   * The image in each applied manifest is rewritten to <dockerhub-user>/<image>:<tag>; nothing else
#     in the manifest is edited besides the ${NAMESPACE}/${STORAGE_NAMESPACE} substitution that
#     deploys/Makefile also does.
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
SCALED_DOWN=""
PRESENT=0
for d in $DEPLOYMENTS; do
  REPLICAS="$(kubectl get deployment "$d" -n "$NAMESPACE" --ignore-not-found -o 'jsonpath={.spec.replicas}')"
  if [ -z "$REPLICAS" ]; then
    if [ -n "$OPTIONAL" ]; then echo "$NAMESPACE/$d: not deployed (optional) -- skipping"; continue; fi
    echo "ERROR: deployment/$d doesn't exist in $NAMESPACE -- provision the namespace first (see deploys/README.md); CI only updates what exists." >&2; exit 1
  fi
  PRESENT=$((PRESENT + 1))
  [ "$REPLICAS" = "0" ] && SCALED_DOWN="$SCALED_DOWN $d"
done
[ "$PRESENT" -gt 0 ] || exit 0

if [ -n "$SCALED_DOWN" ]; then
  echo "$NAMESPACE:${SCALED_DOWN} scaled to 0 -- NOT applying manifests (it would scale back up); bumping the image tag only."
  exec "$HERE/set_backend_images.sh" "$COMPONENT" "$NAMESPACE" "$TAG" "$DOCKERHUB_USER"
fi

IMAGE="docker.io/$DOCKERHUB_USER/$IMAGE_NAME:$TAG"
echo "$NAMESPACE ($COMPONENT): applying $(basename "$FILE") with image $IMAGE"
sed -e 's/${NAMESPACE}/'"$NAMESPACE"'/g' -e 's/${STORAGE_NAMESPACE}/'"$STORAGE_NAMESPACE"'/g' "$FILE" \
  | sed -E "s#(image: )docker\.io/[^/ ]+/$IMAGE_NAME:[^ ]+#\1$IMAGE#" \
  | kubectl apply -f - -n "$NAMESPACE"
