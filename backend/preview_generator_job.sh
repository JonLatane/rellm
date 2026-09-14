#!/bin/bash
#
# Runs Rellm's preview-image generator in a persistent loop: a random 0-120s
# startup delay (so a rollout across many tenants doesn't have every pod hit
# the DB/launch a browser in the same instant), then repeatedly runs
# generate_preview_images with a 120-second sleep between runs -- forever.
#
# Lives alongside background_jobs.sh (see that file) and is a deliberate
# duplicate of its loop shape, trimmed to the one job the preview_generator
# image runs. This replaced the old per-minute `generate-preview-images` K8s
# CronJob (deploys/k8s/preview_generator.yaml) with a single persistent pod --
# that many CronJob executions piling up across every tenant namespace at
# once was adding to cluster resource pressure.
set -euo pipefail

# See background_jobs.sh's `set -m` comment: same reasoning applies here so
# a TERM can reach generate_preview_images's process group, not just this
# loop's own shell.
set -m

STARTUP_DELAY=$(( RANDOM % 121 ))
INTERVAL=120

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

echo "[preview_generator_job] starting in ${STARTUP_DELAY}s..."
sleep "$STARTUP_DELAY"

pid=""
trap '
  if [ -n "$pid" ]; then
    kill -TERM -- "-${pid}" 2>/dev/null || true
  fi
  exit 0
' TERM INT

while true; do
  echo "[preview_generator_job] running generate_preview_images..."
  ./generate_preview_images &
  pid="$!"
  wait "$pid" || echo "[preview_generator_job] generate_preview_images failed" >&2
  pid=""
  sleep "$INTERVAL"
done
