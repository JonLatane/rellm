#!/bin/bash
# kubernetes_logs.sh (behind view_logs, view_server_logs, view_job_logs, view_preview_generator_logs and
# view_tmux_logs), against stub kubectl/tmux.
. "$(dirname "$0")/lib.sh"
sandbox_init
begin "kubernetes_logs.sh"

logs() {
  run bash "$SANDBOX/deploys/kubernetes_logs.sh" "$@"
}

# --- Printing (not following) ---
reset_stub_log
logs server -n my-ns
check_status "server logs: exit status" 0 "$STATUS"
check_eq "server logs: pods' lines are merged by timestamp, with kubectl's timestamps stripped" \
  "[pod/rellm-a/rellm] first from a"$'\n'"[pod/rellm-b/rellm] second from b"$'\n'"[pod/rellm-a/rellm] third from a" "$OUT"
check_contains "server logs: selects the rellm pods" "$(stub_calls)" "logs -n my-ns -l app=rellm --prefix --timestamps --tail=-1"

reset_stub_log
logs jobs --namespace=my-ns --lines 7
check_contains "job logs: selects rellm-jobs and honors --lines" "$(stub_calls)" "logs -n my-ns -l app=rellm-jobs --prefix --timestamps --tail=7"

reset_stub_log
logs preview_generator -n my-ns
check_contains "preview generator logs: selects rellm-preview-generator" "$(stub_calls)" "-l app=rellm-preview-generator"

reset_stub_log
logs all -n my-ns
check_status "all logs: exit status" 0 "$STATUS"
check_contains "all logs: selects every pod in the namespace, all containers" "$(stub_calls)" "logs -n my-ns -l !rellm-no-such-label --all-containers --prefix --timestamps --tail=-1"
check_eq "all logs: merged by timestamp like the others" \
  "[pod/rellm-a/rellm] first from a"$'\n'"[pod/rellm-b/rellm] second from b"$'\n'"[pod/rellm-a/rellm] third from a" "$OUT"
reset_stub_log
logs all -n my-ns --lines 5
check_contains "all logs: honors --lines" "$(stub_calls)" "--all-containers --prefix --timestamps --tail=5"
reset_stub_log
logs server -n my-ns
check_not_contains "the single-source targets don't ask for all containers" "$(stub_calls)" "--all-containers"

# --- Errors ---
logs server
check_nonzero "no namespace is an error" "$STATUS"
check_contains "no namespace: says so" "$OUT" "A namespace is required"
logs bogus -n x
check_nonzero "an unknown log source is an error" "$STATUS"
logs server -n x --bogus
check_nonzero "an unknown option is an error" "$STATUS"
logs server -n x --lines many
check_nonzero "a non-numeric --lines is an error" "$STATUS"
STUB_NO_PREVIEW=1 logs preview_generator -n x
check_nonzero "no pods is an error" "$STATUS"
check_contains "no pods: names what's missing" "$OUT" "No Preview Generator pods"

# --- Following: reconnects when the streams end, replaying nothing the second time ---
reset_stub_log
RELLM_LOGS_RECONNECT_DELAY=0.1 bash "$SANDBOX/deploys/kubernetes_logs.sh" jobs -n my-ns --tail > /dev/null 2>&1 < /dev/null &
pid=$!
sleep 1.5
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
follow_calls="$(grep -c "logs -n my-ns -l app=rellm-jobs --prefix --follow" "$STUB_LOG")"
if [ "$follow_calls" -ge 2 ]; then pass "follow: reconnects after the streams end ($follow_calls connections)"; else fail "follow: should reconnect" "$(stub_calls)"; fi
check_contains "follow: first connection shows the last 50 lines" "$(stub_calls)" "--follow --tail=50"

reset_stub_log
RELLM_LOGS_RECONNECT_DELAY=0.1 bash "$SANDBOX/deploys/kubernetes_logs.sh" all -n my-ns --tail > /dev/null 2>&1 < /dev/null &
pid=$!
sleep 1
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
check_contains "all logs --tail: follows every pod, all containers, and reconnects" "$(stub_calls)" "logs -n my-ns -l !rellm-no-such-label --all-containers --prefix --follow --tail=50 --max-log-requests=50"
check_contains "follow: reconnections don't replay history" "$(stub_calls)" "--follow --tail=0"

# --- tmux ---
reset_stub_log
logs tmux -n my-ns --tail
check_status "tmux: exit status (--tail is accepted, not an error)" 0 "$STATUS"
check_contains "tmux: notes that it tails implicitly" "$OUT" "NOTE: view_tmux_logs tails logs implicitly without --tail"
panes="$(grep "select-pane -t rellm-logs-my-ns -T" "$STUB_LOG" | sed 's/.* -T //' | tr '\n' ',')"
check_eq "tmux: Server, Jobs, Preview Generator, in that order" "Server,Jobs,Preview Generator," "$panes"
check_contains "tmux: session is named for the namespace" "$(stub_calls)" "tmux new-session -d -s rellm-logs-my-ns"
check_contains "tmux: even layout" "$(stub_calls)" "select-layout -t rellm-logs-my-ns even-horizontal"
check_contains "tmux: attaches" "$(stub_calls)" "attach-session -t rellm-logs-my-ns"
check_contains "tmux: each pane follows its own source" "$(stub_calls)" "kubernetes_logs.sh preview_generator --namespace my-ns --tail"
check_contains "tmux: options are session-scoped, not global" "$(stub_calls)" "set-option -t rellm-logs-my-ns mouse on"
check_not_contains "tmux: never uses -g" "$(stub_calls)" " -g "

reset_stub_log
STUB_NO_PREVIEW=1 logs tmux -n my-ns
check_contains "tmux without a preview generator: says it's skipped" "$OUT" "not opening a pane"
panes="$(grep "select-pane -t rellm-logs-my-ns -T" "$STUB_LOG" | sed 's/.* -T //' | tr '\n' ',')"
check_eq "tmux without a preview generator: Server and Jobs only" "Server,Jobs," "$panes"

reset_stub_log
TMUX=/tmp/tmux-sock,1,0 logs tmux -n my-ns --lines 20
check_contains "tmux inside tmux: switches client instead of nesting" "$(stub_calls)" "switch-client -t rellm-logs-my-ns"
check_not_contains "tmux inside tmux: doesn't attach" "$(stub_calls)" "attach-session"
check_contains "tmux: --lines is passed to the panes" "$(stub_calls)" "--tail --lines 20"

finish
