#!/usr/bin/env bash
# ============================================================================
# Provisions ONE namespace's slice of the shared central storage (see README.md): its own
# Postgres database + login role, its own object storage bucket + user, and a Secret in the
# namespace holding the randomly generated credentials for both. Everything is named after the
# namespace: database, Postgres role, bucket, Silo user (and the Silo policy, rellm-<namespace>).
#
# Usage:
#   ./provision_namespace.sh [--reset] [--check] <namespace>
#   (or: NAMESPACE=<namespace> make create_backend_central_data [ARGS=--reset])
#
#   --check   Run only the preflight (valid names, tools present, central pods healthy, nothing
#             already exists for this namespace, unless --reset) and exit without changing anything.
#   --reset   If a previous (possibly half-finished) run left a database/role/Silo user/Secret for
#             this namespace behind, DROP them and start over. The bucket and its contents are
#             deliberately KEPT (only the user/policy/credentials are recreated). Without this
#             flag, the script refuses to touch anything that already exists.
#
# Environment: STORAGE_NAMESPACE (default rellm-storage), OBJECT_STORAGE_ADMIN_LOCAL_PORT
# (default 19002; local port of the temporary port-forward used for `mc`).
#
# What gets restricted, and how:
#   Postgres  - the role is LOGIN only: NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION
#               NOBYPASSRLS, CONNECTION LIMIT 30. It owns its database (so migrations/extensions
#               work -- the only extension used, btree_gin, is a "trusted" one) and PUBLIC's
#               CONNECT on that database is revoked, so no other site's role can even connect to
#               it. PUBLIC's CONNECT on the `postgres` maintenance database is revoked too. Over
#               the network the instance requires the password (scram-sha-256).
#   Silo      - the user gets a policy allowing s3:* on ONLY arn:aws:s3:::<namespace> (and its
#               objects). The script proves this before finishing: it must be able to write to its
#               own bucket and must NOT be able to create another one.
#   Secret    - <namespace>/rellm-central-data: database-url, object-storage-access-key,
#               object-storage-secret-key. Passwords are 48 hex chars from `openssl rand`.
#
# Prerequisites: kubectl, mc (brew install minio/stable/mc), openssl; central storage already
# running (make -C central_storage create_central_storage).
# ============================================================================
set -Eeuo pipefail

STORAGE_NAMESPACE="${STORAGE_NAMESPACE:-rellm-storage}"
LOCAL_PORT="${OBJECT_STORAGE_ADMIN_LOCAL_PORT:-19002}"
SECRET_NAME=rellm-central-data
PG_CONNECTION_LIMIT=30

RESET=false
CHECK_ONLY=false
NAMESPACE=""

usage() { sed -n '2,/^# =====/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; }
die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "   $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --reset) RESET=true ;;
    --check) CHECK_ONLY=true ;;
    -h|--help) usage; exit 0 ;;
    -*) die "Unknown option '$1' (see --help)" ;;
    *) [ -z "$NAMESPACE" ] || die "Only one namespace may be given"; NAMESPACE="$1" ;;
  esac
  shift
done
[ -n "$NAMESPACE" ] || { usage >&2; die "Usage: $0 [--reset] [--check] <namespace>"; }

valid_ns() { printf '%s' "$1" | grep -Eq '^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$'; }
valid_ns "$NAMESPACE" || die "'$NAMESPACE' is not a valid Kubernetes namespace name (lowercase letters, digits and '-' only)"
valid_ns "$STORAGE_NAMESPACE" || die "STORAGE_NAMESPACE '$STORAGE_NAMESPACE' is not a valid Kubernetes namespace name"
[ "$NAMESPACE" != "$STORAGE_NAMESPACE" ] || die "NAMESPACE can't be the central storage namespace itself"
# Bucket names and Silo access keys both need at least 3 characters.
[ "${#NAMESPACE}" -ge 3 ] || die "'$NAMESPACE' is too short (object storage bucket names/user names need at least 3 characters)"

for cmd in kubectl mc openssl base64; do
  command -v "$cmd" >/dev/null || die "'$cmd' is required but not installed$([ "$cmd" = mc ] && echo ' -- brew install minio/stable/mc')"
done

PF_PID=""
cleanup() { [ -z "$PF_PID" ] || { kill "$PF_PID" && wait "$PF_PID"; } 2>/dev/null || true; rm -rf "${TMP_DIR:-}"; }
trap cleanup EXIT
TMP_DIR="$(mktemp -d)"
on_error() {
  local rc=$?
  trap - ERR
  echo >&2
  echo "!! FAILED (exit $rc). $NAMESPACE may be partially provisioned in $STORAGE_NAMESPACE." >&2
  echo "!! Nothing else was modified; re-run with --reset to drop what was created and start over." >&2
  exit "$rc"
}

central_psql() { kubectl exec -i -n "$STORAGE_NAMESPACE" rellm-central-postgres-0 -- psql -U admin -tA -v ON_ERROR_STOP=1 "$@"; }
secret_value() { kubectl get secret "$1" -n "$STORAGE_NAMESPACE" -o "jsonpath={.data.$2}" | base64 --decode; }

echo "== Preflight: central storage in $STORAGE_NAMESPACE =="
kubectl get namespace "$STORAGE_NAMESPACE" >/dev/null 2>&1 || die "Namespace '$STORAGE_NAMESPACE' doesn't exist -- run: make -C central_storage create_central_storage"
kubectl wait --for=condition=ready pod/rellm-central-postgres-0 -n "$STORAGE_NAMESPACE" --timeout=30s >/dev/null || die "rellm-central-postgres-0 isn't ready"
kubectl wait --for=condition=ready pod/rellm-central-object-storage-0 -n "$STORAGE_NAMESPACE" --timeout=30s >/dev/null || die "rellm-central-object-storage-0 isn't ready"
ROOT_USER="$(secret_value rellm-central-object-storage-credentials root-user)"
ROOT_PASSWORD="$(secret_value rellm-central-object-storage-credentials root-password)"
[ -n "$ROOT_USER" ] && [ -n "$ROOT_PASSWORD" ] || die "Couldn't read rellm-central-object-storage-credentials in $STORAGE_NAMESPACE"

start_port_forward() {
  kubectl port-forward -n "$STORAGE_NAMESPACE" pod/rellm-central-object-storage-0 "$LOCAL_PORT:9000" >"$TMP_DIR/pf.log" 2>&1 &
  PF_PID=$!
  local i
  for i in $(seq 1 20); do
    grep -q "Forwarding from" "$TMP_DIR/pf.log" 2>/dev/null && return 0
    sleep 1
  done
  cat "$TMP_DIR/pf.log" >&2
  die "port-forward to the central object storage on local port $LOCAL_PORT never came up (port in use? set OBJECT_STORAGE_ADMIN_LOCAL_PORT)"
}
start_port_forward
export MC_HOST_central="http://$ROOT_USER:$ROOT_PASSWORD@localhost:$LOCAL_PORT"
mc ls central >/dev/null 2>&1 || die "Couldn't authenticate to the central object storage as its root user"

ROLE_EXISTS="$(echo "SELECT 1 FROM pg_roles WHERE rolname = '$NAMESPACE';" | central_psql -d postgres)"
DB_EXISTS="$(echo "SELECT 1 FROM pg_database WHERE datname = '$NAMESPACE';" | central_psql -d postgres)"
mc admin user info central "$NAMESPACE" >/dev/null 2>&1 && USER_EXISTS=1 || USER_EXISTS=""
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1 && SECRET_EXISTS=1 || SECRET_EXISTS=""

EXISTING=""
[ "$ROLE_EXISTS" = "1" ] && EXISTING="$EXISTING postgres-role"
[ "$DB_EXISTS" = "1" ] && EXISTING="$EXISTING postgres-database"
[ -n "$USER_EXISTS" ] && EXISTING="$EXISTING object-storage-user"
[ -n "$SECRET_EXISTS" ] && EXISTING="$EXISTING secret/$SECRET_NAME"
if [ -n "$EXISTING" ] && [ "$RESET" = false ]; then
  die "Already exists for '$NAMESPACE' in central storage:$EXISTING. If that's left over from a failed run, re-run with --reset; otherwise investigate before overwriting anything."
fi
if [ "$CHECK_ONLY" = true ]; then
  echo "   Preflight OK for '$NAMESPACE'${EXISTING:+ (would --reset:$EXISTING)}."
  exit 0
fi

trap on_error ERR

if [ -n "$EXISTING" ]; then
  echo "== --reset: removing previous credentials/database for '$NAMESPACE' (bucket and its objects are kept) =="
  [ "$DB_EXISTS" = "1" ] && echo "DROP DATABASE \"$NAMESPACE\" WITH (FORCE);" | central_psql -d postgres
  [ "$ROLE_EXISTS" = "1" ] && echo "DROP ROLE \"$NAMESPACE\";" | central_psql -d postgres
  [ -n "$USER_EXISTS" ] && mc admin user remove central "$NAMESPACE"
  mc admin policy remove central "rellm-$NAMESPACE" >/dev/null 2>&1 || true
  [ -n "$SECRET_EXISTS" ] && kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
fi

PG_PASSWORD="$(openssl rand -hex 24)"
OS_SECRET_KEY="$(openssl rand -hex 24)"

echo "== Postgres: role + database '$NAMESPACE' =="
central_psql -d postgres -q <<SQL
CREATE ROLE "$NAMESPACE" LOGIN PASSWORD '$PG_PASSWORD' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS CONNECTION LIMIT $PG_CONNECTION_LIMIT;
CREATE DATABASE "$NAMESPACE" OWNER "$NAMESPACE";
REVOKE ALL ON DATABASE "$NAMESPACE" FROM PUBLIC;
REVOKE CONNECT ON DATABASE postgres FROM PUBLIC;
SQL
info "role '$NAMESPACE' (limited to $PG_CONNECTION_LIMIT connections) owns database '$NAMESPACE'; PUBLIC can't connect to it."

echo "== Object storage: bucket + user + bucket-scoped policy '$NAMESPACE' =="
mc mb --ignore-existing "central/$NAMESPACE" >/dev/null
cat > "$TMP_DIR/policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": ["arn:aws:s3:::$NAMESPACE", "arn:aws:s3:::$NAMESPACE/*"]
    }
  ]
}
JSON
# `mc admin policy create/attach` (current) vs. `add/set` (older mc / MinIO-compatible servers).
mc admin policy create central "rellm-$NAMESPACE" "$TMP_DIR/policy.json" >/dev/null 2>&1 \
  || mc admin policy add central "rellm-$NAMESPACE" "$TMP_DIR/policy.json" >/dev/null
mc admin user add central "$NAMESPACE" "$OS_SECRET_KEY" >/dev/null
mc admin policy attach central "rellm-$NAMESPACE" --user "$NAMESPACE" >/dev/null 2>&1 \
  || mc admin policy set central "rellm-$NAMESPACE" "user=$NAMESPACE" >/dev/null

echo "== Verifying the new Silo user is scoped to its own bucket =="
export MC_HOST_verify="http://$NAMESPACE:$OS_SECRET_KEY@localhost:$LOCAL_PORT"
echo probe | mc pipe "verify/$NAMESPACE/.rellm-provision-check" >/dev/null 2>&1 \
  || die "New user '$NAMESPACE' can't write to its own bucket -- the policy didn't apply (does this Silo version support 'mc admin policy'?)"
mc rm "verify/$NAMESPACE/.rellm-provision-check" >/dev/null 2>&1 || true
DENIED_PROBE="zz-rellm-denied-probe-$(openssl rand -hex 4)"
if mc mb "verify/$DENIED_PROBE" >/dev/null 2>&1; then
  mc rb "verify/$DENIED_PROBE" >/dev/null 2>&1 || mc rb --force "central/$DENIED_PROBE" >/dev/null 2>&1 || true
  die "New user '$NAMESPACE' was able to create an unrelated bucket -- the policy is NOT restrictive. Aborting; fix before using this credential."
fi
info "can read/write bucket '$NAMESPACE'; cannot create other buckets."

echo "== Secret $NAMESPACE/$SECRET_NAME =="
kubectl create namespace "$NAMESPACE" >/dev/null 2>&1 || true
kubectl create secret generic "$SECRET_NAME" -n "$NAMESPACE" \
  --from-literal=database-url="postgres://$NAMESPACE:$PG_PASSWORD@rellm-central-postgres.$STORAGE_NAMESPACE.svc.cluster.local/$NAMESPACE" \
  --from-literal=object-storage-access-key="$NAMESPACE" \
  --from-literal=object-storage-secret-key="$OS_SECRET_KEY" >/dev/null
info "stored database-url, object-storage-access-key, object-storage-secret-key."

trap - ERR
echo
echo "Provisioned '$NAMESPACE' in $STORAGE_NAMESPACE. Deploy it with: NAMESPACE=$NAMESPACE make create_internal_central_data_backend"
