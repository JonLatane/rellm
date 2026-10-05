#!/bin/bash
# `rellm deploy` only ever runs `make -C deploys`, so a target in a subdirectory's Makefile (ingress/,
# email/, central_storage/, generated_certs/) that users should run needs a one-line passthrough in
# deploys/Makefile. This checks both directions: nothing in a subdirectory is silently unreachable, and
# no passthrough points at a target that doesn't exist.
. "$(dirname "$0")/lib.sh"
sandbox_init
begin "subdirectory passthroughs"

top_targets="$(makefile_targets "$SANDBOX/deploys/Makefile" | tr '\n' ' ')"

# Subdirectory targets that are deliberately NOT reachable through `rellm deploy`: building blocks of a
# target that is (e.g. create_central_storage runs create_central_postgres), kept out of the user-facing
# surface. A new target in a subdirectory fails this test until it gets a passthrough in deploys/Makefile
# -- or, if users shouldn't run it directly, an entry here.
not_passed_through_central_storage="
  deploy_central_storage_ensure_namespace deploy_central_storage_ensure_storageclass_retain
  create_central_postgres_credentials create_central_object_storage_credentials
  create_central_postgres update_central_postgres delete_central_postgres delete_central_postgres_pvc restart_central_postgres
  create_central_object_storage update_central_object_storage delete_central_object_storage delete_central_object_storage_pvc restart_central_object_storage
  check_delete_central_storage_confirmed"

# The CONFIRM check deploy_ingress_controller_delete (and so remove_ingress) depends on.
not_passed_through_ingress="check_ingress_delete_confirmed"

# generated_certs/Makefile duplicates these verbatim "for standalone use from within that directory";
# deploys/Makefile defines them itself.
defined_at_top_generated_certs="get_backend_generated_certs get_backend_generated_ca_certs deploy_ensure_namespace"

for dir in ingress email central_storage generated_certs; do
  sub_targets="$(makefile_targets "$SANDBOX/deploys/$dir/Makefile" | tr '\n' ' ')"
  for target in $sub_targets; do
    case "$dir" in
      central_storage) in_list "$target" "$not_passed_through_central_storage" && continue ;;
      ingress) in_list "$target" "$not_passed_through_ingress" && continue ;;
      generated_certs) in_list "$target" "$defined_at_top_generated_certs" && continue ;;
    esac
    if ! in_list "$target" "$top_targets"; then
      fail "$dir/$target has no passthrough in deploys/Makefile" "add one, or (if users shouldn't run it directly) list it in tests/passthrough_tests.sh"
      continue
    fi
    mk_dry NAMESPACE=x "$target"
    case "$OUT" in
      *"-C $dir $target"*) pass "$target passes through to $dir/" ;;
      *) fail "$target should pass through to $dir/" "status=$STATUS output: $OUT" ;;
    esac
  done
done

# And the other direction: every passthrough points at a target that exists in its subdirectory.
for target in $top_targets; do
  mk_dry NAMESPACE=x "$target"
  dir="$(printf '%s\n' "$OUT" | sed -n "s/^true -C \([a-z_]*\) $target\$/\1/p" | head -n 1)"
  [ -n "$dir" ] || continue
  if in_list "$target" "$(makefile_targets "$SANDBOX/deploys/$dir/Makefile" | tr '\n' ' ')"; then
    pass "$target exists in $dir/Makefile"
  else
    fail "deploys/Makefile passes $target through to $dir/, which has no such target"
  fi
done

finish
