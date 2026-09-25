FROM --platform=linux/amd64 debian:testing-slim

# This hash is used by the GetServiceVersion RPC.
COPY deploys/docker/continuous_delivery_hash /opt/continuous_delivery_hash

# Rellm server binary (runs Rocket/FE/Web and Tonic/BE/gRPC services, all in one)
COPY backend/target/release/rellm__server_release /opt/rellm

# Background job binaries
COPY backend/target/release/disable_cdn_grpc__server_release /opt/disable_cdn_grpc
COPY backend/target/release/delete_expired_tokens__server_release /opt/delete_expired_tokens
COPY backend/target/release/delete_unowned_media__server_release /opt/delete_unowned_media
COPY backend/target/release/sync_sources__server_release /opt/sync_sources
COPY backend/target/release/update_user_counts__server_release /opt/update_user_counts
COPY backend/target/release/convert_media_sizes__server_release /opt/convert_media_sizes
COPY backend/target/release/renew_market_subscriptions__server_release /opt/renew_market_subscriptions
COPY backend/target/release/calculate_server_media_usage__server_release /opt/calculate_server_media_usage
COPY backend/target/release/calculate_server_object_storage_usage__server_release /opt/calculate_server_object_storage_usage

# TODO(2026-08-18): one-off backfill for the header-reconstruction bug fixed in web/email.rs
# (see build_raw_message's doc comment) -- delete this binary (backend/src/bin/repair_email_messages.rs),
# this COPY line, and its entry in server_ci_cd.yml's "Rename Rust binaries for Dockerfiles" step
# once it's been run against every deployed namespace's Messages.
COPY backend/target/release/repair_email_messages__server_release /opt/repair_email_messages

# TODO(2026-09-04): one-off repair for the EventSyncSource -> SyncSource rename's fallout (see
# fix_duplicate_synced_events.rs's own doc comment) -- delete this binary, this COPY line, and its
# entry in server_ci_cd.yml's "Rename Rust binaries for Dockerfiles" step once it's been run
# against every deployed namespace that's ever had a SyncSource.
COPY backend/target/release/fix_duplicate_synced_events__server_release /opt/fix_duplicate_synced_events

# TODO(2026-09-13): one-off cleanup for resized (small/medium/large) video Media re-muxed to MP4 by
# logic::media_conversion::resized_content_type (see its own doc comment -- Chrome refuses to play
# video/quicktime inline when a media URL is navigated to directly) -- delete this binary
# (backend/src/bin/reencode_quicktime_media.rs), this COPY line, and its entry in
# server_ci_cd.yml's "Rename Rust binaries for Dockerfiles" step once it's been run against every
# deployed namespace that's ever stored video Media.
COPY backend/target/release/reencode_quicktime_media__server_release /opt/reencode_quicktime_media

# Runs all the above background job binaries on a loop -- see backend/background_jobs.sh. Lives
# alongside them in /opt, unsuffixed, so its "./binary_name" resolution step finds them directly
# (same layout as the Homebrew macOS package). Used by the rellm-jobs Deployment in
# deploys/k8s/server_internal.yaml (& co.) instead of one k8s CronJob per job.
COPY backend/background_jobs.sh /opt/background_jobs.sh

# Admin utility binaries
COPY backend/target/release/delete_preview_images__server_release /opt/delete_preview_images
COPY backend/target/release/set_permission__server_release /opt/set_permission
COPY backend/target/release/free_all_cluster_resources__server_release /opt/free_all_cluster_resources
COPY backend/target/release/to_db_id__server_release /opt/to_db_id
COPY backend/target/release/to_proto_id__server_release /opt/to_proto_id

# Browser preview generator job binary. NOTE: USELESS (crashes) without a Chrome instance running against
# port 9222. See the Dockerfile in backend/docker/preview_generator for setup steps for Brave.
COPY backend/target/release/generate_preview_images__server_release /opt/generate_preview_images

# Flutter web app release (served from the filesystem by Rocket within Rellm)
COPY frontends/flutter/build/web/ /opt/flutter_web

# Tamagui web app release (served from the filesystem by Rocket within Rellm).
# Built twice (see apps/next/package.json's "build:export"): "out" has no basePath
# baked in (served at "/"), "out-tamagui" has basePath "/tamagui" baked in (served
# at "/tamagui") -- Next's router/asset URLs assume a single fixed basePath, so
# this can't be just one build serving both prefixes.
COPY frontends/tamagui/apps/next/out/ /opt/tamagui_web
COPY frontends/tamagui/apps/next/out-tamagui/ /opt/tamagui_web_tamagui

# Elm SPA web app release (served from the filesystem by Rocket within Rellm)
COPY frontends/elm-spa/public/ /opt/elm_web

# Generated protocol docs
COPY docs/protocol.html /opt/docs/protocol.html

# Setup the environment for the server.
# imagemagick and ffmpeg are used by /opt/convert_media_sizes (bin/convert_media_sizes.rs) to
# generate small/medium/large resized copies of PNG/JPEG and MP4/QuickTime/WebM Media, respectively.
RUN apt-get update && apt-get -y install libpq5 curl postgresql-client libc6 imagemagick ffmpeg

# Old Ubuntu OpenSSL thing
# RUN curl http://nz2.archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2.20_amd64.deb > libssl1.1.deb
# RUN dpkg -i libssl1.1.deb

# grpcurl is useful to have on a rellm instance!
RUN curl -sSL "https://github.com/fullstorydev/grpcurl/releases/download/v1.8.9/grpcurl_1.8.9_linux_x86_64.tar.gz" | tar -xz -C /opt

EXPOSE 27707 8000 80 443 8001-9000

ENTRYPOINT ["/opt/rellm"]
