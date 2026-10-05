#!/bin/bash
# The NAMESPACE guard at the top of deploys/Makefile: what requires a namespace, what doesn't, and
# that bad namespace names are rejected up front.
. "$(dirname "$0")/lib.sh"
sandbox_init
begin "NAMESPACE guard"

free_targets="$(make_var NAMESPACE_FREE_TARGETS)"
top_targets="$(makefile_targets "$SANDBOX/deploys/Makefile" | tr '\n' ' ')"

check_contains "NAMESPACE_FREE_TARGETS is readable and includes create_ingress" "$free_targets" "create_ingress"

# Every target not on the free list refuses to run without a namespace.
for target in $top_targets; do
  in_list "$target" "$free_targets" && continue
  mk_dry "$target"
  if [ "$STATUS" -ne 0 ] && case "$OUT" in *"NAMESPACE is required"*) true ;; *) false ;; esac; then
    pass "$target requires NAMESPACE"
  else
    fail "$target should require NAMESPACE" "status=$STATUS output: $OUT"
  fi
done

# Every free target exists, and runs without one.
for target in $free_targets; do
  if ! in_list "$target" "$top_targets"; then
    fail "NAMESPACE_FREE_TARGETS lists $target, but deploys/Makefile defines no such target"
    continue
  fi
  mk_dry "$target"
  if [ "$STATUS" -eq 0 ]; then pass "$target runs without NAMESPACE"; else fail "$target should run without NAMESPACE" "$OUT"; fi
done

# The guard is skipped only if every goal is namespace-free -- and the default goal needs a namespace.
mk_dry create_ingress create_backend_data
check_nonzero "a namespace-free target doesn't excuse a per-namespace one alongside it" "$STATUS"
mk_dry create_ingress get_ingress_external_ip
check_status "several namespace-free targets together need no namespace" 0 "$STATUS"
mk -n MAKE=true
check_nonzero "the default goal needs a namespace" "$STATUS"
mk_dry create_backend_data NAMESPACE=my-site
check_status "NAMESPACE=my-site is accepted" 0 "$STATUS"

# Names that aren't Kubernetes namespace names (DNS-1123 labels) are rejected before anything runs.
long_name="$(printf 'a%.0s' $(seq 1 64))"
for bad in Bad_NS BAD under_score -leading trailing- "has space" a/b "$long_name"; do
  mk_dry create_backend_data "NAMESPACE=$bad"
  case "$OUT" in
    *"not a valid Kubernetes namespace name"*) pass "NAMESPACE='$bad' is rejected" ;;
    *) fail "NAMESPACE='$bad' should be rejected" "status=$STATUS output: $OUT" ;;
  esac
done
for good in a my-site site1 "$(printf 'a%.0s' $(seq 1 63))"; do
  mk_dry create_backend_data "NAMESPACE=$good"
  check_status "NAMESPACE='$good' is accepted" 0 "$STATUS"
done
mk_dry create_central_storage STORAGE_NAMESPACE=Bad_Storage
case "$OUT" in
  *"STORAGE_NAMESPACE"*"not a valid Kubernetes namespace name"*) pass "an invalid STORAGE_NAMESPACE is rejected" ;;
  *) fail "an invalid STORAGE_NAMESPACE should be rejected" "$OUT" ;;
esac

# NAMESPACE from the environment counts as much as NAMESPACE= on the command line.
OUT="$(cd "$SANDBOX/deploys" && NAMESPACE=from-env make -n MAKE=true get_backend_all </dev/null 2>&1)"
check_contains "NAMESPACE from the environment works" "$OUT" "kubectl get all -n from-env"

finish
