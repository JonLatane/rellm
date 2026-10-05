#!/bin/bash
#
# Source of truth for the self-updating `rellm` launcher script shipped as
# `bin/rellm` in the Linux release tarball (rellm-<version>-linux.tar.bz2).
#
# This file is copied verbatim into the tarball's `bin/rellm` (chmod +x'd)
# by the "Assemble Linux release tarball" step of the Server CI/CD workflow
# (create_linux_release job) in .github/workflows/server_ci_cd.yml -- don't
# hand-edit a downloaded tarball's bin/rellm, edit this file instead.
#
# The one placeholder below, @@RELLM_PACKAGE_BASE_DIR@@, is replaced by
# that CI step with a literal default install directory (unexpanded shell
# syntax, e.g. `$HOME/.rellm-linux`), resolved at runtime relative to
# whichever user's $HOME the script actually runs under -- so aside from
# that one substitution, this file is plain, valid, directly-runnable bash
# (e.g. `bash docs/rellm_linux.sh help` works locally; `install`, `update`,
# and `cleanup_updates` are the only subcommands that need the real
# substitution, since they manage the *canonical* install location -- every
# other command (server, version, ...) locates the package from its own
# `bin/rellm` path instead, so it works from wherever the tarball was
# extracted, until/unless `install` moves it to the canonical location.
#
set -euo pipefail

RELLM_RELEASES_REPO="jonlatane/rellm"

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
  delete_expired_tokens delete_unowned_media sync_sources update_user_counts convert_media_sizes renew_market_subscriptions generate_link_preview_images regenerate_link_preview_images_for_post
  calculate_server_media_usage calculate_server_object_storage_usage
  set_permission delete_link_preview_images disable_cdn_grpc free_all_cluster_resources
  to_db_id to_proto_id grpcurl
  deploy
  completion
  install show_latest update cleanup_updates uninstall
)

# What `rellm help` says about `rellm help deploys`: the release this package was built from (what
# `rellm-server --version` prints, i.e. the GitHub release tag without its "v"), and where
# deploys/README.md lives on GitHub as of that release. Falls back to the main branch if the server
# binary can't be run (e.g. this script is being run standalone, outside a release package).
_rellm_help_release_info() {
  local release
  release="$(server --version 2>/dev/null | head -n 1)" || release=""
  if [ -n "$release" ]; then
    RELLM_HELP_RELEASE="release $release"
    RELLM_HELP_README_URL="https://github.com/JonLatane/rellm/blob/v${release}/deploys/README.md"
  else
    RELLM_HELP_RELEASE="the main branch (this isn't a release package)"
    RELLM_HELP_README_URL="https://github.com/JonLatane/rellm/blob/main/deploys/README.md"
  fi
}

rellm_help() {
  # jobs'/deploys' real paths vary with wherever the tarball was extracted (see
  # _rellm_package_dir) -- unlike @@RELLM_PACKAGE_BASE_DIR@@ below, which
  # is only true post-`install`, so they're spliced in here instead of baked
  # into the heredoc.
  local jobs_script_path deploys_dir_path
  jobs_script_path="$(_rellm_package_dir)/background_jobs.sh"
  deploys_dir_path="$(_rellm_package_dir)/opt/deploys"
  _rellm_help_release_info
  cat <<'RELLM_HELP_EOF' | sed -e "s|@@JOBS_SCRIPT_PATH@@|$jobs_script_path|" -e "s|@@DEPLOYS_DIR_PATH@@|$deploys_dir_path|" -e "s|@@RELLM_RELEASE@@|$RELLM_HELP_RELEASE|" -e "s|@@RELLM_DEPLOYS_README_URL@@|$RELLM_HELP_README_URL|"
rellm - launcher for the Rellm server and its local dev dependencies

Usage: rellm <command> [args...]

Relies on Postgres's createdb/dropdb/psql for its example database (local_db_* commands),
and on Docker's docker for its example object storage (local_object_storage_* commands; S3-compatible storage).

Relies on `jq` and `curl` for its self-updating commands (install, show_latest, update, cleanup_updates).

Edit ~/.rellm (created on first run) to point DATABASE_URL, OBJECT_STORAGE_* and other environment
variables at different instances, if desired. (Or use "rellm edit_environment".)

Start server:
  rellm server

Quick setup:
  rellm local_db_create && rellm local_object_storage_create && rellm server

Commands:

  Core/Lifecycle:

    server_and_jobs          Run the Rellm server and background jobs together
                             (forks server + jobs, see below); accepts server's flags.
                             Output is prefixed [server]/[jobs] (stderr merged in); see
                             "Logging" below for rotation and syslog.
    server                   Run the Rellm server (rellm-server)
                             --no-internal-server   Don't start the internal-only mail
                                                     delivery server (27705) used by a
                                                     Stalwart mail server -- irrelevant to
                                                     most deploys
    jobs                     Run background jobs on a loop (@@JOBS_SCRIPT_PATH@@) --
                             delete_expired_tokens every 2m, delete_unowned_media every 8h,
                             sync_sources every 1m, update_user_counts every 1h,
                             convert_media_sizes every 10m, renew_market_subscriptions every 1h, ...
    version                  Print the Rellm server version (rellm-server --version)
    local_instances_stop     Stop any running rellm-server processes
    help                     Show this help text. `rellm help deploys` shows the deployment
                             guide (deploys/README.md) in your $PAGER (less, more, ...)

  Logging (server_and_jobs only; set in the environment or ~/.rellm):

    RELLM_LOG_FILE=<path>    Write to this file instead of stdout, rotating it
    RELLM_LOG_MAX_BYTES=<n>  Rotate at this size (default 10485760, i.e. 10 MB)
    RELLM_LOG_KEEP=<n>       Rotated files to keep (default 5): <path>.1 ... <path>.<n>
    RELLM_SYSLOG=1           Also send every line to syslog/journald (logger -t rellm)

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
    generate_link_preview_images
                             Generate preview images (the page's main image, if detected, plus a
                             screenshot with cookie banners dismissed) for posts with links that
                             don't have them yet
    regenerate_link_preview_images_for_post
                             Generate link preview images for one post, even if it already has
                             some; they're added to the post. e.g.:
                             rellm regenerate_link_preview_images_for_post <post id or proto ID>

                             Both need a Chrome, Brave, or Chromium install, auto-detected on
                             macOS (/Applications, ~/Applications), Debian/Ubuntu, Fedora/RHEL,
                             Arch, and snap. Set PREVIEW_BROWSER_PATH to use a specific binary.
                             Optional ad/cookie-blocking extensions are loaded from
                             $PREVIEW_EXTENSIONS_DIR (default /opt/preview_generator_extensions)
                             {ublock,nocookies}/ if present. See
                             deploys/docker/preview_generator/Dockerfile for a reference setup.

  Admin tools:

    set_permission           Grant/revoke a global permission for a user by username
                             e.g.: rellm set_permission <my_admin_username> admin on
    delete_link_preview_images
                             Delete generated preview images, e.g. to force regeneration
    disable_cdn_grpc         Disable the experimental gRPC CDN settings, as an "escape hatch" in case you
                             mess up your CDN configuration in the web UI and lose gRPC access.
    free_all_cluster_resources
                             Force-clear every held ClusterResource lock (e.g. browser) on this
                             server's cluster, if it's the conductor. Use if a generate_link_preview_images
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
                             default. See @@DEPLOYS_DIR_PATH@@/README.md (bundled alongside
                             this package) for the full target reference.

                             -n <ns> / --namespace <ns> work in place of NAMESPACE=<ns> (as with kubectl).
                             --domain <domain> works in place of DOMAIN=<domain> (for add_ingress_domain,
                             add_email_domain and their remove_* counterparts).
                             --confirm <namespace> works in place of CONFIRM=<namespace> (for the
                             destructive targets that ask you to retype the namespace).
                             (So to make a dry run, spell it --dry-run, not -n.)

                             Viewing logs (see "Viewing Logs" in deploys/README.md); they all take
                             -n <ns>, and --lines <n> to limit each pod's history:
                               rellm deploy view_server_logs -n my_namespace     Print the server's logs
                                                              (all replicas, merged) and return
                               rellm deploy view_job_logs -n my_namespace --tail
                                                              Follow the background jobs' logs
                               rellm deploy view_preview_generator_logs -n my_namespace
                               rellm deploy view_tmux_logs -n my_namespace       Follow Server, Jobs and
                                                              Preview Generator logs side by side in
                                                              tmux (always follows; ignores --tail)
                             --tail follows a log (like `tail -f`) instead of returning.

                             `rellm help deploys` shows the full deployment guide in your $PAGER
                             (less, more, ...). It's just a local copy of
                             @@RELLM_DEPLOYS_README_URL@@
                             as of @@RELLM_RELEASE@@.

  Shell completion:

    completion <bash|zsh>    Print a tab-completion script for the given shell. Add ONE of
                             these to your shell startup file (no package manager to hook
                             into on Linux, so this is a one-time manual step). Use
                             `eval "$(...)"`, not `source <(...)` -- the latter silently
                             does nothing on some /bin/bash builds (e.g. macOS's stock 3.2,
                             if you're testing this over there):
                               echo 'eval "$(rellm completion bash)"' >> ~/.bashrc
                               echo 'eval "$(rellm completion zsh)"' >> ~/.zshrc

  Linux self-updater subcommands (require `curl` and/or `jq`):

    install                  Move this rellm folder to its canonical location
                             (@@RELLM_PACKAGE_BASE_DIR@@), required once before `update` works
    show_latest              Print the latest Rellm release version available on GitHub
    update                   Download the latest release and install it to @@RELLM_PACKAGE_BASE_DIR@@, 
                             backing up the current install first (requires `install` first)
    cleanup_updates          Delete backups/downloads accumulated by `update`, freeing disk space
    uninstall                Delete @@RELLM_PACKAGE_BASE_DIR@@ entirely, after confirming (press y)


  Every command except `update`/`cleanup_updates` works from wherever you put
  the extracted `rellm` folder -- `install` is only needed to opt into `update`.
RELLM_HELP_EOF
}

# `rellm help deploys`: the deployment guide (deploys/README.md), in $PAGER.
_rellm_help_deploys() {
  local deploys_dir
  deploys_dir="$(_rellm_deploys_dir)"
  [ -f "$deploys_dir/distributables.sh" ] || { echo "rellm help deploys: can't find $deploys_dir/distributables.sh." >&2; exit 1; }
  . "$deploys_dir/distributables.sh"
  _rellm_deploys_help "$deploys_dir"
}

help() {
  case "${1:-}" in
    "") rellm_help ;;
    deploys) _rellm_help_deploys ;;
    *)
      echo "Unknown help topic: $1" >&2
      echo "Usage: rellm help [deploys]" >&2
      exit 1
      ;;
  esac
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
  killall rellm-server-amd64 rellm-server-arm64 || true
}

# Prints "amd64" or "arm64" to match the release asset/binary naming, or
# fails for architectures the Linux release doesn't build for (e.g. 32-bit x86).
_rellm_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      echo amd64
      ;;
    aarch64|arm64)
      echo arm64
      ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

# Deletes the arch-suffixed binaries (rellm-server-<arch>, grpcurl-<arch>,
# ...) that don't match this machine's architecture, e.g. removes every
# *-amd64 binary on an arm64 machine. Used by `install`/`update` since the
# release package ships binaries for every built architecture side-by-side,
# but only one of each pair is ever needed on a given machine.
_rellm_delete_foreign_arch_binaries() {
  local dir="$1"
  local other_arch
  case "$(_rellm_arch)" in
    amd64) other_arch=arm64 ;;
    arm64) other_arch=amd64 ;;
  esac
  rm -f "$dir"/*-"$other_arch"
}

# Resolves the package root (the dir containing rellm-server-<arch>, docs/,
# tamagui_web/, etc.) from this script's own location, i.e. wherever the
# tarball happens to be extracted -- `readlink -f` follows symlinks (e.g. a
# `ln -s .../bin/rellm /usr/local/bin/rellm`) so this still finds the
# real package dir rather than wherever the symlink itself lives.
_rellm_package_dir() {
  local script_path
  script_path="$(readlink -f "${BASH_SOURCE[0]}")"
  dirname "$(dirname "$script_path")"
}

# Shared by every command below that execs one of the package's arch-suffixed
# binaries (rellm-server-<arch>, delete_expired_tokens-<arch>, grpcurl-<arch>, ...).
_rellm_exec_bin() {
  local bin="$1"
  shift
  cd "$(_rellm_package_dir)" && exec "./${bin}-$(_rellm_arch)" "$@"
}

# --- Log handling for server_and_jobs -------------------------------------
# Every line the server and jobs print is prefixed "[server] " / "[jobs] ", with stderr (panics,
# tool errors) merged into the same stream as stdout. Each job logs like the server does,
# "[<UTC timestamp> LEVEL job_name] message" (e.g.
# "[jobs] [2026-10-05T12:00:00Z INFO  sync_sources] Syncing Sync Sources..."), so a job's own
# lines already name it; output that isn't a log record (a panic, say) is tagged "[jobs]
# [sync_sources] ..." instead (see backend/background_jobs.sh). The LEVEL in a job's lines is
# colored with ANSI escape codes -- set NO_COLOR=1 (in the environment, or in ~/.rellm) for plain
# text, e.g. when logging to RELLM_LOG_FILE or syslog. Optional environment variables
# (set in the environment, or in ~/.rellm):
#   RELLM_LOG_FILE        Append to this file (rotated, see below) instead of stdout.
#   RELLM_LOG_MAX_BYTES   Rotate RELLM_LOG_FILE once it passes this size (default
#                         10485760 = 10 MB). Rotated to FILE.1 ... FILE.<RELLM_LOG_KEEP>.
#   RELLM_LOG_KEEP        Number of rotated files to keep (default 5).
#   RELLM_SYSLOG=1        Also send every line to syslog/journald via `logger -t rellm`.
_rellm_file_size() {
  stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0
}

_rellm_rotate_log() {
  local file="$1" keep="${RELLM_LOG_KEEP:-5}" i
  rm -f "$file.$keep"
  i=$((keep - 1))
  while [ "$i" -ge 1 ]; do
    if [ -f "$file.$i" ]; then
      mv "$file.$i" "$file.$((i + 1))"
    fi
    i=$((i - 1))
  done
  mv "$file" "$file.1"
}

# Reads stdin, writes each line prefixed with "[$1] " to stdout, or to RELLM_LOG_FILE with
# size-based rotation (the file is reopened per line, so rotating under a concurrent
# writer -- server and jobs share the file -- is safe), and/or to syslog.
_rellm_log_pipe() {
  local label="$1" line count=0 max="${RELLM_LOG_MAX_BYTES:-10485760}"
  local file="${RELLM_LOG_FILE:-}"
  if [ -n "$file" ]; then
    mkdir -p "$(dirname "$file")"
  fi
  if [ "${RELLM_SYSLOG:-}" = "1" ] && command -v logger >/dev/null 2>&1; then
    exec 3> >(logger -t rellm)
  else
    exec 3>/dev/null
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="[$label] $line"
    if [ -n "$file" ]; then
      printf '%s\n' "$line" >> "$file"
      count=$((count + 1))
      if [ $((count % 50)) -eq 0 ] && [ "$(_rellm_file_size "$file")" -gt "$max" ]; then
        _rellm_rotate_log "$file"
      fi
    else
      printf '%s\n' "$line"
    fi
    printf '%s\n' "$line" >&3
  done
}

server() {
  _rellm_exec_bin rellm-server "$@"
}

# Runs background_jobs.sh (not arch-suffixed -- it's plain bash that resolves
# its own job binaries per-arch, see backend/background_jobs.sh).
jobs() {
  cd "$(_rellm_package_dir)" && exec ./background_jobs.sh "$@"
}

# Forks `server` and `jobs`, killing both if either the script exits or one
# of them dies. Any args (e.g. --no-internal-server) are forwarded to
# `server` only -- `jobs`/background_jobs.sh takes none.
# Output is labeled, merged, and optionally rotated/sent to syslog -- see
# _rellm_log_pipe above.
server_and_jobs() {
  jobs > >(_rellm_log_pipe jobs) 2>&1 &
  local jobs_pid=$!
  server "$@" > >(_rellm_log_pipe server) 2>&1 &
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
# `apt install imagemagick` -- and video via `ffmpeg`+`ffprobe` -- e.g. `apt install ffmpeg`.
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

# Renders link preview images headlessly. Needs a Chrome/Brave/Chromium install --
# auto-detected, or set PREVIEW_BROWSER_PATH. See
# deploys/docker/preview_generator/Dockerfile for a reference setup.
generate_link_preview_images() {
  _rellm_exec_bin generate_link_preview_images "$@"
}

# Same, for a single post (integer or proto ID), even if it already has previews.
regenerate_link_preview_images_for_post() {
  _rellm_exec_bin regenerate_link_preview_images_for_post "$@"
}

# Admin tools
set_permission() {
  _rellm_exec_bin set_permission "$@"
}

delete_link_preview_images() {
  _rellm_exec_bin delete_link_preview_images "$@"
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

# Bundled alongside deploys/Makefile (see the "Assemble Linux release package layout" step of
# .github/workflows/server_ci_cd.yml's create_linux_release job) -- see deploys/distributables.sh
# for the shared `deploy`/target-listing implementation both this and docs/rellm_homebrew.sh use.
# Resolved dynamically (like _rellm_exec_bin's binaries) since, unlike @@RELLM_PACKAGE_BASE_DIR@@,
# this works from wherever the tarball happens to be extracted.
_rellm_deploys_dir() {
  echo "$(_rellm_package_dir)/opt/deploys"
}

# Runs `make` targets from the bundled deploys/Makefile against your own K8s cluster -- args are
# forwarded as-is, so both targets and VAR=value overrides (e.g. NAMESPACE=my_namespace, required
# by nearly every target -- see deploys/README.md) just work, same as running `make` by hand.
deploy() {
  local deploys_dir
  deploys_dir="$(_rellm_deploys_dir)"
  . "$deploys_dir/distributables.sh"
  _rellm_deploys_run "$deploys_dir" "$@"
}

# Used by `completion`'s deploy-target completion below.
_rellm_deploy_targets() {
  local deploys_dir
  deploys_dir="$(_rellm_deploys_dir)"
  [ -f "$deploys_dir/distributables.sh" ] || return 0
  . "$deploys_dir/distributables.sh"
  _rellm_deploys_list_targets "$deploys_dir"
}

# Used by `completion`'s namespace completion after `rellm deploy ... -n`.
_rellm_deploy_namespaces() {
  local deploys_dir
  deploys_dir="$(_rellm_deploys_dir)"
  [ -f "$deploys_dir/distributables.sh" ] || return 0
  . "$deploys_dir/distributables.sh"
  _rellm_deploys_list_namespaces
}

environment() {
  cat "$RELLM_ENV"
}

edit_environment() {
  # Intentionally unquoted: $EDITOR may be multiple words (e.g. "code --wait").
  ${EDITOR:-vi} "$RELLM_ENV"
}

# Requires `curl` and `jq`. Both just need to be installed -- reading
# public release metadata doesn't require any authentication.
_rellm_latest_release_json() {
  curl -sf "https://api.github.com/repos/${RELLM_RELEASES_REPO}/releases/latest"
}

show_latest() {
  _rellm_latest_release_json | jq -r '.tag_name'
}

# `update` and `cleanup_updates` only ever manage this fixed location -- not
# wherever the package the running script belongs to happens to live -- so
# that repeated updates land in one place instead of scattering across
# however many folders someone's extracted a tarball into over time.
install() {
  local base="@@RELLM_PACKAGE_BASE_DIR@@"
  local pkg_dir
  pkg_dir="$(_rellm_package_dir)"

  if [ "$pkg_dir" = "$base" ]; then
    echo "Already installed at $base."
    return 0
  fi

  if [ -e "$base" ]; then
    local installed_version="unknown version"
    if [ -f "$base/version" ]; then
      installed_version="v$(cat "$base/version")"
    fi
    echo "$base already exists (${installed_version}). Remove it first if you want to replace it with this copy, or run 'rellm update' from within it instead." >&2
    exit 1
  fi

  mkdir -p "$(dirname "$base")"
  mv "$pkg_dir" "$base"
  _rellm_delete_foreign_arch_binaries "$base"
  echo "Installed to $base."
  echo "Run $base/bin/rellm server (consider adding $base/bin to your \$PATH)."
}

_rellm_require_installed() {
  local base="@@RELLM_PACKAGE_BASE_DIR@@"
  if [ ! -f "$base/version" ]; then
    echo "Rellm isn't installed at $base yet." >&2
    echo "Run 'rellm install' first -- it moves this rellm folder to $base," >&2
    echo "the fixed location 'update' downloads new releases into." >&2
    exit 1
  fi
}

update() {
  _rellm_require_installed

  local base="@@RELLM_PACKAGE_BASE_DIR@@"
  local updates_dir="$base/.updates"
  local arch
  arch="$(_rellm_arch)"

  local release_json
  release_json="$(_rellm_latest_release_json)"
  local latest_tag
  latest_tag="$(printf '%s' "$release_json" | jq -r '.tag_name')"
  local latest_version="${latest_tag#v}"

  local current_version="none"
  if [ -f "$base/version" ]; then
    current_version="$(cat "$base/version")"
  fi

  if [ "$current_version" = "$latest_version" ]; then
    echo "Already up to date (v${current_version})."
    return 0
  fi

  echo "Updating v${current_version} -> v${latest_version}..."

  mkdir -p "$updates_dir"

  # The release tarball is a single package containing binaries for every
  # built architecture (see $PKG/rellm-server-<arch> in create_linux_release) --
  # $arch just picks which one `server` execs, so the download itself isn't
  # per-arch. It's still validated up front so unsupported architectures fail
  # fast here instead of via a confusing exec failure from `server` later.
  local asset_name="rellm-${latest_version}-linux.tar.bz2"
  local sha_name="${asset_name}.sha256"
  local download_dir
  download_dir="$(mktemp -d)"

  local asset_url sha_url
  asset_url="$(printf '%s' "$release_json" | jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .browser_download_url')"
  sha_url="$(printf '%s' "$release_json" | jq -r --arg name "$sha_name" '.assets[] | select(.name == $name) | .browser_download_url')"
  if [ -z "$asset_url" ] || [ -z "$sha_url" ]; then
    echo "Couldn't find $asset_name and/or $sha_name among the assets of release $latest_tag." >&2
    exit 1
  fi
  curl -sL -o "$download_dir/$asset_name" "$asset_url"
  curl -sL -o "$download_dir/$sha_name" "$sha_url"

  echo "Verifying checksum..."
  (cd "$download_dir" && sha256sum -c "$sha_name")

  if [ -d "$base" ] && [ "$current_version" != "none" ]; then
    local backup_file="$updates_dir/rellm-${current_version}-backup-$(date +%Y%m%d%H%M%S).tar.bz2"
    echo "Backing up current install (v${current_version}) to $backup_file"
    tar -cjf "$backup_file" --exclude='./.updates' -C "$base" .
  fi

  mkdir -p "$base"
  tar -xjf "$download_dir/$asset_name" -C "$base"
  rm -rf "$download_dir"
  _rellm_delete_foreign_arch_binaries "$base"

  echo "Updated to v${latest_version}."
}

# `update` keeps a backup of the previous install (and downloaded tarballs
# can accumulate in $updates_dir) so rollback is possible -- this clears
# that out, which can add up to a few hundred MB per update.
cleanup_updates() {
  local updates_dir="@@RELLM_PACKAGE_BASE_DIR@@/.updates"
  if [ -d "$updates_dir" ]; then
    local freed
    freed="$(du -sh "$updates_dir" 2>/dev/null | cut -f1)"
    rm -rf "$updates_dir"
    echo "Removed $updates_dir (freed ${freed:-some space})."
  else
    echo "Nothing to clean up."
  fi
}

uninstall() {
  local base="@@RELLM_PACKAGE_BASE_DIR@@"
  if [ ! -e "$base" ]; then
    echo "Nothing installed at $base."
    return 0
  fi

  local confirm=""
  if ! read -r -p "This will permanently delete $base (including any update backups). Press y to confirm: " confirm; then
    echo
    echo "Aborted (no input)." >&2
    exit 1
  fi

  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Aborted."
    return 0
  fi

  rm -rf "$base"
  echo "Removed $base."
}

# Prints a tab-completion script for the given shell. Both scripts shell out to
# `rellm --list-commands` (backed by RELLM_COMMANDS above) for top-level command completion,
# and -- once `deploy` is the first word -- to `rellm --list-deploy-targets` (backed by
# _rellm_deploy_targets, which delegates to `make`'s own Makefile parser) for target completion,
# and, after `-n`/`--namespace`, to `rellm --list-namespaces` (the cluster's namespaces, via
# kubectl) for namespace completion,
# so both stay in sync as commands/targets are added without needing to regenerate/re-source
# anything.
completion() {
  case "${1:-}" in
    bash)
      cat <<'RELLM_BASH_COMPLETION_EOF'
_rellm_complete() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "$(rellm --list-commands)" -- "$cur") )
  elif [ "${COMP_WORDS[1]}" = "help" ]; then
    COMPREPLY=( $(compgen -W "deploys" -- "$cur") )
  elif [ "${COMP_WORDS[1]}" = "deploy" ]; then
    if [ "$prev" = "-n" ] || [ "$prev" = "--namespace" ]; then
      COMPREPLY=( $(compgen -W "$(rellm --list-namespaces)" -- "$cur") )
    elif [ "${cur#-}" != "$cur" ]; then
      COMPREPLY=( $(compgen -W "-n --namespace --domain --confirm --tail --lines" -- "$cur") )
    else
      COMPREPLY=( $(compgen -W "$(rellm --list-deploy-targets)" -- "$cur") )
    fi
  fi
}
complete -F _rellm_complete rellm
RELLM_BASH_COMPLETION_EOF
      ;;
    zsh)
      cat <<'RELLM_ZSH_COMPLETION_EOF'
#compdef rellm
_rellm() {
  if (( CURRENT >= 3 )) && [[ ${words[2]} == help ]]; then
    local -a topics
    topics=(deploys)
    _describe 'help topic' topics
    return
  fi
  if (( CURRENT >= 3 )) && [[ ${words[2]} == deploy ]]; then
    if [[ ${words[CURRENT-1]} == (-n|--namespace) ]]; then
      local -a namespaces
      namespaces=(${(f)"$(rellm --list-namespaces)"})
      _describe 'namespace' namespaces
      return
    fi
    if [[ ${words[CURRENT]} == -* ]]; then
      local -a flags
      flags=('-n:Kubernetes namespace' '--namespace:Kubernetes namespace' '--domain:Domain, for the *_domain targets' '--confirm:Retype the namespace to confirm a destructive target' '--tail:Follow logs' '--lines:Limit logs to the last N lines per pod')
      _describe 'flag' flags
      return
    fi
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
elif [ "$cmd" = "--list-namespaces" ]; then
  _rellm_deploy_namespaces
elif _rellm_is_command "$cmd"; then
  "$cmd" "$@"
else
  echo "Unknown command: $cmd" >&2
  echo >&2
  rellm_help >&2
  exit 1
fi
