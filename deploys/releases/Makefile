.NOTPARALLEL:
.DEFAULT_GOAL := release_be_local

# Configure these when building your own Rellm images. Note that you must update the following to
# point to your cloud registry rather than docker.io/jonlatane:
# - deploys/k8s/server_external.yaml
# - deploys/k8s/preview_generator.yaml
CLOUD_REGISTRY := docker.io/jonlatane
LOCAL_REGISTRY_DIRECTORY := $(HOME)/Development/registry

# You likely don't need to update this, but it's used when creating the local builder image.
LOCAL_REGISTRY := kubernetes.docker.internal:5000

# Versions are derived from TOML/YAML files, and should not be changed here.
BE_VERSION := $(shell cat ../../backend/Cargo.toml | grep 'version =' | sed -n 1p | awk '{print $$3;}' | sed 's/"//g')
FE_VERSION := $(shell cat ../../frontends/flutter/pubspec.yaml | grep 'version:' | sed -n 1p | awk '{print $$2;}' | sed 's/"//g')

get_backend_version:
	@echo $(BE_VERSION)

release_ios:
	cd ../../frontends/flutter && ./build-release ios

release_be_cloud: release_be_push_cloud
# This target rebuilds the Flutter+React apps, but does not rebuild the Rust BE
# before pushing the new image. The server Docker image is structured so that this will
# result in a very small push of only it first layer. Useful for iteration (~55s to deploy
# to two namespaces in my cluster from my old MBP), but note that
# the BE GetServiceVersion call will not match the version of the Docker image.
release_be_fe_only_cloud: release_be_fe_only_push_cloud
release_be_local: release_be_push_local

# Local registry targets for build
local_registry_start:
	docker start local-registry

local_registry_stop:
	docker stop local-registry
	docker rm local-registry

local_registry_create:
	$(MAKE) local_registry_start || docker run -d -p 5000:5000 --restart=always --name local-registry -v $(LOCAL_REGISTRY_DIRECTORY):/var/lib/registry registry:2

local_registry_destroy:
	$(MAKE) local_registry_stop; rm -rf $(LOCAL_REGISTRY_DIRECTORY)/docker

# RELEASE TARGETS (for developers)

# Flutter/React web UI release targets. Copied by deploys/docker/server/Dockerfile
release_web_builds: release_flutter_web_build release_tamagui_build
release_flutter_web_build:
	cd ../../frontends/flutter && ./build-release web
release_tamagui_build:
	cd ../../frontends/tamagui && yarn web:prod:build

# Build Environment (rellm-be-build) image targets.
release_builder_push_local: local_registry_create
	cd ../.. && docker build . -t $(LOCAL_REGISTRY)/rellm-be-build -f deploys/docker/build_environment/Dockerfile
	docker push $(LOCAL_REGISTRY)/rellm-be-build

release_builder_push_cloud:
	cd ../.. && docker build . -t $(CLOUD_REGISTRY)/rellm-be-build -f deploys/docker/build_environment/Dockerfile
	docker push $(CLOUD_REGISTRY)/rellm-be-build

# Build environment targets for build. Root of the repo lives in /opt.
build_environment_start:
	docker start rellm-build-environment
build_environment_stop:
	docker stop rellm-build-environment
	docker rm rellm-build-environment
build_environment_create: local_registry_create
	$(MAKE) build_environment_start || docker run -dit --name rellm-build-environment -v $$(cd ../.. && pwd):/opt $(LOCAL_REGISTRY)/rellm-be-build:latest
build_environment_destroy:
	$(MAKE) build_environment_stop; rm -rf $(LOCAL_REGISTRY_DIRECTORY)/docker

# Server image build targets
release_be_build_binary: ../../backend/target/release/rellm__server_release

../../backend/target/release/rellm__server_release: release_builder_push_local build_environment_create
	docker exec -it -w /opt/backend/src rellm-build-environment /bin/bash -c "cargo build --release"
	cd ../.. && mv backend/target/release/rellm backend/target/release/rellm__server_release
	cd ../.. && mv backend/target/release/disable_cdn_grpc backend/target/release/disable_cdn_grpc__server_release
	cd ../.. && mv backend/target/release/delete_expired_tokens backend/target/release/delete_expired_tokens__server_release
	cd ../.. && mv backend/target/release/delete_unowned_media backend/target/release/delete_unowned_media__server_release
	cd ../.. && mv backend/target/release/generate_link_preview_images backend/target/release/generate_link_preview_images__server_release
	cd ../.. && mv backend/target/release/delete_link_preview_images backend/target/release/delete_link_preview_images__server_release
	cd ../.. && mv backend/target/release/regenerate_link_preview_images_for_post backend/target/release/regenerate_link_preview_images_for_post__server_release
	cd ../.. && mv backend/target/release/set_permission backend/target/release/set_permission__server_release
	cd ../.. && mv backend/target/release/to_db_id backend/target/release/to_db_id__server_release
	cd ../.. && mv backend/target/release/to_proto_id backend/target/release/to_proto_id__server_release
	cd ../.. && mv backend/target/release/load_balancer backend/target/release/load_balancer__server_release

release_be_push_local: local_registry_create release_be_build_binary release_web_builds
	cd ../.. && docker build . -t $(LOCAL_REGISTRY)/rellm -f deploys/docker/server/Dockerfile
	docker push $(LOCAL_REGISTRY)/rellm
	cd ../.. && docker build . -t $(LOCAL_REGISTRY)/rellm_preview_generator -f deploys/docker/preview_generator/Dockerfile
	docker push $(LOCAL_REGISTRY)/rellm_preview_generator

release_be_push_cloud: release_be_build_binary release_web_builds _push_be_cloud_release
release_be_fe_only_push_cloud: release_web_builds _push_be_cloud_release
_push_be_cloud_release:
	cd ../.. && docker build . -t $(CLOUD_REGISTRY)/rellm:$(BE_VERSION) -f deploys/docker/server/Dockerfile
	docker push $(CLOUD_REGISTRY)/rellm:$(BE_VERSION)
	docker tag $(CLOUD_REGISTRY)/rellm:$(BE_VERSION) $(CLOUD_REGISTRY)/rellm:latest
	cd ../.. && docker build . -t $(CLOUD_REGISTRY)/rellm_preview_generator:$(BE_VERSION) -f deploys/docker/preview_generator/Dockerfile
	docker push $(CLOUD_REGISTRY)/rellm_preview_generator:$(BE_VERSION)
	docker tag $(CLOUD_REGISTRY)/rellm_preview_generator:$(BE_VERSION) $(CLOUD_REGISTRY)/rellm_preview_generator:latest
