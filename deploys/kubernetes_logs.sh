#!/bin/bash
#
# Unified log viewing for a Rellm namespace, using nothing but `kubectl` (no kail needed): the
# `rellm` server runs as several replicas (see replicas: in k8s/server_*.yaml), and
# `kubectl logs -l <selector> --prefix` already multiplexes every matching pod into one stream,
# tagging each line "[pod/<pod>/<container>] ". This script adds the rest:
#
#   * non-follow mode merges the pods' lines by timestamp (kubectl alone prints one pod's whole
#     log, then the next's);
#   * follow mode reconnects when pods are replaced (e.g. a rollout), which plain
#     `kubectl logs -f -l ...` doesn't -- it just exits;
#   * `tmux` opens Server | Jobs | Preview Generator side by side.
#
# Run via the deploys/Makefile targets, which is also how `rellm deploy` reaches it:
#   rellm deploy view_logs                   -n my-namespace
#   rellm deploy view_server_logs            -n my-namespace
#   rellm deploy view_job_logs               -n my-namespace --tail
#   rellm deploy view_preview_generator_logs -n my-namespace
#   rellm deploy view_tmux_logs              -n my-namespace
# or directly:
#   deploys/kubernetes_logs.sh <all|server|jobs|preview_generator|tmux> -n <namespace> [--tail] [--lines <n>]
#
# Written for bash 3.2 (stock macOS), as it ships in the Homebrew package.
set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

usage() {
  cat >&2 <<'EOF'
Usage: kubernetes_logs.sh <all|server|jobs|preview_generator|tmux> [options]

  all                    Every pod in the namespace (server, jobs, preview generator, and anything else
                         running there), all containers.

  -n, --namespace <ns>   Kubernetes namespace (or set NAMESPACE). Required.
      --tail             Follow the logs (like `tail -f`) instead of printing them and returning.
      --lines <n>        Only the last <n> lines per pod. Default: all of them, or the last 50
                         when following.

tmux opens Server | Jobs | Preview Generator panes, always following; it ignores --tail.
EOF
}

die() {
  echo "$*" >&2
  exit 1
}

command -v kubectl >/dev/null 2>&1 || die "kubectl is required to view logs."

what="${1:-}"
[ -n "$what" ] || { usage; exit 1; }
shift

namespace="${NAMESPACE:-}"
follow=""
lines=""
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--namespace)
      [ $# -ge 2 ] || die "$1 needs a value."
      namespace="$2"
      shift 2
      ;;
    --namespace=*) namespace="${1#--namespace=}"; shift ;;
    --tail|-f|--follow) follow=1; shift ;;
    --lines)
      [ $# -ge 2 ] || die "--lines needs a value."
      lines="$2"
      shift 2
      ;;
    --lines=*) lines="${1#--lines=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "Unknown option: $1" ;;
  esac
done

[ -n "$namespace" ] || { usage; die "A namespace is required (-n <namespace>)."; }
case "$lines" in
  ''|*[!0-9]*) [ -z "$lines" ] || die "--lines must be a non-negative integer." ;;
esac

# Every Deployment in k8s/*.yaml labels its pods app=<deployment name>.
# `all` is every pod in the namespace, whatever it's labelled: kubectl logs has no "whole namespace" mode, but
# `-l` takes a set-based selector, and "!<key>" matches every pod without that label -- so, with a label
# nothing has, all of them.
selector_for() {
  case "$1" in
    all) echo "!rellm-no-such-label" ;;
    server) echo "app=rellm" ;;
    jobs) echo "app=rellm-jobs" ;;
    preview_generator) echo "app=rellm-preview-generator" ;;
    *) die "Unknown log source: $1" ;;
  esac
}

label_for() {
  case "$1" in
    all) echo "Namespace" ;;
    server) echo "Server" ;;
    jobs) echo "Jobs" ;;
    preview_generator) echo "Preview Generator" ;;
  esac
}

# Names of pods matching the selector; with "running", only ones in the Running phase.
pods_for() {
  local selector="$1" extra=()
  if [ "${2:-}" = "running" ]; then
    extra=(--field-selector=status.phase=Running)
  fi
  kubectl get pods -n "$namespace" -l "$selector" ${extra[@]+"${extra[@]}"} -o name
}

view() {
  local source="$1" selector pods
  selector="$(selector_for "$source")"
  # In `all`, include sidecars/init containers of whatever else runs in the namespace (our own pods have just
  # the one container, so it's the same for them).
  local container_args=()
  if [ "$source" = all ]; then
    container_args=(--all-containers)
  fi
  pods="$(pods_for "$selector")" || exit 1
  if [ -z "$pods" ]; then
    die "No $(label_for "$source") pods (-l $selector) found in namespace '$namespace'."
  fi

  if [ -z "$follow" ]; then
    # kubectl's default for a selector is only the last 10 lines, so always pass --tail.
    # --timestamps is only here to merge by; it's stripped again below.
    kubectl logs -n "$namespace" -l "$selector" ${container_args[@]+"${container_args[@]}"} --prefix --timestamps --tail="${lines:--1}" \
      | LC_ALL=C sort -s -k2,2 \
      | sed -E 's/^(\[[^]]*\]) [0-9T:.Z-]+ /\1 /'
    return
  fi

  # Following. --max-log-requests lifts kubectl's default cap of 5 pods followed at once. The
  # streams all end when the pods go away (a rollout replaced them, say), so reconnect -- with
  # --tail=0 after the first connection so we don't replay history. Errors (bad credentials,
  # namespace deleted) still exit; Ctrl-C always does.
  local tail_arg="${lines:-50}"
  while true; do
    kubectl logs -n "$namespace" -l "$selector" ${container_args[@]+"${container_args[@]}"} --prefix --follow --tail="$tail_arg" --max-log-requests=50
    tail_arg=0
    sleep "${RELLM_LOGS_RECONNECT_DELAY:-2}"
  done
}

tmux_view() {
  command -v tmux >/dev/null 2>&1 || die "view_tmux_logs requires tmux."
  echo "NOTE: view_tmux_logs tails logs implicitly without --tail"

  local session="rellm-logs-$namespace" sources="server jobs" source
  # Only open the Preview Generator pane if one is running (not every deployment has one).
  if [ -n "$(pods_for "$(selector_for preview_generator)" running)" ]; then
    sources="$sources preview_generator"
  else
    echo "NOTE: no running Preview Generator pod in '$namespace'; not opening a pane for it."
  fi

  local lines_arg=""
  if [ -n "$lines" ]; then
    lines_arg="--lines $lines"
  fi

  # Session-scoped options (not -g), so this doesn't change the user's other tmux sessions. As in
  # the dev `run_tmux` Makefile targets: mouse on (click a pane to focus, drag borders to resize),
  # pane titles shown on the borders, and a fixed window/terminal title.
  tmux kill-session -t "$session" 2>/dev/null || true
  local first=1
  for source in $sources; do
    if [ -n "$first" ]; then
      tmux new-session -d -s "$session"
      tmux set-option -t "$session" mouse on
      tmux set-option -t "$session" set-titles on
      tmux set-option -t "$session" set-titles-string "rellm logs: $namespace"
      tmux set-window-option -t "$session" pane-border-status top
      tmux set-window-option -t "$session" automatic-rename off
      tmux rename-window -t "$session" "rellm logs: $namespace"
      first=""
    else
      tmux split-window -t "$session" -h
    fi
    tmux select-pane -t "$session" -T "$(label_for "$source")"
    # printf %q so the namespace/path survive the shell in the pane.
    # shellcheck disable=SC2086
    tmux send-keys -t "$session" \
      "$(printf '%q ' bash "$SCRIPT_PATH" "$source" --namespace "$namespace" --tail)$lines_arg" C-m
  done
  tmux select-layout -t "$session" even-horizontal
  # Focus the leftmost (Server) pane.
  local i
  for ((i = 1; i < $(echo "$sources" | wc -w); i++)); do
    tmux select-pane -t "$session" -L
  done

  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$session"
  else
    tmux attach-session -t "$session"
  fi
}

case "$what" in
  all|server|jobs|preview_generator) view "$what" ;;
  tmux) tmux_view ;;
  *) usage; die "Unknown log source: $what" ;;
esac
