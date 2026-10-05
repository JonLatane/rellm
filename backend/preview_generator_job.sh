#!/bin/bash
#
# Runs Rellm's preview-image generator in a persistent loop: a random 0-120s
# startup delay (so a rollout across many tenants doesn't have every pod hit
# the DB/launch a browser in the same instant), then repeatedly runs
# generate_link_preview_images with a 120-second sleep between runs -- forever.
#
# Lives alongside background_jobs.sh (see that file) and is a deliberate
# duplicate of its loop shape, trimmed to the one job the preview_generator
# image runs. This replaced the old per-minute `generate-preview-images` K8s
# CronJob (deploys/k8s/preview_generator.yaml) with a single persistent pod --
# that many CronJob executions piling up across every tenant namespace at
# once was adding to cluster resource pressure.
set -euo pipefail

# See background_jobs.sh's `set -m` comment: same reasoning applies here so
# a TERM can reach generate_link_preview_images's process group, not just this
# loop's own shell.
set -m

# Logs in the same shape generate_link_preview_images (and the rellm server) log in:
#   [2026-10-05T12:00:00Z INFO  preview_generator_job] message
# with the level colored like env_logger's defaults. A deliberate duplicate of the same helper in
# background_jobs.sh. ERROR/WARN go to stderr. Honors NO_COLOR.
_log() {
  local level="$1" color="" reset=""
  shift
  if [ -z "${NO_COLOR:-}" ]; then
    reset=$'\033[0m'
    case "$level" in
      ERROR) color=$'\033[31m' ;;
      WARN)  color=$'\033[33m' ;;
      INFO)  color=$'\033[32m' ;;
    esac
  fi
  local out
  out="$(printf '[%s %s%-5s%s preview_generator_job] %s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$color" "$level" "$reset" "$*")"
  case "$level" in
    ERROR|WARN) printf '%s\n' "$out" >&2 ;;
    *) printf '%s\n' "$out" ;;
  esac
}

STARTUP_DELAY=$(( RANDOM % 121 ))
INTERVAL=120

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

_log INFO "starting in ${STARTUP_DELAY}s..."
sleep "$STARTUP_DELAY"

pid=""
trap '
  if [ -n "$pid" ]; then
    kill -TERM -- "-${pid}" 2>/dev/null || true
  fi
  exit 0
' TERM INT

while true; do
  _log INFO "running generate_link_preview_images..."
  # RELLM_LOG_JOB_NAME makes the binary log "[<timestamp> LEVEL generate_link_preview_images] ...".
  RELLM_LOG_JOB_NAME=generate_link_preview_images ./generate_link_preview_images &
  pid="$!"
  wait "$pid" || _log ERROR "generate_link_preview_images failed"
  pid=""
  sleep "$INTERVAL"
done
