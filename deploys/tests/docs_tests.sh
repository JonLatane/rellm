#!/bin/bash
# Documentation that names commands: every `rellm deploy <target>` / `make -C deploys <target>` in the
# READMEs is a real target, and the launchers' help text and tab-completion know about the log commands.
. "$(dirname "$0")/lib.sh"
sandbox_init
begin "docs and launchers"

top_targets="$(makefile_targets "$SANDBOX/deploys/Makefile" | tr '\n' ' ')"

# Extract target names (words containing an underscore -- every target does) from documented commands.
documented_targets() {
  local file="$1" prefix="$2"
  grep -o "$prefix [a-z_ ]*" "$file" | sed "s/^$prefix //" | tr ' ' '\n' | grep '_' | grep -v '_$' | sort -u
}

for file in "$DEPLOYS_SRC/README.md" "$REPO_ROOT/README.md"; do
  [ -f "$file" ] || { echo "  (skipping $file: not present)"; continue; }
  name="${file#$REPO_ROOT/}"
  for prefix in "rellm deploy" "make -C deploys"; do
    for target in $(documented_targets "$file" "$prefix"); do
      if in_list "$target" "$top_targets"; then
        pass "$name: '$prefix $target' is a target"
      else
        fail "$name documents '$prefix $target', but deploys/Makefile defines no such target"
      fi
    done
  done
done

# The launchers' `rellm help` documents the deploy flags and log commands.
for launcher in rellm_homebrew.sh rellm_linux.sh; do
  file="$REPO_ROOT/docs/$launcher"
  [ -f "$file" ] || { echo "  (skipping $launcher: not present)"; continue; }
  run bash "$file" help
  check_status "$launcher help" 0 "$STATUS"
  for word in view_server_logs view_job_logs view_preview_generator_logs view_tmux_logs --namespace --domain --confirm --tail; do
    check_contains "$launcher help mentions $word" "$OUT" "$word"
  done
done

# Tab-completion's target list (what `rellm --list-deploy-targets` prints).
. "$DEPLOYS_SRC/distributables.sh"
listed="$(_rellm_deploys_list_targets "$SANDBOX/deploys" | tr '\n' ' ')"
for target in create_ingress view_server_logs view_tmux_logs create_backend_data get_central_postgres_pvc_size; do
  if in_list "$target" "$listed"; then pass "completion lists $target"; else fail "completion should list $target" "listed: $listed"; fi
done

finish
