#!/bin/bash
# distributables.sh's _rellm_deploys_run, which both `rellm` launchers use for `rellm deploy`:
# kubectl-style flags become make variables, everything else is forwarded untouched. Runs it with a
# stub `make` that just records its arguments, under the system bash (3.2 on macOS) and `bash`.
. "$(dirname "$0")/lib.sh"
sandbox_init
begin "rellm deploy flag translation"

printf '#!/bin/bash\necho "make $*" >> "$STUB_LOG"\n' > "$SANDBOX/bin/make"
chmod +x "$SANDBOX/bin/make"

# deploy_args <args...>: the make invocation _rellm_deploys_run produces.
deploy_args() {
  reset_stub_log
  run "$SHELL_UNDER_TEST" -c 'set -euo pipefail; . "$1"; shift; _rellm_deploys_run /d "$@"' _ "$DEPLOYS_SRC/distributables.sh" "$@"
  STATUS_SAVED=$STATUS
  stub_calls
}

check_args() {
  local description="$1" expected="$2"
  shift 2
  local actual
  actual="$(deploy_args "$@")"
  check_eq "$description" "make --no-print-directory -C /d${expected:+ $expected}" "$actual"
}

for SHELL_UNDER_TEST in bash /bin/bash; do
  [ -x "$(command -v "$SHELL_UNDER_TEST")" ] || continue
  echo " ($SHELL_UNDER_TEST: $("$SHELL_UNDER_TEST" --version | head -n 1))"
  check_args "-n <ns>" "view_server_logs NAMESPACE=my-site" view_server_logs -n my-site
  check_args "--namespace <ns>" "view_server_logs NAMESPACE=my-site" view_server_logs --namespace my-site
  check_args "--namespace=<ns>" "view_server_logs NAMESPACE=my-site" view_server_logs --namespace=my-site
  check_args "-n<ns>" "view_server_logs NAMESPACE=my-site" view_server_logs -nmy-site
  check_args "-n=<ns>" "view_server_logs NAMESPACE=my-site" view_server_logs -n=my-site
  check_args "the flag may come first" "NAMESPACE=my-site create_backend_data create_internal_backend" -n my-site create_backend_data create_internal_backend
  check_args "--domain <d>" "add_ingress_domain NAMESPACE=x DOMAIN=a.example.com" add_ingress_domain -n x --domain a.example.com
  check_args "--domain=<d>" "add_ingress_domain NAMESPACE=x DOMAIN=a.example.com" add_ingress_domain -n x --domain=a.example.com
  check_args "--confirm <v>" "delete_backend_data_pvcs NAMESPACE=x CONFIRM=x" delete_backend_data_pvcs -n x --confirm x
  check_args "--confirm=<v>" "delete_backend_data_pvcs NAMESPACE=x CONFIRM=x" delete_backend_data_pvcs -n x --confirm=x
  check_args "--tail" "view_job_logs NAMESPACE=x LOG_TAIL=1" view_job_logs -n x --tail
  check_args "--lines <n>" "view_job_logs NAMESPACE=x LOG_LINES=20" view_job_logs -n x --lines 20
  check_args "--lines=<n>" "view_job_logs NAMESPACE=x LOG_LINES=20" view_job_logs -n x --lines=20
  check_args "all log flags together" "view_tmux_logs NAMESPACE=x LOG_TAIL=1 LOG_LINES=5" view_tmux_logs -n x --tail --lines 5
  check_args "VAR=value arguments are forwarded as-is" "add_ingress_domain NAMESPACE=x CONFIRM=x DOMAIN=a.example.com" add_ingress_domain -n x CONFIRM=x DOMAIN=a.example.com
  check_args "NAMESPACE=<ns> still works" "get_backend_all NAMESPACE=x" get_backend_all NAMESPACE=x
  check_args "make's own long flags (--dry-run) are untouched" "--dry-run NAMESPACE=x get_backend_all" --dry-run -n x get_backend_all
  check_args "no arguments at all (empty array under set -u)" ""

  for flag in -n --namespace --lines --domain --confirm; do
    deploy_args view_server_logs "$flag" > /dev/null
    check_nonzero "$flag without a value fails" "$STATUS_SAVED"
    check_contains "$flag without a value says so" "$OUT" "needs a value"
  done
done

finish
