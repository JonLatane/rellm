# Shared helpers for deploys/tests/*_tests.sh -- sourced, not run. Written for bash 3.2 (stock macOS):
# no associative arrays, mapfile or ${var,,}, and empty arrays are guarded for `set -u`.
#
# Nothing here ever talks to a cluster. Each test file runs against a sandbox copy of deploys/ (so
# generated files and anything a recipe writes stay out of the repo, and no private keys or Postgres
# dumps are copied), with stub `kubectl`/`tmux`/... first on PATH that record every call in
# $STUB_LOG and return canned output. Two ways of running make against it:
#   * mk <args>      runs make for real (stub kubectl), for targets whose behavior we want to see.
#   * mk_dry <args>  runs `make -n MAKE=true <args>`. `make -n` still *executes* any recipe line that
#                    mentions $(MAKE) (that's how the passthroughs and interactive targets like
#                    deploy_certmanager_credential would hang or hit a real cluster), so MAKE=true
#                    neuters those: a passthrough prints/runs as `true -C ingress <target>`.
# Everything runs with stdin from /dev/null so nothing can block on a prompt.

set -u

# These tests run make themselves, against a sandbox. When they're started by `make -C deploys test` (as CI does)
# they inherit that make's MAKELEVEL/MAKEFLAGS, which makes GNU make 4+ treat every make here as a sub-make and
# print "make[1]: Entering directory ..." lines -- even with -s -- into output that tests parse. Start clean.
unset MAKELEVEL MAKEFLAGS MFLAGS

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYS_SRC="$(dirname "$TESTS_DIR")"
REPO_ROOT="$(dirname "$DEPLOYS_SRC")"

PASSED=0
FAILED=0
SANDBOX=""
OUT=""
STATUS=0

pass() {
  PASSED=$((PASSED + 1))
  echo "  ok - $1"
}

fail() {
  FAILED=$((FAILED + 1))
  echo "  FAIL - $1"
  if [ $# -gt 1 ]; then
    printf '%s\n' "$2" | sed 's/^/         /'
  fi
}

# check_eq <description> <expected> <actual>
check_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected: $2"$'\n'"actual:   $3"; fi
}

# check_contains <description> <haystack> <needle>
check_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "expected to contain: $3"$'\n'"actual output: $2" ;;
  esac
}

check_not_contains() {
  case "$2" in
    *"$3"*) fail "$1" "expected NOT to contain: $3"$'\n'"actual output: $2" ;;
    *) pass "$1" ;;
  esac
}

check_status() {
  if [ "$2" -eq "$3" ]; then pass "$1"; else fail "$1" "expected exit status $2, got $3"$'\n'"output: $OUT"; fi
}

check_nonzero() {
  if [ "$2" -ne 0 ]; then pass "$1"; else fail "$1" "expected a non-zero exit status, got 0"$'\n'"output: $OUT"; fi
}

# in_list <word> <space-separated list>
in_list() {
  local list
  list="$(printf '%s' "$2" | tr '\n\t' '  ')"
  case " $list " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# run <command...>: runs it with stdin from /dev/null, stdout+stderr into $OUT, exit status in $STATUS.
run() {
  OUT="$("$@" 2>&1 </dev/null)"
  STATUS=$?
}

begin() {
  echo "== $1"
}

finish() {
  echo "  $PASSED passed, $FAILED failed"
  [ "$FAILED" -eq 0 ]
  exit $?
}

# Every target defined in a Makefile (plain names only: not pattern rules, `.PHONY`-style specials, or
# generated-file rules like k8s/foo.$(NAMESPACE).generated.yaml).
makefile_targets() {
  awk '/^[A-Za-z0-9_-]+:([^=]|$)/ { sub(/:.*/, ""); print }' "$1" | sort -u
}

stub_kubectl() {
  cat > "$SANDBOX/bin/kubectl" <<'STUB'
#!/bin/bash
echo "kubectl $*" >> "$STUB_LOG"
case "$*" in *" -f -"*) cat > /dev/null ;; esac
case "$1" in
  get)
    case "$*" in
      *"get pods"*"-o name"*)
        case "$*" in
          *app=rellm-preview-generator*) [ -n "${STUB_NO_PREVIEW:-}" ] || echo pod/rellm-preview-generator-x ;;
          *) echo pod/rellm-a; echo pod/rellm-b ;;
        esac
        ;;
      *"get namespaces"*)
        printf 'default\nmy-site\nmy-other-site\nrellm\n'
        ;;
      *"get service"*)
        printf 'NAME    TYPE         CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE\nrellm   LoadBalancer 10.0.0.1     203.0.113.7   443/TCP   1d\n'
        ;;
      *"get ingressroute"*)
        printf '{"items":[{"metadata":{"name":"rellm-http","namespace":"site-a"},"spec":{"routes":[{"match":"Host(`a.example.com`)"}]}},{"metadata":{"name":"other","namespace":"x"},"spec":{"routes":[{"match":"Host(`no`)"}]}}]}\n'
        ;;
    esac
    ;;
  logs)
    echo "[pod/rellm-b/rellm] 2026-10-05T12:00:02.000000000Z second from b"
    echo "[pod/rellm-a/rellm] 2026-10-05T12:00:01.500000000Z first from a"
    echo "[pod/rellm-a/rellm] 2026-10-05T12:00:03.000000000Z third from a"
    ;;
esac
exit 0
STUB
  chmod +x "$SANDBOX/bin/kubectl"
}

# Records the call and does nothing -- stubs out commands that must never really run.
stub_noop() {
  local name
  for name in "$@"; do
    printf '#!/bin/bash\necho "%s $*" >> "$STUB_LOG"\nexit 0\n' "$name" > "$SANDBOX/bin/$name"
    chmod +x "$SANDBOX/bin/$name"
  done
}

# Copies deploys/ (minus anything private or generated) into a temp dir, puts stub binaries first on
# PATH, and sets STUB_LOG. Cleaned up automatically on exit.
sandbox_init() {
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/rellm-deploys-tests.XXXXXX")"
  trap 'rm -rf "$SANDBOX"' EXIT
  mkdir -p "$SANDBOX/deploys" "$SANDBOX/bin" "$SANDBOX/home"
  tar -C "$DEPLOYS_SRC" -cf - \
    --exclude=./backups --exclude='*.key' --exclude='*.pem' --exclude='*.srl' --exclude='*.csr' \
    --exclude='*.generated.yaml' . | tar -C "$SANDBOX/deploys" -xf -
  printf 'print-%%: ; @echo '"'"'$($*)'"'"'\n' > "$SANDBOX/print.mk"
  export STUB_LOG="$SANDBOX/calls.log"
  : > "$STUB_LOG"
  stub_kubectl
  stub_noop tmux pkill
  export HOME="$SANDBOX/home"
  export PATH="$SANDBOX/bin:$PATH"
}

stub_calls() {
  cat "$STUB_LOG"
}

reset_stub_log() {
  : > "$STUB_LOG"
}

# mk <make args...>: real make in the sandbox's deploys/. --no-print-directory because that's how
# `rellm deploy` runs make (GNU make 4+ would otherwise print "Entering directory" lines, which
# would break composable output like `$(rellm deploy get_ingress_external_ip)`).
mk() {
  run bash -c 'cd "$1" && shift && exec make --no-print-directory "$@"' _ "$SANDBOX/deploys" "$@"
}

# mk_dry <make args...>: `make -n MAKE=true` (see the header comment).
mk_dry() {
  mk -n MAKE=true "$@"
}

# make_var <NAME> -> the value of a variable defined in deploys/Makefile.
make_var() {
  (cd "$SANDBOX/deploys" && make -s --no-print-directory -f Makefile -f "$SANDBOX/print.mk" NAMESPACE=x "print-$1" </dev/null 2>/dev/null)
}

# install_launchers: builds both `rellm` launchers inside the sandbox, laid out like the real
# packages, so tests can run them end to end:
#   $LAUNCHER_LINUX     docs/rellm_linux.sh as <pkg>/bin/rellm, with deploys/ at <pkg>/opt/deploys
#   $LAUNCHER_HOMEBREW  docs/rellm_homebrew.sh with @@RELLM_ETC@@ filled in, deploys/ at <etc>/rellm/opt/deploys
install_launchers() {
  mkdir -p "$SANDBOX/linux_pkg/bin" "$SANDBOX/linux_pkg/opt" "$SANDBOX/brew" "$SANDBOX/etc/rellm/opt"
  cp "$REPO_ROOT/docs/rellm_linux.sh" "$SANDBOX/linux_pkg/bin/rellm"
  cp -R "$SANDBOX/deploys" "$SANDBOX/linux_pkg/opt/deploys"
  sed "s|@@RELLM_ETC@@|$SANDBOX/etc|g" "$REPO_ROOT/docs/rellm_homebrew.sh" > "$SANDBOX/brew/rellm"
  cp -R "$SANDBOX/deploys" "$SANDBOX/etc/rellm/opt/deploys"
  LAUNCHER_LINUX="$SANDBOX/linux_pkg/bin/rellm"
  LAUNCHER_HOMEBREW="$SANDBOX/brew/rellm"
  # Stub server binaries: `rellm-server --version` prints the release this "package" was built from.
  STUB_RELEASE="0.5.553-20260101000000-abc1234"
  local stub
  for stub in "$SANDBOX/linux_pkg/rellm-server-amd64" "$SANDBOX/linux_pkg/rellm-server-arm64" "$SANDBOX/etc/rellm/rellm-server"; do
    printf '#!/bin/bash\n[ "${1:-}" = "--version" ] && echo "%s"\n' "$STUB_RELEASE" > "$stub"
    chmod +x "$stub"
  done
}

# use_launcher <path>: makes `rellm` on PATH run that launcher (what the completion scripts shell out to).
use_launcher() {
  printf '#!/bin/bash\nexec bash "%s" "$@"\n' "$1" > "$SANDBOX/bin/rellm"
  chmod +x "$SANDBOX/bin/rellm"
}
