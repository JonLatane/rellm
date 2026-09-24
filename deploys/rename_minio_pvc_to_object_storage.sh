#!/usr/bin/env bash
# ============================================================================
# ONE-TIME, PER-NAMESPACE, MANUAL cutover script. NOT run automatically by
# anything -- not a `make` target, not wired into CI, not invoked by any
# other script in this repo. Run it by hand, once, per already-deployed
# namespace (jonline.io, rellm.org, ato-band, etc.), and only after the
# renamed manifests (k8s-object-storage-digitalocean.yaml,
# k8s-object-storage-pvc-digitalocean.yaml, server_external.yaml & co.) have
# otherwise already been applied to your cluster via the normal `make`
# targets/CI deploy.
#
# What/why:
#   The MinIO-to-object-storage rename renamed the object storage PVC from
#   `minio-pv-claim` to `object-storage-pv-claim`. Kubernetes PVC identity
#   IS its name -- a PVC isn't renamed by relabeling, it's a brand-new
#   object. So simply deploying the renamed manifests to an
#   ALREADY-DEPLOYED namespace would provision a new, empty
#   `object-storage-pv-claim` and silently orphan the real media data still
#   sitting on the old `minio-pv-claim` -> PV. This script performs the
#   safe, zero-data-copy rebind instead: it releases the underlying PV from
#   the old PVC and re-binds that SAME PV (by name) to a new PVC named
#   `object-storage-pv-claim`, so no bytes move and no bucket copy is
#   needed (contrast this with the jonline->rellm namespace rename, which
#   genuinely had to `mc mirror` an S3 bucket -- see
#   cutover_jonline_namespace.sh -- because that rename changed data
#   ownership, not just a PVC's own name).
#
#   This is only possible because `deploys/k8s/storageclass-retain-*.yaml`
#   sets `reclaimPolicy: Retain` on the StorageClass -- deleting a PVC bound
#   via a Retain-policy StorageClass leaves the underlying PV (and its data)
#   fully intact, just unbound ("Released"), rather than deleting it. This
#   script patches that PV's `claimRef` back to null (making it "Available"
#   again) and then creates a new PVC that pins `spec.volumeName` to that
#   exact PV, which forces Kubernetes to bind them back together instead of
#   provisioning a new empty volume.
#
# Prerequisites:
#  - kubectl pointed at the right cluster/context.
#  - The renamed k8s-object-storage-*.yaml manifests (this script's sibling
#    files under k8s/) must already reflect what you want deployed -- this
#    script reads k8s/k8s-object-storage-pvc-digitalocean.yaml directly to
#    build the temporary PVC manifest in step 4, so it stays in sync with
#    that file's labels/storageClassName/size automatically.
#  - Expect a brief object storage outage across steps 1-5 (the StatefulSet
#    is down from step 1 until step 5 brings the new one up) -- Postgres
#    and the main `rellm`/`rellm-jobs` Deployments are untouched throughout,
#    so the rest of the site keeps serving; only object storage reads/writes
#    (media upload/download, avatar/preview images, inbound email .eml
#    storage) are affected for that window.
#
# Usage:
#   ./rename_minio_pvc_to_object_storage.sh <namespace>
#   NAMESPACE=jonline ./rename_minio_pvc_to_object_storage.sh
# ============================================================================
set -euo pipefail

NAMESPACE="${1:-${NAMESPACE:?Usage: $0 <namespace>  (e.g. jonline, bullcitysocial, oakcitysocial, ato-band)}}"
DEPLOYS_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Namespace: $NAMESPACE ==="

echo
echo "== 1. Check current state =="
if kubectl get pvc object-storage-pv-claim -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "   'object-storage-pv-claim' already exists in $NAMESPACE -- assuming this cutover"
  echo "   already ran. Nothing to do. (If you actually want to re-run it, delete that PVC"
  echo "   first and re-check the old 'minio-pv-claim'/PV state by hand before retrying.)"
  exit 0
fi

if ! kubectl get pvc minio-pv-claim -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "Neither 'object-storage-pv-claim' nor 'minio-pv-claim' found in $NAMESPACE -- unexpected state, bailing out." >&2
  exit 1
fi

PV_NAME="$(kubectl get pvc minio-pv-claim -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')"
if [ -z "$PV_NAME" ]; then
  echo "Couldn't resolve the PV bound to 'minio-pv-claim' in $NAMESPACE -- bailing out before deleting anything." >&2
  exit 1
fi
echo "   'minio-pv-claim' is bound to PV: $PV_NAME"

echo
echo "== 2. Delete the old object storage Service+StatefulSet (if not already gone) =="
echo "   (deleted by name, not by -f k8s/k8s-minio-*.yaml -- those files no longer exist in"
echo "   this repo post-rename; deleting by name has the same effect)"
kubectl delete statefulset rellm-minio -n "$NAMESPACE" --ignore-not-found
kubectl delete service rellm-minio -n "$NAMESPACE" --ignore-not-found

echo
echo "== 3. Delete the old 'minio-pv-claim' PVC (PV survives -- reclaimPolicy: Retain) =="
kubectl delete pvc minio-pv-claim -n "$NAMESPACE"
echo "   Waiting for PV $PV_NAME to show up as Released..."
for i in $(seq 1 30); do
  PHASE="$(kubectl get pv "$PV_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [ "$PHASE" = "Released" ] && break
  sleep 1
done
echo "   PV $PV_NAME phase: ${PHASE:-unknown}"
if [ "${PHASE:-}" != "Released" ]; then
  echo "PV $PV_NAME never reached 'Released' (still: ${PHASE:-unknown}) -- bailing out before touching claimRef." >&2
  exit 1
fi

echo
echo "== 4. Release the PV's claimRef (Released -> Available), then bind it to a new"
echo "   'object-storage-pv-claim' pinned to this exact PV by spec.volumeName =="
kubectl patch pv "$PV_NAME" --type merge -p '{"spec":{"claimRef": null}}'

TMP_PVC_MANIFEST="$(mktemp)"
trap 'rm -f "$TMP_PVC_MANIFEST"' EXIT
# Reads the real, checked-in PVC manifest and injects `volumeName: $PV_NAME` right after its
# `spec:` line -- keeps this script in sync with that file's labels/storageClassName/size
# automatically, instead of duplicating them here. Plain awk (not sed -i) for
# macOS/Linux portability -- BSD and GNU sed's `-i`/`a\` syntax diverge.
awk -v pv="$PV_NAME" '
  /^spec:/ && !done { print; print "  volumeName: " pv; done=1; next }
  { print }
' "$DEPLOYS_DIR/k8s/k8s-object-storage-pvc-digitalocean.yaml" > "$TMP_PVC_MANIFEST"

echo "   Generated temp PVC manifest (pinned to $PV_NAME):"
sed 's/^/   /' "$TMP_PVC_MANIFEST"
kubectl apply -n "$NAMESPACE" -f "$TMP_PVC_MANIFEST"

echo "   Waiting for 'object-storage-pv-claim' to bind..."
for i in $(seq 1 30); do
  BOUND_PHASE="$(kubectl get pvc object-storage-pv-claim -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [ "$BOUND_PHASE" = "Bound" ] && break
  sleep 1
done
if [ "${BOUND_PHASE:-}" != "Bound" ]; then
  echo "'object-storage-pv-claim' never reached Bound (still: ${BOUND_PHASE:-unknown})." >&2
  echo "The PV ($PV_NAME) is currently Available/unbound -- do NOT delete it. Investigate" >&2
  echo "(kubectl describe pvc/pv) before retrying." >&2
  exit 1
fi
BOUND_VOLUME="$(kubectl get pvc object-storage-pv-claim -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')"
if [ "$BOUND_VOLUME" != "$PV_NAME" ]; then
  echo "'object-storage-pv-claim' bound to $BOUND_VOLUME, not the expected $PV_NAME -- this means a" >&2
  echo "NEW empty volume got provisioned instead of reusing the old one. Investigate immediately;" >&2
  echo "your original data is still safe on $PV_NAME (Available/unbound), just not yet reattached." >&2
  exit 1
fi
echo "   Confirmed: 'object-storage-pv-claim' is bound to the original PV ($PV_NAME). No data moved."

echo
echo "== 5. Apply the renamed Service+StatefulSet (k8s-object-storage-digitalocean.yaml) =="
kubectl apply -f "$DEPLOYS_DIR/k8s/k8s-object-storage-digitalocean.yaml" -n "$NAMESPACE"
kubectl wait --for=condition=ready pod/rellm-object-storage-0 -n "$NAMESPACE" --timeout=2m

echo
echo "=== Done with $NAMESPACE. Spot check that existing media/avatars/previews still load,"
echo "    then restart rellm/rellm-jobs if they were up during this window: "
echo "    kubectl rollout restart deployment/rellm deployment/rellm-jobs -n $NAMESPACE ==="
