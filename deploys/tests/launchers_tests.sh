#!/bin/bash
# The Homebrew and Linux `rellm` launchers, end to end, for their deploy-related commands: laid out like
# the real packages (see install_launchers in lib.sh), with the stub kubectl.
. "$(dirname "$0")/lib.sh"
sandbox_init
install_launchers

[ -f "$REPO_ROOT/docs/rellm_linux.sh" ] || { echo "(skipping launchers: docs/ not present)"; exit 0; }

# complete <words...>: the bash completions for `rellm <words...>`, one per line. The last word is the
# one being completed ("" for a bare TAB).
complete_bash() {
  local count=$#
  run bash -c '
    eval "$(rellm completion bash)"
    COMP_WORDS=(rellm "$@")
    COMP_CWORD=$#
    _rellm_complete
    printf "%s\n" ${COMPREPLY[@]+"${COMPREPLY[@]}"}' _ "$@"
}

for name in linux homebrew; do
  if [ "$name" = linux ]; then launcher="$LAUNCHER_LINUX"; else launcher="$LAUNCHER_HOMEBREW"; fi
  use_launcher "$launcher"
  begin "launcher: $name"

  # --- rellm deploy, end to end ---
  run bash "$launcher" deploy view_server_logs -n my-ns
  check_status "deploy view_server_logs -n my-ns" 0 "$STATUS"
  check_contains "deploy runs the bundled Makefile against kubectl" "$OUT" "[pod/rellm-a/rellm] first from a"
  run bash "$launcher" deploy add_ingress_domain
  check_contains "deploy forwards make's errors (namespace required)" "$OUT" "NAMESPACE is required"

  # --- rellm help deploys ---
  run bash "$launcher" help deploys
  check_status "help deploys" 0 "$STATUS"
  check_eq "help deploys (stdout not a terminal) prints deploys/README.md" "$(cat "$DEPLOYS_SRC/README.md")" "$OUT"
  run bash "$launcher" help
  check_contains "plain help mentions help deploys" "$OUT" "rellm help deploys"
  check_contains "plain help: deploys guide is a copy of the GitHub page for this release" "$OUT" "https://github.com/JonLatane/rellm/blob/v$STUB_RELEASE/deploys/README.md"
  check_contains "plain help: ... as of this release" "$OUT" "as of release $STUB_RELEASE."
  run bash "$launcher" help bogus
  check_nonzero "help <unknown topic> fails" "$STATUS"
  check_contains "help <unknown topic> shows usage" "$OUT" "Usage: rellm help [deploys]"

  # --- namespace and target lists, as the completion scripts use them ---
  run bash "$launcher" --list-namespaces
  check_eq "--list-namespaces lists the cluster's namespaces" "default"$'\n'"my-site"$'\n'"my-other-site"$'\n'"rellm" "$OUT"
  run bash "$launcher" --list-deploy-targets
  check_contains "--list-deploy-targets lists targets" "$OUT" "view_server_logs"

  # --- bash completion ---
  complete_bash deploy view_server_logs -n ""
  check_eq "-n <TAB> completes namespaces" "default"$'\n'"my-site"$'\n'"my-other-site"$'\n'"rellm" "$OUT"
  complete_bash deploy view_server_logs --namespace my-
  check_eq "--namespace my-<TAB> completes matching namespaces" "my-site"$'\n'"my-other-site" "$OUT"
  complete_bash deploy create_ing
  check_eq "deploy cre<TAB> completes targets" "create_ingress" "$OUT"
  complete_bash deploy view_server_logs --
  check_eq "deploy -- <TAB> completes flags" "--namespace"$'\n'"--domain"$'\n'"--confirm"$'\n'"--tail"$'\n'"--lines" "$OUT"
  complete_bash help ""
  check_eq "help <TAB> completes topics" "deploys" "$OUT"
  complete_bash dep
  check_eq "rellm dep<TAB> completes commands" "deploy" "$OUT"

  # --- zsh completion script at least parses ---
  if command -v zsh > /dev/null 2>&1; then
    bash "$launcher" completion zsh > "$SANDBOX/_rellm"
    if zsh -n "$SANDBOX/_rellm" 2>/dev/null; then pass "zsh completion script parses"; else fail "zsh completion script has a syntax error" "$(zsh -n "$SANDBOX/_rellm" 2>&1)"; fi
  fi
done

# --- Outside a release package (no server binary to ask), help points at the main branch ---
begin "rellm help without a release"
rm -f "$SANDBOX"/linux_pkg/rellm-server-* "$SANDBOX/etc/rellm/rellm-server"
for launcher in "$LAUNCHER_LINUX" "$LAUNCHER_HOMEBREW"; do
  run bash "$launcher" help
  check_contains "help falls back to the main branch's README" "$OUT" "https://github.com/JonLatane/rellm/blob/main/deploys/README.md"
  check_contains "help says it isn't a release package" "$OUT" "as of the main branch (this isn't a release package)."
done

# --- _rellm_deploys_help: the pager ---
begin "rellm help deploys: pager"
stub_noop mypager less
readme="$SANDBOX/deploys/README.md"
pager_run() {
  # pager_run <PAGER value or empty>: runs _rellm_deploys_help as if stdout were a terminal.
  run env PAGER="$1" bash -c '. "$1"; _rellm_stdout_is_tty() { return 0; }; _rellm_deploys_help "$2"' _ "$DEPLOYS_SRC/distributables.sh" "$SANDBOX/deploys"
}
reset_stub_log
pager_run "mypager -x"
check_contains "uses \$PAGER (with its arguments) on a terminal" "$(stub_calls)" "mypager -x $readme"
reset_stub_log
pager_run ""
check_contains "falls back to less without \$PAGER" "$(stub_calls)" "less $readme"
reset_stub_log
pager_run "no-such-pager-xyz"
check_eq "falls back to plain output if \$PAGER doesn't exist" "$(cat "$readme")" "$OUT"
run bash -c '. "$1"; _rellm_deploys_help /nonexistent' _ "$DEPLOYS_SRC/distributables.sh"
check_nonzero "a missing README is an error" "$STATUS"

finish
