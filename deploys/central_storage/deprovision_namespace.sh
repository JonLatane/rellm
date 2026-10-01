#!/usr/bin/env bash
# ============================================================================
# The reverse of provision_namespace.sh: removes ONE namespace's slice of the shared central
# storage -- its Postgres database + role, its object storage bucket (AND every object in it) +
# user + policy, and the rellm-central-data Secret. Meant for cleaning up a smoke test
# (NAMESPACE=central-smoke ...), or retiring a site for good.
#
# DESTRUCTIVE and NOT undoable: the database and every object in the bucket are deleted.
#
# Usage:
#   ./deprovision_namespace.sh [--yes] <namespace>
#   (or: NAMESPACE=<namespace> CONFIRM=<namespace> make delete_backend_central_data)
#
#   --yes   Skip the interactive "type the namespace to confirm" prompt.
#
# Refuses while a `rellm` Deployment in the namespace is still running against central storage
# (i.e. reads its DATABASE_URL from the rellm-central-data Secret): delete the site first
# (`kubectl delete namespace <namespace>`, or move it back off central storage), then run this.
# It's fine -- expected, for the smoke test -- for the namespace itself to already be gone.
# Safe to re-run: anything already removed is skipped.
#
# Environment: STORAGE_NAMESPACE (default rellm-storage). Safe to run for several namespaces at once.
# Prerequisites: kubectl, mc (brew install minio/stable/mc).
# ============================================================================
set -Eeuo pipefail

STORAGE_NAMESPACE="${STORAGE_NAMESPACE:-rellm-storage}"
LOCAL_PORT=""   # kernel-chosen free port, so several runs can overlap
SECRET_NAME=rellm-central-data
YES=false
NAMESPACE=""

usage() { sed -n '2,/^# =====/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; }
die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "   $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=true ;;
    -h|--help) usage; exit 0 ;;
    -*) die "Unknown option '$1' (see --help)" ;;
    *) [ -z "$NAMESPACE" ] || die "Only one namespace may be given"; NAMESPACE="$1" ;;
  esac
  shift
done
[ -n "$NAMESPACE" ] || { usage >&2; die "Usage: $0 [--yes] <namespace>"; }

valid_ns() { printf '%s' "$1" | grep -Eq '^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$'; }
valid_ns "$NAMESPACE" || die "'$NAMESPACE' is not a valid Kubernetes namespace name"
valid_ns "$STORAGE_NAMESPACE" || die "STORAGE_NAMESPACE '$STORAGE_NAMESPACE' is not a valid Kubernetes namespace name"
[ "$NAMESPACE" != "$STORAGE_NAMESPACE" ] || die "NAMESPACE can't be the central storage namespace itself"
for cmd in kubectl mc base64; do
  command -v "$cmd" >/dev/null || die "'$cmd' is required but not installed$([ "$cmd" = mc ] && echo ' -- brew install minio/stable/mc')"
done

PF_PID=""
TMP_DIR="$(mktemp -d)"
cleanup() { [ -z "$PF_PID" ] || { kill "$PF_PID" && wait "$PF_PID"; } 2>/dev/null || true; rm -rf "$TMP_DIR"; }
trap cleanup EXIT

central_psql() { kubectl exec -i -n "$STORAGE_NAMESPACE" rellm-central-postgres-0 -- psql -U admin -tA -v ON_ERROR_STOP=1 "$@"; }
secret_value() { kubectl get secret "$1" -n "$STORAGE_NAMESPACE" -o "jsonpath={.data.$2}" | base64 --decode; }

echo "== Preflight: central storage in $STORAGE_NAMESPACE =="
kubectl get namespace "$STORAGE_NAMESPACE" >/dev/null 2>&1 || die "Namespace '$STORAGE_NAMESPACE' doesn't exist"
kubectl wait --for=condition=ready pod/rellm-central-postgres-0 -n "$STORAGE_NAMESPACE" --timeout=30s >/dev/null || die "rellm-central-postgres-0 isn't ready"
kubectl wait --for=condition=ready pod/rellm-central-object-storage-0 -n "$STORAGE_NAMESPACE" --timeout=30s >/dev/null || die "rellm-central-object-storage-0 isn't ready"

# Refuse to pull the storage out from under a site that's still running on it.
if [ -n "$(kubectl get deployment rellm -n "$NAMESPACE" --ignore-not-found -o name 2>/dev/null)" ]; then
  LIVE_SECRET="$(kubectl get deployment rellm -n "$NAMESPACE" -o 'jsonpath={.spec.template.spec.containers[0].env[?(@.name=="DATABASE_URL")].valueFrom.secretKeyRef.name}')"
  [ "$LIVE_SECRET" != "$SECRET_NAME" ] \
    || die "The 'rellm' Deployment in $NAMESPACE is still running against central storage. Delete the site first (e.g. kubectl delete namespace $NAMESPACE), then re-run."
fi

ROOT_USER="$(secret_value rellm-central-object-storage-credentials root-user)"
ROOT_PASSWORD="$(secret_value rellm-central-object-storage-credentials root-password)"
kubectl port-forward -n "$STORAGE_NAMESPACE" pod/rellm-central-object-storage-0 ":9000" >"$TMP_DIR/pf.log" 2>&1 &
PF_PID=$!
for i in $(seq 1 20); do
  LOCAL_PORT="$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9][0-9]*\) ->.*/\1/p' "$TMP_DIR/pf.log" 2>/dev/null | head -1)"
  [ -z "$LOCAL_PORT" ] || break
  sleep 1
done
[ -n "$LOCAL_PORT" ] || { cat "$TMP_DIR/pf.log" >&2; die "port-forward to central object storage never came up"; }
export MC_HOST_central="http://$ROOT_USER:$ROOT_PASSWORD@127.0.0.1:$LOCAL_PORT"
mc ls central >/dev/null 2>&1 || die "Couldn't authenticate to the central object storage as its root user"

DB_EXISTS="$(echo "SELECT 1 FROM pg_database WHERE datname = '$NAMESPACE';" | central_psql -d postgres)"
ROLE_EXISTS="$(echo "SELECT 1 FROM pg_roles WHERE rolname = '$NAMESPACE';" | central_psql -d postgres)"
mc admin user info central "$NAMESPACE" >/dev/null 2>&1 && USER_EXISTS=1 || USER_EXISTS=""
mc admin policy info central "rellm-$NAMESPACE" >/dev/null 2>&1 && POLICY_EXISTS=1 || POLICY_EXISTS=""
mc ls "central/$NAMESPACE" >/dev/null 2>&1 && BUCKET_EXISTS=1 || BUCKET_EXISTS=""
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1 && SECRET_EXISTS=1 || SECRET_EXISTS=""

FOUND=""
[ "$DB_EXISTS" = "1" ] && FOUND="$FOUND\n   - Postgres database '$NAMESPACE'"
[ "$ROLE_EXISTS" = "1" ] && FOUND="$FOUND\n   - Postgres role '$NAMESPACE'"
if [ -n "$BUCKET_EXISTS" ]; then
  COUNT="$(mc ls --recursive "central/$NAMESPACE" 2>/dev/null | wc -l | tr -d ' ')"
  FOUND="$FOUND\n   - object storage bucket '$NAMESPACE' and its $COUNT object(s)"
fi
[ -n "$USER_EXISTS" ] && FOUND="$FOUND\n   - object storage user '$NAMESPACE'"
[ -n "$POLICY_EXISTS" ] && FOUND="$FOUND\n   - object storage policy 'rellm-$NAMESPACE'"
[ -n "$SECRET_EXISTS" ] && FOUND="$FOUND\n   - Secret $NAMESPACE/$SECRET_NAME"
if [ -z "$FOUND" ]; then
  echo "Nothing to remove: no central storage resources exist for '$NAMESPACE'."
  exit 0
fi

echo
echo "   This PERMANENTLY deletes, from $(kubectl config current-context)'s central storage:"
printf '%b\n' "$FOUND"
if [ "$YES" = false ]; then
  [ -t 0 ] || die "Not a terminal -- pass --yes to run non-interactively"
  printf '\n   Type the namespace name (%s) to proceed: ' "$NAMESPACE"
  read -r answer
  [ "$answer" = "$NAMESPACE" ] || die "Confirmation didn't match -- aborting, nothing was changed"
fi

echo
echo "== Removing =="
[ "$DB_EXISTS" = "1" ] && { echo "DROP DATABASE \"$NAMESPACE\" WITH (FORCE);" | central_psql -d postgres; info "dropped database"; }
[ "$ROLE_EXISTS" = "1" ] && { echo "DROP ROLE \"$NAMESPACE\";" | central_psql -d postgres; info "dropped role"; }
[ -n "$USER_EXISTS" ] && { mc admin user remove central "$NAMESPACE" >/dev/null; info "removed object storage user"; }
[ -n "$POLICY_EXISTS" ] && { mc admin policy remove central "rellm-$NAMESPACE" >/dev/null; info "removed object storage policy"; }
[ -n "$BUCKET_EXISTS" ] && { mc rb --force "central/$NAMESPACE" >/dev/null; info "removed bucket and its objects"; }
[ -n "$SECRET_EXISTS" ] && { kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null; info "deleted Secret"; }
echo
echo "Done: central storage no longer has anything for '$NAMESPACE'."
