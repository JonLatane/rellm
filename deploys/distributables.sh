# Shared `deploy` subcommand implementation for the `rellm` launcher scripts shipped in the
# Homebrew and Linux packages (docs/rellm_homebrew.sh and docs/rellm_linux.sh). Both launchers
# bundle a full copy of `deploys/` (this file included -- see the "Assemble ... package layout"
# steps of .github/workflows/server_ci_cd.yml's create_homebrew_release/create_linux_release jobs)
# and source this file lazily, only when their `deploy`/`_rellm_deploy_targets` functions are
# actually invoked, since it only exists once installed -- not when a launcher is run standalone/
# uninstalled for local testing (see each launcher's own header comment).
#
# Each launcher resolves its own install-dependent deploys dir differently (Homebrew's fixed
# @@RELLM_ETC@@/rellm/opt/deploys vs. Linux's runtime-resolved
# $(_rellm_package_dir)/opt/deploys), so that resolution stays in the launcher; this file just
# takes the resolved dir as an explicit argument. Not meant to be run standalone -- it's sourced
# into a launcher that's already running under `set -euo pipefail`.

# Usage: _rellm_deploys_run <deploys_dir> [make targets, VAR=value overrides and kubectl-style flags...]
# Forwards args to `make -C <deploys_dir>`, so both targets (create_external_backend, ...) and
# VAR=value overrides (e.g. NAMESPACE=my_namespace, required by nearly every target -- see
# deploys/README.md) just work, same as running `make` by hand from that directory.
#
# A few kubectl-style flags are accepted as friendlier alternatives, and translated first (make
# would otherwise read `-n` as its own --dry-run):
#   -n <ns> | -n<ns> | -n=<ns> | --namespace <ns> | --namespace=<ns>   ->  NAMESPACE=<ns>
#   --domain <d> | --domain=<d>                                         ->  DOMAIN=<d>
#   --confirm <v> | --confirm=<v>                                       ->  CONFIRM=<v>
#   --tail                                                              ->  LOG_TAIL=1
#   --lines <n> | --lines=<n>                                           ->  LOG_LINES=<n>
# --domain only means something to the *_ingress_domain/*_email_domain targets, --confirm to the
# destructive targets that ask for it (the value must still be the namespace -- it's a typed
# confirmation, not a yes/no), and --tail/--lines
# only to the view_*_logs targets (see kubernetes_logs.sh). To dry-run a
# target, use make's long spelling, --dry-run.
_rellm_deploys_run() {
  local deploys_dir="$1"
  shift
  command -v make >/dev/null 2>&1 || {
    echo "rellm deploy requires 'make' -- see $deploys_dir/README.md." >&2
    exit 1
  }
  local make_args=() value
  while [ $# -gt 0 ]; do
    case "$1" in
      -n|--namespace|--lines|--domain|--confirm)
        if [ $# -lt 2 ]; then
          echo "rellm deploy: $1 needs a value." >&2
          exit 1
        fi
        case "$1" in
          --lines) make_args+=("LOG_LINES=$2") ;;
          --domain) make_args+=("DOMAIN=$2") ;;
          --confirm) make_args+=("CONFIRM=$2") ;;
          *) make_args+=("NAMESPACE=$2") ;;
        esac
        shift 2
        ;;
      --namespace=*) make_args+=("NAMESPACE=${1#--namespace=}"); shift ;;
      --lines=*) make_args+=("LOG_LINES=${1#--lines=}"); shift ;;
      --domain=*) make_args+=("DOMAIN=${1#--domain=}"); shift ;;
      --confirm=*) make_args+=("CONFIRM=${1#--confirm=}"); shift ;;
      -n?*)
        value="${1#-n}"
        make_args+=("NAMESPACE=${value#=}")
        shift
        ;;
      --tail) make_args+=("LOG_TAIL=1"); shift ;;
      *) make_args+=("$1"); shift ;;
    esac
  done
  # ${arr[@]+"${arr[@]}"}: an empty array is an unbound variable under `set -u` in bash 3.2 (macOS).
  # --no-print-directory: GNU make 4+ otherwise prints "make: Entering directory ..." around everything
  # (as -C implies -w), which would break composing output, e.g. `$(rellm deploy get_ingress_external_ip)`.
  make --no-print-directory -C "$deploys_dir" ${make_args[@]+"${make_args[@]}"}
}

# Usage: _rellm_deploys_list_targets <deploys_dir>
# Prints deploys/Makefile's target names by asking `make` itself to parse the file and dump its
# internal database (`-qp`), rather than hand-rolling a regex over the Makefile text -- the same
# trick bash-completion's own `_make` completion function uses (including its "# Not a target:"
# annotation handling below, needed to exclude non-target database entries like .DEFAULT_GOAL).
# Used by each launcher's `completion` for deploy-target completion. NAMESPACE is required by the
# Makefile (see deploys/README.md) but irrelevant to just listing target names, so a placeholder
# is passed here to satisfy that check.
_rellm_deploys_list_targets() {
  local deploys_dir="$1"
  command -v make >/dev/null 2>&1 || return 0
  LC_ALL=C make -C "$deploys_dir" -qp NAMESPACE=completion-placeholder 2>/dev/null \
    | awk -v RS= -F: '/(^|\n)# File/,/^# make/ { if ($1 !~ "^[#.\t]") { print $1 } }' \
    | tr ' ' '\n' \
    | sort -u
}

# Usage: _rellm_deploys_list_namespaces
# Prints the cluster's namespace names, one per line, for `rellm deploy ... -n <TAB>` completion.
# Quiet and quick on purpose (a completion shouldn't hang or spew): prints nothing if kubectl is
# missing, the cluster is unreachable or the 3 second request timeout passes.
_rellm_deploys_list_namespaces() {
  command -v kubectl >/dev/null 2>&1 || return 0
  kubectl get namespaces --request-timeout=3s -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
}

# Whether stdout is a terminal. A function so tests can override it.
_rellm_stdout_is_tty() {
  [ -t 1 ]
}

# Usage: _rellm_deploys_help <deploys_dir>
# `rellm help deploys`: shows <deploys_dir>/README.md in $PAGER (falling back to less, then more) when
# stdout is a terminal, and just prints it otherwise (e.g. when piped or redirected).
_rellm_deploys_help() {
  local readme="$1/README.md" pager
  if [ ! -f "$readme" ]; then
    echo "rellm help deploys: can't find $readme." >&2
    exit 1
  fi
  if ! _rellm_stdout_is_tty; then
    cat "$readme"
    return
  fi
  pager="${PAGER:-}"
  if [ -z "$pager" ]; then
    if command -v less >/dev/null 2>&1; then pager=less; elif command -v more >/dev/null 2>&1; then pager=more; else pager=cat; fi
  elif ! command -v "${pager%% *}" >/dev/null 2>&1; then
    pager=cat
  fi
  # Intentionally unquoted: $PAGER may be several words (e.g. "less -R").
  $pager "$readme"
}
