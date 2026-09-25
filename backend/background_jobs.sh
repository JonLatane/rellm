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
#   3. cargo run --bin binary_name --   (running from a source checkout)
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

  echo "cargo run --bin ${name} --"
}

_background_jobs_run_loop() {
  local name="$1" delay="$2" interval="$3"

  if [ "$delay" = "random" ]; then
    delay=$((RANDOM % interval))
    echo "[background_jobs] ${name}: randomized startup delay ${delay}s (interval ${interval}s)"
  fi

  if [ "$delay" -gt 0 ]; then
    sleep "$delay"
  fi

  while true; do
    local bin
    bin="$(_background_jobs_resolve_bin "$name")"
    echo "[background_jobs] running ${name} (${bin})..."
    if ! $bin; then
      echo "[background_jobs] ${name} failed" >&2
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
