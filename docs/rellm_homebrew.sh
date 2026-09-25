#!/bin/bash
#
# Source of truth for the `rellm` launcher script installed by Homebrew
# (JonLatane/homebrew-rellm) as `bin/rellm`.
#
# This file is spliced verbatim into Formula/rellm.rb's `install` method by
# the "Push Formula/rellm.rb to JonLatane/homebrew-rellm" step of the
# Server CI/CD workflow (create_homebrew_release job) in
# .github/workflows/server_ci_cd.yml -- don't hand-edit the generated
# Formula, edit this file instead.
#
# The one placeholder below, @@RELLM_ETC@@, is replaced by that CI step with
# a Ruby string interpolation of the formula's `etc` accessor, which Homebrew
# resolves to the formula's installed etc/ prefix (e.g. /opt/homebrew/etc)
# when the user runs `brew install`. That path isn't known until install time
# and can differ per machine, so it can't be baked in here as a real value --
# but aside from that one substitution, this file is plain, valid,
# directly-runnable bash (e.g. `bash docs/rellm_homebrew.sh help` works
# locally; `server` and the other package-binary subcommands, via
# _rellm_exec_bin, are the only ones that need the real substitution to
# find their install dir).
#
# NOTE: because this whole file is embedded via an interpolated Ruby heredoc,
# any other literal Ruby interpolation syntax written below (a hash followed
# immediately by a brace) would also get evaluated by Ruby at formula-write
# time. Don't introduce one outside of the @@RELLM_ETC@@ substitution step.
#
set -euo pipefail

RELLM_ENV="$HOME/.rellm"
if [ ! -f "$RELLM_ENV" ]; then
  cat > "$RELLM_ENV" <<'RELLM_ENV_EOF'
DATABASE_URL=postgres://localhost/rellm_dev

OBJECT_STORAGE_ENDPOINT=http://localhost:9000
OBJECT_STORAGE_REGION=
OBJECT_STORAGE_BUCKET=rellm-dev
OBJECT_STORAGE_ACCESS_KEY=ROOTNAME
OBJECT_STORAGE_SECRET_KEY=CHANGEME123

# TLS_CERT_PATH=/path/to/cert.pem
RELLM_ENV_EOF
fi

set -a
source "$RELLM_ENV"
set +a

RELLM_DB_NAME="${RELLM_DB_NAME:-rellm_dev}"
RELLM_OBJECT_STORAGE_CONTAINER="${RELLM_OBJECT_STORAGE_CONTAINER:-rellm-dev-object-storage}"
RELLM_OBJECT_STORAGE_DATA_DIR="${RELLM_OBJECT_STORAGE_DATA_DIR:-$HOME/.rellm-object-storage-data}"

# Single source of truth for valid subcommands -- used both to dispatch (see
# bottom of file) and to answer `rellm --list-commands`, which the
# completion scripts printed by `completion()` shell out to. Keep this in
# sync with the functions defined below (nothing else auto-derives it).
RELLM_COMMANDS=(
  help
  server_and_jobs server jobs version local_instances_stop
  environment edit_environment
  local_db_create local_db_drop local_db_reset local_db_connect
  local_object_storage_start local_object_storage_create local_object_storage_delete
  delete_expired_tokens delete_unowned_media sync_sources update_user_counts convert_media_sizes renew_market_subscriptions generate_preview_images
  calculate_server_media_usage calculate_server_object_storage_usage
  set_permission delete_preview_images disable_cdn_grpc free_all_cluster_resources
  to_db_id to_proto_id grpcurl
  deploy
  completion
)

rellm_help() {
  cat <<'RELLM_HELP_EOF'
rellm - launcher for the Rellm server and its local dev dependencies

Usage: rellm <command> [args...]

Relies on Postgres's createdb/dropdb/psql for its example database (local_db_* commands),
and on Docker's docker for its example object storage (local_object_storage_* commands; S3-compatible storage).

Edit ~/.rellm (created on first run) to point DATABASE_URL, OBJECT_STORAGE_* and other environment
variables at different instances, if desired. (Or use "rellm edit_environment".)

Start server:
  rellm server

Quick setup:
  rellm local_db_create && rellm local_object_storage_create && rellm server

Commands:

  Core/Lifecycle:

    server_and_jobs          Run the Rellm server and background jobs together
                             (forks server + jobs, see below); accepts server's flags
    server                   Run the Rellm server (rellm-server)
                             --no-internal-server   Don't start the internal-only mail
                                                     delivery server (27705) used by a
                                                     Stalwart mail server -- irrelevant to
                                                     most deploys
    jobs                     Run background jobs on a loop (@@RELLM_ETC@@/rellm/background_jobs.sh) --
                             delete_expired_tokens every 2m, delete_unowned_media every 8h,
                             sync_sources every 1m, update_user_counts every 1h,
                             convert_media_sizes every 10m, renew_market_subscriptions every 1h, ...
    version                  Print the Rellm server version (rellm-server --version)
    local_instances_stop     Stop any running rellm-server processes
    help                     Show this help text

  Environment/Configuration:

    environment              Print the current config (cat ~/.rellm)
    edit_environment         Edit the config in $EDITOR (falls back to vi)

  Example Environment (will match generated default generated ~/.rellm):

    local_db_create          Create a local Postgres database (createdb rellm_dev)
    local_db_drop            Drop the local Postgres database (dropdb rellm_dev)
    local_db_reset           Stop local instances, then drop and recreate the local database
    local_db_connect         Connect to the local database with psql ($DATABASE_URL)

    local_object_storage_start
                             Start an existing local object storage docker container
    local_object_storage_create
                             Start local object storage, creating its docker container first if needed
    local_object_storage_delete
                             Stop and remove the local object storage docker container

  Background jobs:

    delete_expired_tokens    Delete expired auth tokens from the database
    delete_unowned_media     Delete media no longer referenced by any post/user/etc.
    sync_sources             Sync any SyncSource (ICS subscription) that's due, per its
                             sync_interval_seconds/last_synced_at
    update_user_counts       Recompute follower/following/friend/group/post/response/event/
                             occasion counts for every User, correcting any drift
    convert_media_sizes      Generate small/medium/large resized copies of unprocessed PNG/JPEG
                             Media via ImageMagick (`magick`, or `convert`+`identify`) and
                             MP4/QuickTime/WebM Media via `ffmpeg`+`ffprobe`; each must be on
                             your $PATH to convert its media types -- skips those media types
                             (logging an error) if missing
    renew_market_subscriptions
                             Charge/renew any due Rellm Marketplace MarketSubscription (media
                             storage/AI grant/Rellm hosting) via Stripe, applying the renewed
                             entitlement on success or ending the subscription on failure
    calculate_server_media_usage
                             Recompute MediaSettings.server_media_usage_bytes from the media
                             table, correcting any drift the incremental adjustments made at
                             CreateMedia/delete/conversion time missed
    calculate_server_object_storage_usage
                             Recompute MediaSettings.server_object_storage_usage_bytes by
                             listing and summing every object in object storage directly -- a
                             drift check against server_media_usage_bytes above
    generate_preview_images  Generate media preview images -- NOT currently supported on
                             macOS: it launches a browser hardcoded to /usr/bin/brave-browser,
                             a Linux path that Homebrew's Brave cask doesn't populate (and
                             which macOS's SIP won't let you symlink into), plus ad/cookie-
                             blocking Chrome extensions expected at
                             /opt/preview_generator_extensions/{ublock,nocookies}/

  Admin tools:

    set_permission           Grant/revoke a global permission for a user by username
                             e.g.: rellm set_permission <my_admin_username> admin on
    delete_preview_images    Delete generated preview images, e.g. to force regeneration
    disable_cdn_grpc         Disable the experimental gRPC CDN settings, as an "escape hatch" in case you
                             mess up your CDN configuration in the web UI and lose gRPC access.
    free_all_cluster_resources
                             Force-clear every held ClusterResource lock (e.g. browser) on this
                             server's cluster, if it's the conductor. Use if a generate_preview_images
                             job died holding one -- see the Cluster tab on the Server Configuration
                             page for the acquired_at time before assuming a lock is actually stuck.

  Utilities:

    to_db_id                 Convert a proto (external, string) ID to a database (internal) ID
    to_proto_id              Convert a database (internal) ID to a proto (external, string) ID
    grpcurl                  Run the bundled grpcurl. "Like curl, but for gRPC."
                             (https://github.com/fullstorydev/grpcurl)

  Deployment (requires `make` -- manage your own Kubernetes cluster):

    deploy <targets...>      Run `make` targets from the bundled deploys/Makefile, e.g.:
                               rellm deploy create_external_backend NAMESPACE=my_namespace
                               rellm deploy create_backend_data create_internal_backend NAMESPACE=my_namespace
                             NAMESPACE=... is required by nearly every target -- there's no
                             default. See @@RELLM_ETC@@/rellm/opt/deploys/README.md (bundled
                             alongside this package) for the full target reference.

  Shell completion:

    completion <bash|zsh>    Print a tab-completion script for the given shell. Homebrew
                             installs this automatically; to wire it up by hand instead
                             (`eval "$(...)"`, not `source <(...)` -- macOS's stock
                             /bin/bash (3.2) can't `source` a process substitution):
                               echo 'eval "$(rellm completion bash)"' >> ~/.bashrc
                               echo 'eval "$(rellm completion zsh)"' >> ~/.zshrc
RELLM_HELP_EOF
}

help() {
  rellm_help
}

local_db_create() {
  createdb "$RELLM_DB_NAME"
}

local_db_drop() {
  dropdb "$RELLM_DB_NAME"
}

local_db_reset() {
  local_instances_stop
  local_db_drop
  local_db_create
}

local_db_connect() {
  psql "$DATABASE_URL"
}

local_object_storage_start() {
  docker start "$RELLM_OBJECT_STORAGE_CONTAINER"
}

local_object_storage_create() {
  local_object_storage_start || _do_local_object_storage_create
}

# pgsty/silo, not quay.io/minio/minio or minio/minio -- MinIO's OSS project was archived in
# 2026: minio/minio was pulled from Docker Hub entirely (404s), and quay.io/minio/minio now
# 401s "unauthorized" on anonymous pulls of every tag. pgsty/silo is a drop-in,
# MinIO-API-compatible fork that accepts the exact same `server /data --console-address
# ":9090"` invocation and MINIO_ROOT_USER/MINIO_ROOT_PASSWORD env vars.
_do_local_object_storage_create() {
  mkdir -p "$RELLM_OBJECT_STORAGE_DATA_DIR"
  docker run -d -p 9000:9000 -p 9090:9090 --name "$RELLM_OBJECT_STORAGE_CONTAINER" -v "$RELLM_OBJECT_STORAGE_DATA_DIR:/data" -e "MINIO_ROOT_USER=$OBJECT_STORAGE_ACCESS_KEY" -e "MINIO_ROOT_PASSWORD=$OBJECT_STORAGE_SECRET_KEY" pgsty/silo:latest server /data --console-address ":9090"
}

local_object_storage_delete() {
  docker stop "$RELLM_OBJECT_STORAGE_CONTAINER"
  docker rm "$RELLM_OBJECT_STORAGE_CONTAINER"
}

local_instances_stop() {
  killall rellm-server || true
}

# Shared by every command below that execs one of the package's binaries
# (rellm-server, delete_expired_tokens, grpcurl, ...) from @@RELLM_ETC@@/rellm.
_rellm_exec_bin() {
  local bin="$1"
  shift
  cd "@@RELLM_ETC@@/rellm" && exec "./${bin}" "$@"
}

server() {
  _rellm_exec_bin rellm-server "$@"
}

# Runs background_jobs.sh (resolves its own job binaries -- see
# backend/background_jobs.sh).
jobs() {
  cd "@@RELLM_ETC@@/rellm" && exec ./background_jobs.sh "$@"
}

# Forks `server` and `jobs`, killing both if either the script exits or one
# of them dies. Any args (e.g. --no-internal-server) are forwarded to
# `server` only -- `jobs`/background_jobs.sh takes none.
server_and_jobs() {
  jobs &
  local jobs_pid=$!
  server "$@" &
  local server_pid=$!
  trap 'kill "$jobs_pid" "$server_pid" 2>/dev/null || true' EXIT TERM INT
  wait
}

version() {
  server --version
}

# Background jobs
delete_expired_tokens() {
  _rellm_exec_bin delete_expired_tokens "$@"
}

delete_unowned_media() {
  _rellm_exec_bin delete_unowned_media "$@"
}

sync_sources() {
  _rellm_exec_bin sync_sources "$@"
}

update_user_counts() {
  _rellm_exec_bin update_user_counts "$@"
}

# Resizes images via ImageMagick (`magick`, or the legacy `convert`+`identify` pair) -- e.g.
# `brew install imagemagick` -- and video via `ffmpeg`+`ffprobe` -- e.g. `brew install ffmpeg`.
# Either is optional: logs an error and skips that media type's conversion (retrying next
# interval, via `jobs`'/background_jobs.sh's loop) if its tool isn't found. Exits nonzero only
# if neither tool is found.
convert_media_sizes() {
  _rellm_exec_bin convert_media_sizes "$@"
}

renew_market_subscriptions() {
  _rellm_exec_bin renew_market_subscriptions "$@"
}

calculate_server_media_usage() {
  _rellm_exec_bin calculate_server_media_usage "$@"
}

calculate_server_object_storage_usage() {
  _rellm_exec_bin calculate_server_object_storage_usage "$@"
}

# Renders media preview images headlessly via a browser hardcoded to
# /usr/bin/brave-browser -- a Linux path, not populated by Homebrew's Brave
# cask and not writable on macOS due to SIP -- plus extensions expected at
# /opt/preview_generator_extensions/. Doesn't currently work on macOS; see
# deploys/docker/preview_generator/Dockerfile for the Linux reference setup.
generate_preview_images() {
  _rellm_exec_bin generate_preview_images "$@"
}

# Admin tools
set_permission() {
  _rellm_exec_bin set_permission "$@"
}

delete_preview_images() {
  _rellm_exec_bin delete_preview_images "$@"
}

disable_cdn_grpc() {
  _rellm_exec_bin disable_cdn_grpc "$@"
}

free_all_cluster_resources() {
  _rellm_exec_bin free_all_cluster_resources "$@"
}

# Utilities
to_db_id() {
  _rellm_exec_bin to_db_id "$@"
}

to_proto_id() {
  _rellm_exec_bin to_proto_id "$@"
}

grpcurl() {
  _rellm_exec_bin grpcurl "$@"
}

# Bundled alongside deploys/Makefile (see the "Assemble .../etc/rellm package layout" step of
# .github/workflows/server_ci_cd.yml's create_homebrew_release job) -- see deploys/distributables.sh
# for the shared `deploy`/target-listing implementation both this and docs/rellm_linux.sh use.
_rellm_deploys_dir="@@RELLM_ETC@@/rellm/opt/deploys"

# Runs `make` targets from the bundled deploys/Makefile against your own K8s cluster -- args are
# forwarded as-is, so both targets and VAR=value overrides (e.g. NAMESPACE=my_namespace, required
# by nearly every target -- see deploys/README.md) just work, same as running `make` by hand.
deploy() {
  . "$_rellm_deploys_dir/distributables.sh"
  _rellm_deploys_run "$_rellm_deploys_dir" "$@"
}

# Used by `completion`'s deploy-target completion below.
_rellm_deploy_targets() {
  [ -f "$_rellm_deploys_dir/distributables.sh" ] || return 0
  . "$_rellm_deploys_dir/distributables.sh"
  _rellm_deploys_list_targets "$_rellm_deploys_dir"
}

environment() {
  cat "$RELLM_ENV"
}

edit_environment() {
  # Intentionally unquoted: $EDITOR may be multiple words (e.g. "code --wait").
  ${EDITOR:-vi} "$RELLM_ENV"
}

# Prints a tab-completion script for the given shell. Both scripts shell out to
# `rellm --list-commands` (backed by RELLM_COMMANDS above) for top-level command completion,
# and -- once `deploy` is the first word -- to `rellm --list-deploy-targets` (backed by
# _rellm_deploy_targets, which delegates to `make`'s own Makefile parser) for target completion,
# so both stay in sync as commands/targets are added without needing to regenerate/re-source
# anything.
completion() {
  case "${1:-}" in
    bash)
      cat <<'RELLM_BASH_COMPLETION_EOF'
_rellm_complete() {
  local cur
  cur="${COMP_WORDS[COMP_CWORD]}"
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "$(rellm --list-commands)" -- "$cur") )
  elif [ "${COMP_WORDS[1]}" = "deploy" ]; then
    COMPREPLY=( $(compgen -W "$(rellm --list-deploy-targets)" -- "$cur") )
  fi
}
complete -F _rellm_complete rellm
RELLM_BASH_COMPLETION_EOF
      ;;
    zsh)
      cat <<'RELLM_ZSH_COMPLETION_EOF'
#compdef rellm
_rellm() {
  if (( CURRENT >= 3 )) && [[ ${words[2]} == deploy ]]; then
    local -a targets
    targets=(${(f)"$(rellm --list-deploy-targets)"})
    _describe 'deploy target' targets
    return
  fi
  local -a commands
  commands=(${(f)"$(rellm --list-commands)"})
  _describe 'command' commands
}
compdef _rellm rellm
RELLM_ZSH_COMPLETION_EOF
      ;;
    *)
      echo "Usage: rellm completion <bash|zsh>" >&2
      exit 1
      ;;
  esac
}

# Checks $1 against RELLM_COMMANDS -- the single source of truth used both
# here (dispatch) and by `rellm --list-commands` (completion scripts).
_rellm_is_command() {
  local c
  for c in "${RELLM_COMMANDS[@]}"; do
    [ "$c" = "$1" ] && return 0
  done
  return 1
}

cmd="${1:-help}"
if [ $# -gt 0 ]; then
  shift
fi

case "$cmd" in
  -h|--help)
    cmd=help
    ;;
esac

if [ "$cmd" = "--list-commands" ]; then
  printf '%s\n' "${RELLM_COMMANDS[@]}"
elif [ "$cmd" = "--list-deploy-targets" ]; then
  _rellm_deploy_targets
elif _rellm_is_command "$cmd"; then
  "$cmd" "$@"
else
  echo "Unknown command: $cmd" >&2
  echo >&2
  rellm_help >&2
  exit 1
fi
