#!/usr/bin/env bash
# Prints the path of the manifest CI (or you) should `kubectl apply` for a namespace's backend,
# choosing between the per-namespace-storage manifests (server_internal.yaml/preview_generator.yaml)
# and the central_storage ones (server_internal_central_data.yaml/preview_generator_central_data.yaml,
# generated for this namespace) based on what the namespace is running RIGHT NOW: if its live
# `rellm` Deployment's DATABASE_URL comes from the rellm-central-data Secret it's on central
# storage, otherwise it isn't. Deciding from the live Deployment (rather than, say, whether the
# Secret exists) means a namespace only ever switches when
# transition_jonline_namespace_to_central_storage.sh actually applies the switch -- a half-finished
# provisioning can't flip CI's next deploy onto an empty database.
#
# Usage: kubectl apply -f "$(deploys/select_backend_manifest.sh server <namespace>)" -n <namespace>
#        kubectl apply -f "$(deploys/select_backend_manifest.sh preview <namespace>)" -n <namespace>
#
# Only the path goes to stdout (everything else to stderr). Fails -- rather than guessing -- if the
# cluster can't be queried, since guessing wrong would silently point a live site at the wrong DB.
# Version-bumping (sed of the image tag) must already have been applied to BOTH sets of manifests.
set -euo pipefail

COMPONENT="${1:?Usage: $0 <server|preview> <namespace>}"
NAMESPACE="${2:?Usage: $0 <server|preview> <namespace>}"
DEPLOYS_DIR="$(cd "$(dirname "$0")" && pwd)"
STORAGE_NAMESPACE="${STORAGE_NAMESPACE:-rellm-storage}"

case "$COMPONENT" in
  server)  STATIC="server_internal.yaml";     TEMPLATE_NAME="server_internal_central_data" ;;
  preview) STATIC="preview_generator.yaml";   TEMPLATE_NAME="preview_generator_central_data" ;;
  *) echo "Unknown component '$COMPONENT' (expected server or preview)" >&2; exit 1 ;;
esac
printf '%s' "$NAMESPACE" | grep -Eq '^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$' || { echo "Invalid namespace '$NAMESPACE'" >&2; exit 1; }

# --ignore-not-found: a Deployment that doesn't exist yet is fine (fresh namespace -> static);
# any OTHER kubectl failure (auth, network) exits non-zero here and aborts via `set -e`.
if [ -n "$(kubectl get deployment rellm -n "$NAMESPACE" --ignore-not-found -o name)" ]; then
  DB_SECRET="$(kubectl get deployment rellm -n "$NAMESPACE" -o 'jsonpath={.spec.template.spec.containers[0].env[?(@.name=="DATABASE_URL")].valueFrom.secretKeyRef.name}')"
else
  DB_SECRET=""
fi

if [ "$DB_SECRET" = "rellm-central-data" ]; then
  GENERATED="k8s/$TEMPLATE_NAME.$NAMESPACE.generated.yaml"
  rm -f "$DEPLOYS_DIR/$GENERATED"
  make -C "$DEPLOYS_DIR" --no-print-directory "$GENERATED" NAMESPACE="$NAMESPACE" STORAGE_NAMESPACE="$STORAGE_NAMESPACE" >&2
  echo "$NAMESPACE is on central storage -> $GENERATED" >&2
  echo "$DEPLOYS_DIR/$GENERATED"
else
  # The per-namespace manifests read their credentials from the rellm-data-credentials Secret. A
  # namespace deployed before that existed doesn't have one yet: fail here (the site keeps running
  # its current pods) instead of applying manifests whose pods couldn't start.
  if [ -z "$(kubectl get secret rellm-data-credentials -n "$NAMESPACE" --ignore-not-found -o name)" ]; then
    echo "ERROR: $NAMESPACE has no rellm-data-credentials Secret, which k8s/$STATIC now requires. For a namespace that already exists run: deploys/data_migrations/adopt_legacy_data_credentials.sh $NAMESPACE (for a new one: NAMESPACE=$NAMESPACE make create_backend_data_credentials)." >&2
    exit 1
  fi
  echo "$NAMESPACE uses its own storage -> k8s/$STATIC" >&2
  echo "$DEPLOYS_DIR/k8s/$STATIC"
fi
