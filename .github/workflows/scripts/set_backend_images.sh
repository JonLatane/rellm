#!/usr/bin/env bash
# Rolls a namespace's Rellm deployments to a new image tag -- and changes NOTHING else.
#
# Usage: set_backend_images.sh <server|preview> <namespace> <tag> <dockerhub-user>
#   server  -> deployment/rellm and deployment/rellm-jobs (image <user>/rellm:<tag>)
#   preview -> deployment/rellm-preview-generator (image <user>/rellm_preview_generator:<tag>)
#
# CI deliberately only bumps image tags (kubectl set image), never `kubectl apply`s manifests:
# the namespace's storage wiring (per-namespace vs. central storage), credentials Secrets,
# replica counts and every other setting stay exactly as they are. That makes a CI deploy safe
# during a storage transition (a scaled-down site stays scaled down) and independent of how a
# namespace is configured. The consequence: changes to deploys/k8s manifests are NOT rolled out by
# CI -- see "Rolling out manifest changes" in deploys/README.md.
#
# Fails (without changing anything) if a deployment doesn't exist -- a namespace must be
# provisioned by the deploys/ Makefile first -- or if its container isn't named as expected.
set -euo pipefail

COMPONENT="${1:?Usage: $0 <server|preview> <namespace> <tag> <dockerhub-user>}"
NAMESPACE="${2:?Usage: $0 <server|preview> <namespace> <tag> <dockerhub-user>}"
TAG="${3:?Usage: $0 <server|preview> <namespace> <tag> <dockerhub-user>}"
DOCKERHUB_USER="${4:?Usage: $0 <server|preview> <namespace> <tag> <dockerhub-user>}"

printf '%s' "$NAMESPACE" | grep -Eq '^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$' || { echo "Invalid namespace '$NAMESPACE'" >&2; exit 1; }
printf '%s' "$TAG" | grep -Eq '^[A-Za-z0-9._-]{1,128}$' || { echo "Invalid image tag '$TAG'" >&2; exit 1; }
printf '%s' "$DOCKERHUB_USER" | grep -Eq '^[A-Za-z0-9._-]+$' || { echo "Invalid DockerHub user" >&2; exit 1; }

case "$COMPONENT" in
  server)  IMAGE="docker.io/$DOCKERHUB_USER/rellm:$TAG";                     DEPLOYMENTS="rellm rellm-jobs" ;;
  preview) IMAGE="docker.io/$DOCKERHUB_USER/rellm_preview_generator:$TAG";   DEPLOYMENTS="rellm-preview-generator" ;;
  *) echo "Unknown component '$COMPONENT' (expected server or preview)" >&2; exit 1 ;;
esac

# Check everything exists first so a missing deployment fails before anything is rolled.
for d in $DEPLOYMENTS; do
  CONTAINERS="$(kubectl get deployment "$d" -n "$NAMESPACE" --ignore-not-found -o 'jsonpath={.spec.template.spec.containers[*].name}')"
  [ -n "$CONTAINERS" ] || { echo "ERROR: deployment/$d doesn't exist in $NAMESPACE -- provision the namespace first (see deploys/README.md); CI only updates images." >&2; exit 1; }
  case " $CONTAINERS " in *" $d "*) ;; *) echo "ERROR: deployment/$d in $NAMESPACE has containers [$CONTAINERS], expected one named '$d'." >&2; exit 1 ;; esac
done

for d in $DEPLOYMENTS; do
  PREVIOUS="$(kubectl get deployment "$d" -n "$NAMESPACE" -o 'jsonpath={.spec.template.spec.containers[0].image}')"
  echo "$NAMESPACE/$d: $PREVIOUS -> $IMAGE"
  kubectl set image "deployment/$d" "$d=$IMAGE" -n "$NAMESPACE"
done
