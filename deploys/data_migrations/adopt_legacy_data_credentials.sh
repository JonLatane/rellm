#!/usr/bin/env bash
# ============================================================================
# ONE-TIME, PER-NAMESPACE, MANUAL. Run once for each namespace that was deployed BEFORE
# k8s/*.yaml started reading Postgres/object storage credentials from a Secret
# (rellm-data-credentials, see `create_backend_data_credentials` in deploys/Makefile).
#
# Those namespaces' running Deployments/StatefulSets have their credentials written inline (the old
# checked-in defaults, or whatever you changed them to). This script creates the Secret FROM THOSE
# LIVE VALUES -- it doesn't assume the defaults, and it doesn't change any credential -- so the new
# manifests (which now say "read it from the Secret") keep working against the exact same database
# and object storage, with no restart of either. It verifies the Deployment's values agree with the
# Postgres/object storage StatefulSets' own before creating anything, and is safe to re-run (it
# leaves an existing Secret alone).
#
# RUN THIS BEFORE the next `make update_*_backend`/CI deploy of the namespace: the new manifests
# reference the Secret, and deploys/select_backend_manifest.sh (used by CI) deliberately refuses to
# deploy a namespace that doesn't have it, rather than roll out pods that can't start.
#
# To then ROTATE a credential you'd change it in both the running server (Postgres:
# ALTER ROLE ... PASSWORD; object storage: its root credentials env) and the Secret -- this script
# only adopts what's there. Namespaces moving to central storage
# (transition_jonline_namespace_to_central_storage.sh) get fresh random credentials instead, and
# can drop this Secret afterwards (`make delete_backend_data_pvcs` does).
#
# Usage: ./adopt_legacy_data_credentials.sh <namespace>
# ============================================================================
set -euo pipefail

NAMESPACE="${1:?Usage: $0 <namespace>}"
printf '%s' "$NAMESPACE" | grep -Eq '^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$' || { echo "Invalid namespace '$NAMESPACE'" >&2; exit 1; }
SECRET=rellm-data-credentials

die() { echo "ERROR: $*" >&2; exit 1; }
# <kind/name> <container-index-expr-free env name> -> literal value of that env var (or empty)
env_value() { kubectl get "$1" -n "$NAMESPACE" -o "jsonpath={.spec.template.spec.containers[0].env[?(@.name==\"$2\")].value}"; }

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || die "Namespace '$NAMESPACE' doesn't exist in $(kubectl config current-context)"
if kubectl get secret "$SECRET" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "$NAMESPACE already has $SECRET -- nothing to do."
  exit 0
fi

kubectl get deployment rellm -n "$NAMESPACE" >/dev/null 2>&1 || die "No 'rellm' Deployment in $NAMESPACE"
kubectl get statefulset rellm-postgres rellm-object-storage -n "$NAMESPACE" >/dev/null 2>&1 \
  || die "$NAMESPACE has no rellm-postgres/rellm-object-storage StatefulSets -- it doesn't use its own storage (already on central storage?)"

DB_URL="$(env_value deployment/rellm DATABASE_URL)"
[ -n "$DB_URL" ] || die "rellm's DATABASE_URL isn't an inline value (already Secret-backed?) -- nothing to adopt"
case "$DB_URL" in postgres://admin:*@rellm-postgres/*) ;; *) die "Unexpected DATABASE_URL '$DB_URL' (expected postgres://admin:<password>@rellm-postgres/<db>)" ;; esac
PG_PASSWORD="${DB_URL#postgres://admin:}"; PG_PASSWORD="${PG_PASSWORD%%@*}"
OS_USER="$(env_value deployment/rellm OBJECT_STORAGE_ACCESS_KEY)"
OS_PASSWORD="$(env_value deployment/rellm OBJECT_STORAGE_SECRET_KEY)"
[ -n "$PG_PASSWORD" ] && [ -n "$OS_USER" ] && [ -n "$OS_PASSWORD" ] || die "Couldn't read all of the server's inline credentials"

[ "$(env_value statefulset/rellm-postgres POSTGRES_PASSWORD)" = "$PG_PASSWORD" ] \
  || die "The server's Postgres password doesn't match rellm-postgres's POSTGRES_PASSWORD -- resolve that by hand first"
[ "$(env_value statefulset/rellm-object-storage MINIO_ROOT_USER)" = "$OS_USER" ] \
  && [ "$(env_value statefulset/rellm-object-storage MINIO_ROOT_PASSWORD)" = "$OS_PASSWORD" ] \
  || die "The server's object storage credentials don't match rellm-object-storage's MINIO_ROOT_USER/PASSWORD -- resolve that by hand first"

kubectl create secret generic "$SECRET" -n "$NAMESPACE" \
  --from-literal=postgres-password="$PG_PASSWORD" \
  --from-literal=object-storage-user="$OS_USER" \
  --from-literal=object-storage-password="$OS_PASSWORD" >/dev/null
echo "Created $NAMESPACE/$SECRET from the namespace's live credentials (nothing was restarted or changed)."
