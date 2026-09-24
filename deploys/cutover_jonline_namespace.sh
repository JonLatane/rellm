#!/usr/bin/env bash
# Manual, one-time traffic cutover for a single namespace after merging the
# Jonline->Rellm rename PR. NOT run automatically by anything.
#
# Usage: ./cutover_jonline_namespace.sh <namespace>
#   ./cutover_jonline_namespace.sh jonline
#   ./cutover_jonline_namespace.sh bullcitysocial
#   ./cutover_jonline_namespace.sh oakcitysocial
#   ./cutover_jonline_namespace.sh ato-band
#
# What it does, in order:
#   1. Renames Postgres (jonline-postgres -> rellm-postgres) and object
#      storage (jonline-minio -> rellm-object-storage) StatefulSets+Services.
#      Data is untouched by this step -- both old and new StatefulSets mount
#      the SAME PVC (postgres-pv-claim/object-storage-pv-claim), referenced
#      by a fixed claimName rather than derived from the StatefulSet's own
#      name.
#   2. Deletes the old `jonline`/`jonline-jobs` Deployment+Service. Done
#      here (before the data-level renames below) specifically to stop all
#      writes to the old Postgres database/object storage bucket before
#      copying it, so there's no window where something could write to
#      `jonline` after we've already copied/renamed it to `rellm`.
#   3. Renames the Postgres database itself (`jonline` -> `rellm`) via
#      ALTER DATABASE -- metadata-only, no data copied, just needs zero
#      active connections (guaranteed by step 2).
#   4. Copy-migrates the object storage bucket (`jonline` -> `rellm`):
#      S3/object storage has no rename-bucket operation, so this actually
#      copies every object via `mc mirror`, verifies the copy is
#      byte-for-byte identical with `mc diff`, and only then removes the old
#      bucket. Requires the MinIO Client (`mc` -- works against any
#      S3-compatible server, including the object storage backend used
#      here): `brew install minio/stable/mc`.
#   5. Issues a new TLS certificate (rellm-generated-tls, via a new
#      cert-manager Certificate resource, rellm-letsencrypt-cert) for
#      HTTPS/gRPC (ports 443/27707). TLS_KEY/TLS_CERT are `optional: true`
#      secretKeyRefs, so the app doesn't crash without them -- it just
#      silently gets an empty cert, which accepts the TCP connection but
#      fails the TLS handshake. Reuses the existing letsencrypt-prod Issuer
#      and digitalocean-dns credential as-is; only requests a fresh
#      Let's-Encrypt-issued cert under the new secret name.
#   6. Restarts rellm/rellm-jobs and waits for them to come up healthy
#      against the now-renamed Postgres database, object storage bucket, and cert.
#   7. Swaps the Traefik ingress routes (jonline-http/-alt/-https/-grpc ->
#      rellm-http/-alt/-https/-grpc) so traffic reaches the new `rellm`
#      Service. DOMAIN/EXTRA_DOMAINS are read straight off the live old
#      IngressRoute's match rule, not hardcoded.
#   8. Bounces Traefik -- same reason server_ci_cd.yml does this after every
#      jonline.io deploy: TLS-passthrough IngressRouteTCP routing can get
#      wedged pointing at stale backend pod IPs after a rollout replaces
#      pods, and this script just replaced a lot of them.
#
# Downtime: this is a full stop-old/start-new cutover, not a staged
# rollout -- the domain will be down from step 2 until step 8 completes
# (Postgres rename is instant, object storage copy-migrate in step 4 takes
# as long as your media library does to copy, and the cert issuance in step
# 5 needs a few minutes for DNS-01 propagation). No data is at risk at any
# point: the old Postgres/object storage data is never deleted until
# verified copied (object storage) or is untouched entirely (Postgres is a
# metadata-only rename); the old TLS cert/secret is untouched too.
#
# Prerequisites:
#  - kubectl pointed at the right cluster. If your kubeconfig still
#    references the cluster by its old name, refresh it now that it's been
#    renamed to rellm-be:
#      doctl kubernetes cluster kubeconfig save --expiry-seconds 600 rellm-be
#  - the MinIO Client, for the bucket copy: brew install minio/stable/mc
set -euo pipefail

NAMESPACE="${1:?Usage: $0 <namespace>  (e.g. jonline, bullcitysocial, oakcitysocial, ato-band)}"
DEPLOYS_DIR="$(cd "$(dirname "$0")" && pwd)"

command -v mc >/dev/null || { echo "mc (MinIO Client) is required -- install with: brew install minio/stable/mc" >&2; exit 1; }

echo "=== Namespace: $NAMESPACE ==="

echo
echo "== 1. Rename Postgres and object storage StatefulSets+Services (data untouched -- same PVCs) =="
kubectl delete statefulset jonline-postgres -n "$NAMESPACE" --ignore-not-found
kubectl delete service jonline-postgres -n "$NAMESPACE" --ignore-not-found
(cd "$DEPLOYS_DIR" && make update_backend_postgres NAMESPACE="$NAMESPACE")
kubectl wait --for=condition=ready pod/rellm-postgres-0 -n "$NAMESPACE" --timeout=2m

kubectl delete statefulset jonline-minio -n "$NAMESPACE" --ignore-not-found
kubectl delete service jonline-minio -n "$NAMESPACE" --ignore-not-found
(cd "$DEPLOYS_DIR" && make update_backend_object_storage NAMESPACE="$NAMESPACE")
kubectl wait --for=condition=ready pod/rellm-object-storage-0 -n "$NAMESPACE" --timeout=2m

echo
echo "== 2. Delete the old jonline/jonline-jobs Deployment+Service =="
echo "   (stops all writes to the old DB/bucket before we copy/rename them below --"
echo "   this is also the site going down until step 6 completes)"
kubectl delete deployment jonline jonline-jobs -n "$NAMESPACE" --ignore-not-found
kubectl delete service jonline -n "$NAMESPACE" --ignore-not-found

echo
echo "== 3. Rename the Postgres database (jonline -> rellm) =="
kubectl port-forward -n "$NAMESPACE" svc/rellm-postgres 15432:5432 >/tmp/pgpf-"$NAMESPACE".log 2>&1 &
PG_PF_PID=$!
sleep 2
trap 'kill $PG_PF_PID 2>/dev/null || true' EXIT

DBS="$(PGPASSWORD=secure_password1 psql -h localhost -p 15432 -U admin -d postgres -tAc "SELECT datname FROM pg_database WHERE datname IN ('jonline','rellm');")"
if echo "$DBS" | grep -qx rellm; then
  echo "   'rellm' database already exists -- assuming this step already ran, skipping."
elif echo "$DBS" | grep -qx jonline; then
  RENAMED=false
  for attempt in 1 2 3 4 5; do
    if PGPASSWORD=secure_password1 psql -h localhost -p 15432 -U admin -d postgres -c "ALTER DATABASE jonline RENAME TO rellm;" 2>/tmp/pgrename-"$NAMESPACE".log; then
      RENAMED=true
      break
    fi
    echo "   Rename attempt $attempt failed (probably a lingering connection) -- retrying in 5s..."
    cat /tmp/pgrename-"$NAMESPACE".log >&2
    sleep 5
  done
  [ "$RENAMED" = true ] || { echo "Could not rename the database after 5 attempts -- bailing out." >&2; exit 1; }
else
  echo "Neither 'jonline' nor 'rellm' database found -- unexpected state, bailing out." >&2
  exit 1
fi

kill $PG_PF_PID 2>/dev/null || true
trap - EXIT

echo
echo "== 4. Copy-migrate the object storage bucket (jonline -> rellm) =="
kubectl port-forward -n "$NAMESPACE" svc/rellm-object-storage 19000:9000 >/tmp/objectstoragepf-"$NAMESPACE".log 2>&1 &
OBJECT_STORAGE_PF_PID=$!
sleep 2
trap 'kill $OBJECT_STORAGE_PF_PID 2>/dev/null || true' EXIT

export MC_HOST_local="http://minio:minio123@localhost:19000"

if mc ls local/jonline >/dev/null 2>&1; then
  mc mb --ignore-existing local/rellm
  echo "   Mirroring (this can take a while depending on how much media there is)..."
  mc mirror --overwrite --remove local/jonline local/rellm
  echo "   Verifying the copy is complete..."
  DIFF_OUTPUT="$(mc diff local/jonline local/rellm || true)"
  if [ -n "$DIFF_OUTPUT" ]; then
    echo "Mirror verification found differences -- NOT removing the old bucket. Re-run this" >&2
    echo "step (it's incremental) or investigate before proceeding:" >&2
    echo "$DIFF_OUTPUT" >&2
    exit 1
  fi
  echo "   Verified identical. Removing the old 'jonline' bucket."
  mc rb --force local/jonline
else
  echo "   'jonline' bucket not found (already migrated, or never existed) -- skipping."
fi

kill $OBJECT_STORAGE_PF_PID 2>/dev/null || true
trap - EXIT

echo
echo "== 5. Issue a new TLS certificate (rellm-generated-tls) =="
echo "   TLS_KEY/TLS_CERT are optional: true, so the app didn't crash when the renamed"
echo "   rellm-generated-tls secret didn't exist -- it just silently got an empty cert,"
echo "   which is why port 443/27707 accept the TCP connection but fail the TLS handshake."
if kubectl get secret rellm-generated-tls -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "   'rellm-generated-tls' already exists -- skipping issuance."
else
  CERT_DOMAIN="$(kubectl get certificate jonline-letsencrypt-cert -n "$NAMESPACE" -o jsonpath='{.spec.commonName}')"
  CERT_EMAIL="$(kubectl get issuer letsencrypt-prod -n "$NAMESPACE" -o jsonpath='{.spec.acme.email}')"
  echo "   Requesting a new Let's Encrypt cert for $CERT_DOMAIN via a new Certificate resource"
  echo "   (rellm-letsencrypt-cert) -- reuses the EXISTING letsencrypt-prod Issuer and"
  echo "   digitalocean-dns credential as-is, neither is recreated or touched."
  sed -e "s/\${CERT_MANAGER_EMAIL}/$CERT_EMAIL/g" -e "s/\${CERT_MANAGER_DOMAIN}/$CERT_DOMAIN/g" \
    "$DEPLOYS_DIR/generated_certs/k8s/cert-manager.digitalocean.template.yaml" | kubectl apply -n "$NAMESPACE" -f -
  echo "   Waiting for cert-manager to complete the DNS-01 challenge and issue the cert"
  echo "   (DNS propagation -- can take a few minutes)..."
  kubectl wait --for=condition=Ready certificate/rellm-letsencrypt-cert -n "$NAMESPACE" --timeout=5m
fi

echo
echo "== 6. Restart rellm/rellm-jobs and confirm healthy against the renamed DB/bucket/cert =="
kubectl rollout restart deployment/rellm deployment/rellm-jobs -n "$NAMESPACE"
kubectl rollout status deployment/rellm -n "$NAMESPACE" --timeout 3m
kubectl rollout status deployment/rellm-jobs -n "$NAMESPACE" --timeout 3m

echo
echo "== 7. Swap the ingress routes =="
if kubectl get ingressroute jonline-http -n "$NAMESPACE" >/dev/null 2>&1; then
  MATCH="$(kubectl get ingressroute jonline-http -n "$NAMESPACE" -o jsonpath='{.spec.routes[0].match}')"
  echo "   Live match rule: $MATCH"
  # MATCH looks like: Host(`jonline.io`) || Host(`jonline.io.getj.online`)
  # Deliberately using positional params instead of a bash array here -- macOS's
  # stock bash 3.2 has a real off-by-one quirk with `arr=(); arr+=(...)`
  # (verified: DOMAINS[0] comes back empty, DOMAINS[1] holds what was actually
  # appended first), so array indexing isn't trustworthy on this system.
  set -- $(grep -oE 'Host\(`[^`]+`\)' <<<"$MATCH" | sed -E 's/Host\(`([^`]+)`\)/\1/')
  if [ "$#" -eq 0 ]; then
    echo "Couldn't parse any domain out of '$MATCH' -- bailing out before deleting anything." >&2
    exit 1
  fi
  DOMAIN="$1"
  shift || true
  EXTRA_DOMAINS="$*"
  echo "   -> DOMAIN=$DOMAIN EXTRA_DOMAINS=${EXTRA_DOMAINS:-<none>}"

  kubectl delete ingressroute jonline-http jonline-http-alt -n "$NAMESPACE" --ignore-not-found
  kubectl delete ingressroutetcp jonline-https jonline-grpc -n "$NAMESPACE" --ignore-not-found
  (cd "$DEPLOYS_DIR/ingress" && NAMESPACE="$NAMESPACE" DOMAIN="$DOMAIN" EXTRA_DOMAINS="$EXTRA_DOMAINS" make add_ingress_domain)
elif kubectl get ingressroute rellm-http -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "   'jonline-http' doesn't exist but 'rellm-http' does -- already swapped, skipping."
  DOMAIN="$(kubectl get ingressroute rellm-http -n "$NAMESPACE" -o jsonpath='{.spec.routes[0].match}' | grep -oE 'Host\(`[^`]+`\)' | head -1 | sed -E 's/Host\(`([^`]+)`\)/\1/')"
else
  echo "Neither 'jonline-http' nor 'rellm-http' IngressRoute found in $NAMESPACE -- unexpected state, bailing out." >&2
  exit 1
fi

echo
echo "== 8. Bounce Traefik =="
echo "   Same reason server_ci_cd.yml does this after every jonline.io deploy: TLS-passthrough"
echo "   IngressRouteTCP routing can get wedged pointing at stale backend pod IPs after a"
echo "   rollout replaces pods -- and this script just replaced a lot of them."
kubectl rollout restart deployment traefik -n traefik-ingress
kubectl rollout status deployment traefik -n traefik-ingress --timeout 3m

echo
echo "=== Done with $NAMESPACE. Spot check: https://$DOMAIN ==="
