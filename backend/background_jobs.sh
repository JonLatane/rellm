#!/bin/bash
#
# Runs Rellm's periodic background jobs, each in its own forked loop: sleep
# the job's startup delay (if any), run the job's binary, sleep the job's
# interval, repeat -- forever, one Unix fork per job.
#
# Copied verbatim into the Homebrew and Linux release packages, alongside the
# other binaries (rellm-server, delete_expired_tokens, ...), by the
# create_homebrew_release / create_linux_release jobs in
# .github/workflows/server_ci_cd.yml. It's invoked by those packages'
# `rellm jobs` / `rellm server_and_jobs` launcher commands (see
# docs/rellm_linux.sh and docs/rellm_homebrew.sh) -- don't hand-edit a
# shipped copy, edit this file instead.
#
# To add a job, append a "binary_name startup_delay_seconds interval_seconds"
# entry to JOBS below -- binary_name must have a matching backend/src/bin/*.rs.
# startup_delay_seconds may instead be the literal string "random", meaning a
# delay chosen once (at this script's own startup) uniformly at random between
# 0 and interval_seconds -- useful for a job whose work is expensive against a
# shared resource (e.g. listing a whole object storage bucket), so that many
# instances of this script starting at the same wall-clock moment (e.g. a
# Kubernetes rolling deploy restarting every replica together) don't all run
# that job at the same moment too, every interval, forever.
# Each job's binary is resolved (in this order):
#   1. ./binary_name                    (Homebrew macOS package; single-arch)
#   2. ./binary_name-<amd64|arm64>      (Linux tarball; arch-suffixed binaries)
#   3. target/debug/binary_name         (running from a source checkout: built first with
#                                        `cargo build --quiet`, whose output -- compiler warnings,
#                                        "Finished" -- is discarded so it doesn't clutter the job
#                                        logs; falls back to `cargo run`, which shows any build errors)
#
set -euo pipefail

# Job control: makes each `&`-launched loop below its own process group
# leader, so `kill -TERM -- "-$pid"` in the trap can reach not just the loop
# itself but whatever it's currently running too -- notably `cargo run`,
# which forks the actual job binary as a child that a plain `kill $pid`
# would otherwise orphan (bash only kills the loop's shell, not its
# grandchildren).
set -m

JOBS=(
  "delete_expired_tokens 0 120"
  "delete_unowned_media 10 28800"
  "sync_sources 5 60"
  "update_user_counts 15 3600"
  "convert_media_sizes 20 600"
  "renew_market_subscriptions 25 3600"
  "calculate_server_media_usage 30 180"
  "calculate_server_object_storage_usage random 14400"
)

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Prints "amd64" or "arm64" to match the Linux release's binary naming, or
# nothing for architectures/platforms that scheme doesn't cover (e.g. macOS),
# so callers just fall through to the next resolution step.
_background_jobs_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) echo "" ;;
  esac
}

# Echoes the command (as a single, word-split-on-purpose string) that runs
# the given job binary, trying each resolution step in turn.
_background_jobs_resolve_bin() {
  local name="$1"
  if [ -x "./${name}" ]; then
    echo "./${name}"
    return
  fi

  local arch
  arch="$(_background_jobs_arch)"
  if [ -n "$arch" ] && [ -x "./${name}-${arch}" ]; then
    echo "./${name}-${arch}"
    return
  fi

  # Source checkout: build first, quietly, and run the binary itself. `cargo run` would replay
  # the project's compiler warnings (and print "Finished"/"Running") into every job run's output.
  if command -v cargo >/dev/null 2>&1; then
    local built="${CARGO_TARGET_DIR:-target}/debug/${name}"
    if cargo build --quiet --bin "$name" >/dev/null 2>&1 && [ -x "$built" ]; then
      echo "$built"
      return
    fi
  fi

  # Couldn't build/find it above (or no cargo): `cargo run` reproduces and shows any build errors.
  echo "cargo run --quiet --bin ${name} --"
}

# Logs a message in the same shape the job binaries (and the rellm server) log in:
#   [2026-10-05T12:00:00Z INFO  background_jobs] message
# with the level colored like env_logger's defaults (see init_bin_logging in backend/src/lib.rs).
# Usage: _background_jobs_log LEVEL message...   -- ERROR/WARN go to stderr, the rest to stdout.
# Honors NO_COLOR.
_background_jobs_log() {
  local level="$1" color="" reset=""
  shift
  if [ -z "${NO_COLOR:-}" ]; then
    reset=$'\033[0m'
    case "$level" in
      ERROR) color=$'\033[31m' ;;
      WARN)  color=$'\033[33m' ;;
      INFO)  color=$'\033[32m' ;;
      DEBUG) color=$'\033[34m' ;;
      TRACE) color=$'\033[36m' ;;
    esac
  fi
  local out
  out="$(printf '[%s %s%-5s%s background_jobs] %s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$color" "$level" "$reset" "$*")"
  case "$level" in
    ERROR|WARN) printf '%s\n' "$out" >&2 ;;
    *) printf '%s\n' "$out" ;;
  esac
}

# Prefixes each stdin line with "[name] " -- except lines already in the "[<timestamp> LEVEL name]"
# form the job binaries log in when RELLM_LOG_JOB_NAME is set (see the run loop below), which
# already say which job they came from. What's left to label is output that doesn't come from the
# `log` crate: panic text on stderr, `cargo run` build output, stray println!s, and continuation
# lines of multi-line messages.
_background_jobs_label() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "[20"[0-9][0-9]-*) printf '%s\n' "$line" ;;
      *) printf '[%s] %s\n' "$1" "$line" ;;
    esac
  done
}

_background_jobs_run_loop() {
  local name="$1" delay="$2" interval="$3"

  if [ "$delay" = "random" ]; then
    delay=$((RANDOM % interval))
    _background_jobs_log INFO "${name}: randomized startup delay ${delay}s (interval ${interval}s)"
  fi

  if [ "$delay" -gt 0 ]; then
    sleep "$delay"
  fi

  while true; do
    local bin
    bin="$(_background_jobs_resolve_bin "$name")"
    _background_jobs_log INFO "running ${name} (${bin})..."
    local status=0
    if [ "${RELLM_LABEL_JOB_OUTPUT:-1}" != "0" ]; then
      # Make each job's output (stderr merged in) say which job printed what, so interleaved
      # logs -- kubectl logs on the jobs pod, the launchers' server_and_jobs -- are readable:
      # RELLM_LOG_JOB_NAME makes the job log "[<timestamp> LEVEL name] message" itself, and
      # _background_jobs_label adds a "[name] " prefix to anything else it prints. Set
      # RELLM_LABEL_JOB_OUTPUT=0 to disable the label pipe. (pipefail makes the pipeline's
      # status the job's own.)
      RELLM_LOG_JOB_NAME="$name" $bin 2>&1 | _background_jobs_label "$name" || status=$?
    else
      RELLM_LOG_JOB_NAME="$name" $bin || status=$?
    fi
    if [ "$status" -ne 0 ]; then
      _background_jobs_log ERROR "${name} failed"
    fi
    sleep "$interval"
  done
}

pids=()
for job in "${JOBS[@]}"; do
  read -r name delay interval <<< "$job"
  _background_jobs_run_loop "$name" "$delay" "$interval" &
  pids+=("$!")
done

trap '
  for pid in "${pids[@]}"; do
    kill -TERM -- "-${pid}" 2>/dev/null || true
  done
' TERM INT

wait
