#!/bin/bash
# The CONFIRM gate on the destructive cluster-wide targets (the ones with no per-site NAMESPACE, which
# `rellm deploy` runs without `-n`): each refuses to touch the cluster unless CONFIRM is the namespace it
# would delete from, same as delete_backend_data_pvcs.
. "$(dirname "$0")/lib.sh"
sandbox_init
begin "CONFIRM gate on cluster-wide deletes"

# check_gated <description> <expected CONFIRM value> <delete command fragment> <make target...>
check_gated() {
  local description="$1" confirm="$2" deletes="$3"
  shift 3
  reset_stub_log
  mk "$@"
  check_nonzero "$description refuses without CONFIRM" "$STATUS"
  check_contains "$description says how to confirm" "$OUT" "CONFIRM=$confirm"
  check_not_contains "$description doesn't touch the cluster without CONFIRM" "$(stub_calls)" "kubectl delete"

  reset_stub_log
  mk "$@" CONFIRM=wrong
  check_nonzero "$description refuses with the wrong CONFIRM" "$STATUS"
  check_not_contains "$description doesn't touch the cluster with the wrong CONFIRM" "$(stub_calls)" "kubectl delete"

  reset_stub_log
  mk "$@" CONFIRM="$confirm"
  check_status "$description runs with CONFIRM=$confirm" 0 "$STATUS"
  check_contains "$description deletes once confirmed" "$(stub_calls)" "$deletes"
}

check_gated "remove_ingress" traefik-ingress "kubectl delete -f k8s/traefik.yaml -n traefik-ingress" remove_ingress
check_gated "deploy_ingress_controller_delete" traefik-ingress "kubectl delete -f k8s/traefik.yaml" deploy_ingress_controller_delete
check_gated "remove_email" rellm-email "kubectl delete -f k8s/stalwart.yaml -n rellm-email" remove_email
check_gated "delete_central_storage" rellm-storage "-n rellm-storage" delete_central_storage

# The confirmation names the namespace actually in use, not a hard-coded one.
reset_stub_log
mk remove_ingress INGRESS_NAMESPACE=elsewhere CONFIRM=traefik-ingress
check_nonzero "remove_ingress with a custom INGRESS_NAMESPACE wants that namespace as CONFIRM" "$STATUS"
mk remove_ingress INGRESS_NAMESPACE=elsewhere CONFIRM=elsewhere
check_status "remove_ingress INGRESS_NAMESPACE=elsewhere CONFIRM=elsewhere" 0 "$STATUS"
mk delete_central_storage STORAGE_NAMESPACE=elsewhere CONFIRM=elsewhere
check_status "delete_central_storage STORAGE_NAMESPACE=elsewhere CONFIRM=elsewhere" 0 "$STATUS"

# Both central-storage deletes (postgres + object storage) happen under the one confirmation.
reset_stub_log
mk delete_central_storage CONFIRM=rellm-storage
check_contains "delete_central_storage deletes Postgres" "$(stub_calls)" "k8s-central-postgres-"
check_contains "delete_central_storage deletes object storage" "$(stub_calls)" "k8s-central-object-storage-"

# The PVC deletes are gated too, even though they're not reachable through `rellm deploy`.
for target in delete_central_postgres_pvc delete_central_object_storage_pvc; do
  reset_stub_log
  run bash -c 'cd "$1/central_storage" && make --no-print-directory "$2"' _ "$SANDBOX/deploys" "$target"
  check_nonzero "$target refuses without CONFIRM" "$STATUS"
  check_not_contains "$target doesn't touch the cluster without CONFIRM" "$(stub_calls)" "kubectl delete"
done

finish
