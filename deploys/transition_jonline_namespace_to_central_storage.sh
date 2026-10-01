#!/usr/bin/env bash
# ============================================================================
# ONE-TIME, PER-NAMESPACE, MANUAL transition script. NOT run automatically by
# anything -- not wired into CI, not invoked by any other script. Run it by
# hand, once, per already-deployed namespace that currently has its OWN
# Postgres/object storage (rellm-postgres/rellm-object-storage), to move it
# onto the shared instances in deploys/central_storage (rellm-central-postgres/
# rellm-central-object-storage in the rellm-storage namespace). See
# central_storage/README.md for why (short version: DOKS caps attached PVCs).
#
# Usage:
#   ./transition_jonline_namespace_to_central_storage.sh [options] <namespace>
#   ./transition_jonline_namespace_to_central_storage.sh bullcitysocial
#
# Options:
#   --yes, -y             Skip the interactive confirmation prompt.
#   --reset-target        If central storage already has a database/role/Silo user/Secret for
#                         this namespace (e.g. left half-populated by a previous failed run of
#                         this script), DROP them and start over (the bucket's objects are kept;
#                         the copy is incremental). Without this flag the script refuses to touch
#                         anything that already exists. Passed through to
#                         central_storage/provision_namespace.sh --reset.
#   --repo-images         Deploy the image tags written in server_internal_central_data.yaml/
#                         preview_generator_central_data.yaml instead of preserving whatever
#                         image tags the namespace's Deployments are running right now (the
#                         default -- CI deploys tags like 0.5.553-<sha> that aren't in the
#                         checked-in manifests, and this transition shouldn't ALSO be a
#                         surprise version change).
#   --no-traefik-bounce   Skip the final Traefik restart (see step 5).
#
# Environment:
#   STORAGE_NAMESPACE     Namespace of the central instances (default: rellm-storage)
#
# Running several at once: different namespaces can be transitioned in parallel (separate
# terminals) -- the port-forwards use kernel-chosen free local ports and provisioning is
# serialized where central storage needs it. The same namespace can't (a per-namespace lock refuses
# a second run). Pass --no-traefik-bounce to all but the last one so Traefik isn't bounced N times.
#
# What it does, in order (the namespace's site is DOWN from step 1 until step 4):
#   1. Scales rellm, rellm-jobs and rellm-preview-generator to 0 and waits for their pods
#      to be gone, so nothing can write to the old Postgres/bucket during the copy.
#   2. Provisions the namespace in the central instances via
#      central_storage/provision_namespace.sh -- a database + login role and a bucket + user, all
#      named after the namespace, each restricted to just that data, with random credentials
#      stored in the namespace's rellm-central-data Secret -- then copies ALL data over: Postgres
#      via pg_dump | psql (run inside the two Postgres pods, so client/server versions always
#      match; restored AS the new restricted role, so it owns everything), verified by comparing
#      per-table row counts; object storage via `mc mirror`, verified by `mc diff`.
#   3. Applies server_internal_central_data.yaml + preview_generator_central_data.yaml
#      (generated for this namespace, exactly like `make update_internal_central_data_backend`
#      does) so the Deployments point at the central Postgres/object storage.
#   4. Makes sure all three Deployments are actually back up (scales any still at 0 back to
#      their original replica counts), waits for rollout, and checks the pods aren't crash-
#      looping (the server runs migrations and tests the bucket at startup, so a bad
#      connection shows up right away).
#   5. Bounces Traefik -- same reason server_ci_cd.yml/data_migrations/cutover_jonline_namespace.sh do:
#      TLS-passthrough routing can get wedged on stale pod IPs after a rollout replaces pods.
#      NOTE: this briefly interrupts EVERY domain behind that Traefik, not just this one.
#
# What it deliberately does NOT do: delete, scale down, or modify this namespace's OLD
# rellm-postgres/rellm-object-storage StatefulSets, their data, or their PVCs -- they're
# left completely untouched (and running) so you can verify the cutover and roll back if
# needed. Once you're satisfied, remove them yourself with:
#   NAMESPACE=<namespace> CONFIRM=<namespace> make delete_backend_data_pvcs
# (see that target's docs in deploys/Makefile).
#
# CI: no change needed -- CI only bumps image tags (kubectl set image), so it never touches this
# namespace's storage wiring and can't scale a site you've taken down for this cutover back up.
#
# Prerequisites:
#  - kubectl pointed at the right cluster/context (the script prints it and asks first).
#  - The central instances already running: `make -C central_storage create_central_storage`.
#  - The MinIO Client, for the object storage copy: brew install minio/stable/mc
#  - Works on macOS's stock bash 3.2 (no arrays/associative arrays used).
# ============================================================================
set -Eeuo pipefail

DEPLOYS_DIR="$(cd "$(dirname "$0")" && pwd)"
STORAGE_NAMESPACE="${STORAGE_NAMESPACE:-rellm-storage}"
DEPLOYMENTS="rellm rellm-jobs rellm-preview-generator"
export STORAGE_NAMESPACE
PROVISION="$DEPLOYS_DIR/central_storage/provision_namespace.sh"

YES=false
RESET_TARGET=false
REPO_IMAGES=false
BOUNCE_TRAEFIK=true
NAMESPACE=""

usage() { sed -n '2,/^# =====/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; }
die() { echo "ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=true ;;
    --reset-target) RESET_TARGET=true ;;
    --repo-images) REPO_IMAGES=true ;;
    --no-traefik-bounce) BOUNCE_TRAEFIK=false ;;
    -h|--help) usage; exit 0 ;;
    -*) die "Unknown option '$1' (see --help)" ;;
    *) [ -z "$NAMESPACE" ] || die "Only one namespace may be given (got '$NAMESPACE' and '$1')"; NAMESPACE="$1" ;;
  esac
  shift
done
[ -n "$NAMESPACE" ] || { usage >&2; die "Usage: $0 [options] <namespace>"; }

# Same DNS-1123 label rule as deploys/Makefile -- NAMESPACE becomes the central database and
# bucket name, and lands in SQL identifiers/sed replacements below.
valid_ns() { printf '%s' "$1" | grep -Eq '^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$'; }
valid_ns "$NAMESPACE" || die "'$NAMESPACE' is not a valid Kubernetes namespace name (lowercase letters, digits and '-' only)"
valid_ns "$STORAGE_NAMESPACE" || die "STORAGE_NAMESPACE '$STORAGE_NAMESPACE' is not a valid Kubernetes namespace name"
[ "$NAMESPACE" != "$STORAGE_NAMESPACE" ] || die "NAMESPACE can't be the central storage namespace itself ($STORAGE_NAMESPACE)"

# Only one transition per namespace at a time (different namespaces may run concurrently: every
# port-forward uses a kernel-chosen free port, and central provisioning is serialized where needed).
LOCK_DIR="${TMPDIR:-/tmp}/rellm-transition-$NAMESPACE.lock"
LOCK_HELD=false
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  OTHER_PID="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [ -n "$OTHER_PID" ] && kill -0 "$OTHER_PID" 2>/dev/null; then
    die "Another transition of '$NAMESPACE' is already running (pid $OTHER_PID)"
  fi
  rm -rf "$LOCK_DIR"; mkdir "$LOCK_DIR" || die "Couldn't take the run lock $LOCK_DIR"
fi
echo $$ > "$LOCK_DIR/pid"
LOCK_HELD=true

STATE_DIR="$(mktemp -d)"
PF_PIDS=""
CURRENT_STEP="preflight"
DOWNTIME_STARTED=false
APPLIED=false

cleanup() {
  local pid
  for pid in $PF_PIDS; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$STATE_DIR"
  [ "$LOCK_HELD" = false ] || rm -rf "$LOCK_DIR"
}
trap cleanup EXIT

on_error() {
  local rc=$?
  trap - ERR
  echo >&2
  echo "!! FAILED during: $CURRENT_STEP (exit $rc)" >&2
  if [ "$DOWNTIME_STARTED" = true ]; then
    echo "!! The old per-namespace Postgres/object storage were NOT modified -- your original data is intact." >&2
    if [ "$APPLIED" = false ]; then
      echo "!! The central-data manifests were not applied yet, so the site is still DOWN (scaled to 0)." >&2
      echo "!! To bring the OLD setup straight back up:" >&2
      for d in $DEPLOYMENTS; do
        [ -f "$STATE_DIR/replicas.$d" ] && echo "!!   kubectl scale deployment/$d --replicas=$(cat "$STATE_DIR/replicas.$d") -n $NAMESPACE" >&2
      done
      echo "!! Or fix the problem above and re-run this script (add --reset-target if the central" >&2
      echo "!! database was left half-populated)." >&2
    else
      echo "!! The central-data manifests WERE applied. Inspect with: kubectl get pods -n $NAMESPACE; kubectl logs deploy/rellm -n $NAMESPACE" >&2
      echo "!! To go back to the per-namespace storage: NAMESPACE=$NAMESPACE make update_internal_backend" >&2
      echo "!! (any data written to the central instances since is NOT copied back)." >&2
    fi
  fi
  exit "$rc"
}
trap on_error ERR

step() { CURRENT_STEP="$*"; echo; echo "== $* =="; }
info() { echo "   $*"; }

deployment_exists() { kubectl get deployment "$1" -n "$NAMESPACE" >/dev/null 2>&1; }
deployment_env() { kubectl get deployment "$1" -n "$NAMESPACE" -o "jsonpath={.spec.template.spec.containers[0].env[?(@.name==\"$2\")].value}"; }
# Like deployment_env, but also follows a secretKeyRef (per-namespace manifests now read their
# credentials from the rellm-data-credentials Secret; older namespaces have them inline).
deployment_env_resolved() { # <deployment> <env name>
  local v secret key
  v="$(deployment_env "$1" "$2")"
  if [ -n "$v" ]; then printf '%s' "$v"; return 0; fi
  secret="$(deployment_env_secret_ref "$1" "$2")"
  key="$(kubectl get deployment "$1" -n "$NAMESPACE" -o "jsonpath={.spec.template.spec.containers[0].env[?(@.name==\"$2\")].valueFrom.secretKeyRef.key}")"
  [ -n "$secret" ] && [ -n "$key" ] || return 0
  kubectl get secret "$secret" -n "$NAMESPACE" -o "jsonpath={.data.$key}" | base64 --decode
}
deployment_env_secret_ref() { kubectl get deployment "$1" -n "$NAMESPACE" -o "jsonpath={.spec.template.spec.containers[0].env[?(@.name==\"$2\")].valueFrom.secretKeyRef.name}"; }
deployment_image() { kubectl get deployment "$1" -n "$NAMESPACE" -o 'jsonpath={.spec.template.spec.containers[0].image}'; }
deployment_replicas() { kubectl get deployment "$1" -n "$NAMESPACE" -o 'jsonpath={.spec.replicas}'; }
count_pods() { kubectl get pods -n "$NAMESPACE" -l 'app in (rellm,rellm-jobs,rellm-preview-generator)' -o name 2>/dev/null | wc -l | tr -d ' '; }


# name=rowcount for every public table, sorted -- run against both source and target and diffed.
table_counts() { # <namespace> <pod> <database>
  kubectl exec -i -n "$1" "$2" -- psql -U admin -d "$3" -tA -v ON_ERROR_STOP=1 <<'SQL'
SELECT table_name || '=' || (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text
FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY table_name;
SQL
}

# Starts `kubectl port-forward` to <namespace>/<pod> on a kernel-chosen FREE local port (the
# ":<remote>" form), so any number of copies of this script can run at once without fighting over
# ports, and leaves that port in PF_LAST_PORT. An explicit 4th argument pins the local port instead.
start_port_forward() { # <namespace> <pod> <remote-port> [fixed-local-port]
  local log; log="$(mktemp "$STATE_DIR/pf.XXXXXX")"
  kubectl port-forward -n "$1" "pod/$2" "${4:-}:$3" >"$log" 2>&1 &
  PF_PIDS="$PF_PIDS $!"
  local i
  PF_LAST_PORT=""
  for i in $(seq 1 20); do
    PF_LAST_PORT="$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9][0-9]*\) ->.*/\1/p' "$log" 2>/dev/null | head -1)"
    [ -z "$PF_LAST_PORT" ] || return 0
    sleep 1
  done
  cat "$log" >&2
  die "port-forward to $1/$2 never came up"
}

# (Re)establishes both object storage port-forwards from scratch. `kubectl port-forward` tunnels
# drop during long transfers (a ~1GB copy is plenty of time), so the copy/verify steps reconnect
# rather than trusting a tunnel started minutes ago.
restart_object_storage_port_forwards() {
  local pid
  for pid in $PF_PIDS; do { kill "$pid" && wait "$pid"; } 2>/dev/null || true; done
  PF_PIDS=""
  start_port_forward "$NAMESPACE" rellm-object-storage-0 9000; SRC_PORT="$PF_LAST_PORT"
  start_port_forward "$STORAGE_NAMESPACE" rellm-central-object-storage-0 9000; DST_PORT="$PF_LAST_PORT"
  # Ports differ on every (re)connect, so the mc aliases are re-exported here each time.
  export MC_HOST_src="http://$SRC_ACCESS_KEY:$SRC_SECRET_KEY@127.0.0.1:$SRC_PORT"
  export MC_HOST_dst="http://$DST_ROOT_USER:$DST_ROOT_PASSWORD@127.0.0.1:$DST_PORT"
}

# `mc mirror` is incremental (already-copied objects are skipped), so when a tunnel drops
# mid-copy we just reconnect and run it again.
mirror_until_done() {
  local attempt
  for attempt in 1 2 3 4 5 6; do
    restart_object_storage_port_forwards
    if mc mirror --overwrite "src/$SRC_BUCKET" "dst/$NAMESPACE"; then return 0; fi
    info "Mirror attempt $attempt of 6 failed (usually a dropped kubectl port-forward) -- reconnecting and resuming..."
    sleep 3
  done
  return 1
}

# ---------------------------------------------------------------------------
step "Preflight checks (nothing is modified yet)"
for cmd in kubectl mc make sed grep; do
  command -v "$cmd" >/dev/null || die "'$cmd' is required but not installed$([ "$cmd" = mc ] && echo ' -- brew install minio/stable/mc')"
done
[ -f "$DEPLOYS_DIR/k8s/server_internal_central_data.yaml" ] && [ -f "$DEPLOYS_DIR/k8s/preview_generator_central_data.yaml" ] \
  || die "k8s/server_internal_central_data.yaml / preview_generator_central_data.yaml not found next to this script"

CONTEXT="$(kubectl config current-context)"
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || die "Namespace '$NAMESPACE' doesn't exist in cluster context '$CONTEXT'"
kubectl get namespace "$STORAGE_NAMESPACE" >/dev/null 2>&1 || die "Central storage namespace '$STORAGE_NAMESPACE' doesn't exist -- run: make -C central_storage create_central_storage"
deployment_exists rellm || die "No 'rellm' Deployment in $NAMESPACE -- nothing to transition"

[ "$(deployment_env_secret_ref rellm DATABASE_URL)" != "rellm-central-data" ] \
  || die "'$NAMESPACE' rellm's DATABASE_URL already comes from the rellm-central-data Secret -- already transitioned?"
LIVE_DB_URL="$(deployment_env rellm DATABASE_URL)"
LIVE_ENDPOINT="$(deployment_env rellm OBJECT_STORAGE_ENDPOINT)"
SRC_BUCKET="$(deployment_env rellm OBJECT_STORAGE_BUCKET)"
SRC_ACCESS_KEY="$(deployment_env_resolved rellm OBJECT_STORAGE_ACCESS_KEY)"
SRC_SECRET_KEY="$(deployment_env_resolved rellm OBJECT_STORAGE_SECRET_KEY)"
[ -n "$SRC_ACCESS_KEY" ] && [ -n "$SRC_SECRET_KEY" ] || die "Couldn't determine the source object storage credentials from the live rellm Deployment"
case "$LIVE_DB_URL" in
  *@rellm-central-postgres*) die "'$NAMESPACE' already points at the central Postgres ($LIVE_DB_URL) -- already transitioned?" ;;
  *@rellm-postgres/*) ;;
  *) die "'$NAMESPACE' rellm DATABASE_URL is '$LIVE_DB_URL' -- this script only handles namespaces using their own in-namespace rellm-postgres" ;;
esac
[ "$LIVE_ENDPOINT" = "http://rellm-object-storage:9000" ] \
  || die "'$NAMESPACE' OBJECT_STORAGE_ENDPOINT is '$LIVE_ENDPOINT' -- this script only handles namespaces using their own in-namespace rellm-object-storage"
SRC_DB="${LIVE_DB_URL##*/}"; SRC_DB="${SRC_DB%%\?*}"
[ -n "$SRC_DB" ] && [ -n "$SRC_BUCKET" ] || die "Couldn't determine source database ('$SRC_DB') / bucket ('$SRC_BUCKET') from the live Deployment"
valid_ns "$SRC_DB" 2>/dev/null || printf '%s' "$SRC_DB" | grep -Eq '^[A-Za-z0-9_-]+$' || die "Unexpected source database name '$SRC_DB'"

kubectl wait --for=condition=ready pod/rellm-postgres-0 -n "$NAMESPACE" --timeout=30s >/dev/null || die "Source rellm-postgres-0 isn't ready in $NAMESPACE"
kubectl wait --for=condition=ready pod/rellm-object-storage-0 -n "$NAMESPACE" --timeout=30s >/dev/null || die "Source rellm-object-storage-0 isn't ready in $NAMESPACE"
kubectl wait --for=condition=ready pod/rellm-central-postgres-0 -n "$STORAGE_NAMESPACE" --timeout=30s >/dev/null || die "rellm-central-postgres-0 isn't ready in $STORAGE_NAMESPACE"
kubectl wait --for=condition=ready pod/rellm-central-object-storage-0 -n "$STORAGE_NAMESPACE" --timeout=30s >/dev/null || die "rellm-central-object-storage-0 isn't ready in $STORAGE_NAMESPACE"

# Validates names/tools, that central storage is healthy and that nothing already exists for this
# namespace (unless --reset-target) -- all BEFORE any downtime.
PROVISION_ARGS=""; [ "$RESET_TARGET" = true ] && PROVISION_ARGS="--reset"
"$PROVISION" --check $PROVISION_ARGS "$NAMESPACE" || die "Central storage preflight failed (see above); nothing was changed"

for d in $DEPLOYMENTS; do
  if deployment_exists "$d"; then
    replicas="$(deployment_replicas "$d")"
    echo "$replicas" > "$STATE_DIR/replicas.$d"
    deployment_image "$d" > "$STATE_DIR/image.$d"
  fi
done

echo
echo "   Cluster context:   $CONTEXT"
echo "   Namespace:         $NAMESPACE   (site will be DOWN until step 4 completes)"
echo "   Source:            rellm-postgres db '$SRC_DB' + rellm-object-storage bucket '$SRC_BUCKET' (left untouched)"
echo "   Destination:       $STORAGE_NAMESPACE: rellm-central-postgres db+role '$NAMESPACE' + rellm-central-object-storage bucket+user '$NAMESPACE' (new random credentials -> Secret $NAMESPACE/rellm-central-data)"
[ "$RESET_TARGET" = true ] && echo "   --reset-target:    any existing central database/role/user/Secret for '$NAMESPACE' WILL BE DROPPED first"
for d in $DEPLOYMENTS; do [ -f "$STATE_DIR/image.$d" ] && echo "   Deployment $d: $(cat "$STATE_DIR/replicas.$d") replica(s), image $(cat "$STATE_DIR/image.$d")"; done
if [ "$YES" = false ]; then
  [ -t 0 ] || die "Not a terminal -- pass --yes to run non-interactively"
  printf '\n   Type the namespace name (%s) to proceed: ' "$NAMESPACE"
  read -r answer
  [ "$answer" = "$NAMESPACE" ] || die "Confirmation didn't match -- aborting, nothing was changed"
fi

# ---------------------------------------------------------------------------
step "1. Take down rellm / rellm-jobs / rellm-preview-generator (site is now OUT)"
DOWNTIME_STARTED=true
for d in $DEPLOYMENTS; do
  deployment_exists "$d" && kubectl scale deployment "$d" --replicas=0 -n "$NAMESPACE"
done
for i in $(seq 1 60); do
  [ "$(count_pods)" = "0" ] && break
  sleep 2
done
[ "$(count_pods)" = "0" ] || die "Pods for $DEPLOYMENTS are still running after 2 minutes -- not copying data while something might still write to it"
info "All rellm pods in $NAMESPACE are gone; nothing can write to the old Postgres/bucket now."

# ---------------------------------------------------------------------------
step "2a. Provision '$NAMESPACE' in central storage (database+role, bucket+user, credentials Secret)"
"$PROVISION" $PROVISION_ARGS "$NAMESPACE"

step "2b. Copy Postgres data ('$SRC_DB' -> central '$NAMESPACE') via pg_dump | psql"
kubectl exec -n "$NAMESPACE" rellm-postgres-0 -- pg_dump -U admin -d "$SRC_DB" --no-owner --no-acl \
  | kubectl exec -i -n "$STORAGE_NAMESPACE" rellm-central-postgres-0 -- psql -U "$NAMESPACE" -d "$NAMESPACE" -q --single-transaction -v ON_ERROR_STOP=1

step "2c. Verify Postgres copy (per-table row counts, source vs. central)"
SRC_COUNTS="$(table_counts "$NAMESPACE" rellm-postgres-0 "$SRC_DB")"
DST_COUNTS="$(table_counts "$STORAGE_NAMESPACE" rellm-central-postgres-0 "$NAMESPACE")"
[ -n "$SRC_COUNTS" ] || die "Source database '$SRC_DB' has no tables -- unexpected, refusing to continue"
if [ "$SRC_COUNTS" != "$DST_COUNTS" ]; then
  echo "--- source" >&2; echo "$SRC_COUNTS" >&2; echo "--- central" >&2; echo "$DST_COUNTS" >&2
  die "Row counts differ between source and central databases (see above)"
fi
info "$(echo "$SRC_COUNTS" | wc -l | tr -d ' ') tables, all row counts identical."

step "2d. Copy object storage ('$SRC_BUCKET' -> central '$NAMESPACE') via mc mirror"
# Destination uses the central instance's root credentials (from its Secret) for the copy; the
# namespace's own restricted user is what the running site will use.
DST_ROOT_USER="$(kubectl get secret rellm-central-object-storage-credentials -n "$STORAGE_NAMESPACE" -o jsonpath='{.data.root-user}' | base64 --decode)"
DST_ROOT_PASSWORD="$(kubectl get secret rellm-central-object-storage-credentials -n "$STORAGE_NAMESPACE" -o jsonpath='{.data.root-password}' | base64 --decode)"
restart_object_storage_port_forwards
if mc ls "src/$SRC_BUCKET" >/dev/null 2>&1; then
  mc mb --ignore-existing "dst/$NAMESPACE"
  info "Mirroring (can take a while depending on how much media there is; safe to re-run -- it's incremental)..."
  mirror_until_done || die "Object storage copy still failing after 6 reconnects. The site is still down; re-run this script with --reset-target (the copy resumes where it left off)."

  step "2e. Verify object storage copy (mc diff + total size/object count)"
  restart_object_storage_port_forwards
  DIFF_OUTPUT="$(mc diff "src/$SRC_BUCKET" "dst/$NAMESPACE" || true)"
  if [ -n "$DIFF_OUTPUT" ]; then
    echo "$DIFF_OUTPUT" >&2
    die "Bucket verification found differences (see above)"
  fi
  # `mc diff ... || true` above can't tell "identical" from "couldn't connect", so also require
  # both sides to report (successfully) the same total size and object count.
  SRC_DU="$(mc du "src/$SRC_BUCKET")" || die "Couldn't measure the source bucket for verification"
  DST_DU="$(mc du "dst/$NAMESPACE")" || die "Couldn't measure the central bucket for verification"
  [ "$(echo "$SRC_DU" | awk '{print $1, $2}')" = "$(echo "$DST_DU" | awk '{print $1, $2}')" ] \
    || die "Source and central buckets differ in total size/object count: source '$SRC_DU' vs central '$DST_DU'"
  info "$(mc ls --recursive "dst/$NAMESPACE" | wc -l | tr -d ' ') object(s) in central bucket '$NAMESPACE'; identical to source."
else
  info "Source bucket '$SRC_BUCKET' doesn't exist (no media ever uploaded) -- creating an empty '$NAMESPACE' bucket instead."
  mc mb --ignore-existing "dst/$NAMESPACE"
fi
for pid in $PF_PIDS; do { kill "$pid" && wait "$pid"; } 2>/dev/null || true; done
PF_PIDS=""

# ---------------------------------------------------------------------------
step "3. Apply server_internal_central_data.yaml + preview_generator_central_data.yaml to $NAMESPACE"
SERVER_YAML="$DEPLOYS_DIR/k8s/server_internal_central_data.$NAMESPACE.generated.yaml"
PREVIEW_YAML="$DEPLOYS_DIR/k8s/preview_generator_central_data.$NAMESPACE.generated.yaml"
rm -f "$SERVER_YAML" "$PREVIEW_YAML"
(cd "$DEPLOYS_DIR" && make --no-print-directory \
  "k8s/server_internal_central_data.$NAMESPACE.generated.yaml" \
  "k8s/preview_generator_central_data.$NAMESPACE.generated.yaml" \
  NAMESPACE="$NAMESPACE" STORAGE_NAMESPACE="$STORAGE_NAMESPACE")

if [ "$REPO_IMAGES" = false ]; then
  if [ -f "$STATE_DIR/image.rellm" ]; then
    LIVE_IMAGE="$(cat "$STATE_DIR/image.rellm")"
    sed -E "s#(image: )docker\.io/jonlatane/rellm:[^ ]+#\1$LIVE_IMAGE#" "$SERVER_YAML" > "$SERVER_YAML.tmp" && mv "$SERVER_YAML.tmp" "$SERVER_YAML"
    info "Preserving live server image: $LIVE_IMAGE"
  fi
  if [ -f "$STATE_DIR/image.rellm-preview-generator" ]; then
    LIVE_PREVIEW_IMAGE="$(cat "$STATE_DIR/image.rellm-preview-generator")"
    sed -E "s#(image: )docker\.io/jonlatane/rellm_preview_generator:[^ ]+#\1$LIVE_PREVIEW_IMAGE#" "$PREVIEW_YAML" > "$PREVIEW_YAML.tmp" && mv "$PREVIEW_YAML.tmp" "$PREVIEW_YAML"
    info "Preserving live preview generator image: $LIVE_PREVIEW_IMAGE"
  fi
fi

kubectl apply -f "$SERVER_YAML" -n "$NAMESPACE"
kubectl apply -f "$PREVIEW_YAML" -n "$NAMESPACE"
APPLIED=true

# ---------------------------------------------------------------------------
step "4. Make sure services are back up"
for d in $DEPLOYMENTS; do
  if [ "$(deployment_replicas "$d")" = "0" ]; then
    original="$(cat "$STATE_DIR/replicas.$d" 2>/dev/null || echo 0)"
    [ "$original" != "0" ] || { [ "$d" = rellm ] && original=2 || original=1; }
    info "$d is still at 0 replicas after apply -- scaling to $original"
    kubectl scale deployment "$d" --replicas="$original" -n "$NAMESPACE"
  fi
done
for d in $DEPLOYMENTS; do
  kubectl rollout status "deployment/$d" -n "$NAMESPACE" --timeout 3m
done
info "Watching for crash loops for 20s (the server tests its DB/bucket connections at startup)..."
sleep 20
BAD_PODS="$(kubectl get pods -n "$NAMESPACE" -l 'app in (rellm,rellm-jobs,rellm-preview-generator)' \
  -o 'jsonpath={range .items[*]}{.metadata.name}{" "}{.status.phase}{" restarts="}{.status.containerStatuses[0].restartCount}{"\n"}{end}' \
  | grep -v ' Running restarts=0$' || true)"
if [ -n "$BAD_PODS" ]; then
  echo "$BAD_PODS" >&2
  echo "--- rellm logs:" >&2
  kubectl logs deployment/rellm -n "$NAMESPACE" --tail=30 >&2 || true
  die "Some pods aren't Running with 0 restarts (see above)"
fi
info "All pods Running, 0 restarts."

# ---------------------------------------------------------------------------
if [ "$BOUNCE_TRAEFIK" = true ] && kubectl get deployment traefik -n traefik-ingress >/dev/null 2>&1; then
  step "5. Bounce Traefik (briefly interrupts every domain behind it)"
  kubectl rollout restart deployment traefik -n traefik-ingress
  kubectl rollout status deployment traefik -n traefik-ingress --timeout 3m
else
  step "5. Bounce Traefik -- skipped"
fi

trap - ERR
echo
echo "=== Done: $NAMESPACE now runs against $STORAGE_NAMESPACE's central Postgres/object storage. ==="
echo "  Spot check the site now. The OLD rellm-postgres/rellm-object-storage (and their PVCs) in $NAMESPACE"
echo "  are untouched and still running. Once you're happy:"
echo "    NAMESPACE=$NAMESPACE CONFIRM=$NAMESPACE make delete_backend_data_pvcs"
echo "  Before the next deploy to this namespace, make sure CI applies the central-data manifests"
echo "  (not server_internal.yaml) or it will point the site back at the old storage."
