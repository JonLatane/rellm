include .env
export

.NOTPARALLEL:

# Local BE dev targets
run:
	cargo run

test:
	cargo test

build:
	cargo build

clean:
	cargo clean

clean_protos:
	cargo clean -p prost-build

rebuild_fe_and_run:
	$(MAKE) -C ../frontends/tamagui rebuild_fe
	$(MAKE) run

rebuild_tamagui_and_run:
	$(MAKE) -C ../frontends/tamagui rebuild_fe
	$(MAKE) run

rebuild_elm_and_run:
	$(MAKE) -C ../frontends/elm-spa build
	$(MAKE) run

rebuild_protos: clean_protos build

local_db_create:
	createdb rellm_dev
local_db_drop:
	dropdb rellm_dev
local_db_reset: local_instances_stop local_db_drop local_db_create
local_db_connect:
	psql $(DATABASE_URL)

# Separate DB `cargo test` runs specs against (see backend/src/tests/), so specs never touch
# rellm_dev's data. Mirrors the local_db_* targets above; migrations are applied automatically
# on first test run (see src/tests/factories.rs), not here.
local_test_db_create:
	createdb rellm_test
local_test_db_drop:
	dropdb rellm_test
local_test_db_reset: local_test_db_drop local_test_db_create

MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
MAKEFILE_DIR := $(dir $(MAKEFILE_PATH))

local_minio_start:
	docker start rellm-dev-minio

local_minio_create:
	$(MAKE) local_minio_start || $(MAKE) _do_local_minio_create

# bitnamilegacy/minio, not quay.io/minio/minio -- MinIO locked down anonymous pulls of
# quay.io/minio/minio (401 "unauthorized" on every tag) after archiving the OSS project.
# bitnamilegacy/minio is Bitnami's frozen/unsupported-but-still-pullable image; it starts
# the server itself via its own entrypoint, so no `server /data` command override here.
_do_local_minio_create:
	docker run -d -p 9000:9000 -p 9090:9090 --name rellm-dev-minio -v $(MAKEFILE_DIR)/.minio-data:/bitnami/minio/data -e "MINIO_ROOT_USER=ROOTNAME" -e "MINIO_ROOT_PASSWORD=CHANGEME123" -e "MINIO_BROWSER=on" -e "MINIO_CONSOLE_PORT_NUMBER=9090" bitnamilegacy/minio:latest

local_minio_delete:
	docker stop rellm-dev-minio
	docker rm rellm-dev-minio


local_instances_stop:
	-killall rellm

prepare_integration_test: local_instances_stop
	cargo build
	(cargo run &)
	sleep 3

test_list_services: prepare_integration_test
	grpcurl $(TEST_GRPC_TARGET) list
	grpcurl $(TEST_GRPC_TARGET) list rellm.Rellm
	grpcurl $(TEST_GRPC_TARGET) rellm.Rellm/GetServiceVersion
	$(MAKE) local_instances_stop

test_authentication_local: local_db_reset prepare_integration_test
	grpcurl -plaintext -d '{"username": "test", "password": "testpass"}' localhost:27707 rellm.Rellm/CreateAccount
	! grpcurl -plaintext -d '{"username": "test", "password": "expect_error_dup_username"}' localhost:27707 rellm.Rellm/CreateAccount
	grpcurl -plaintext -d '{"username": "test", "password": "testpass"}' localhost:27707 rellm.Rellm/Login
	! grpcurl -plaintext -d '{"username": "test", "password": "expect_error_wrong_password"}' localhost:27707 rellm.Rellm/Login
	@echo ''
	@echo 'Authentication test successful.'
	@echo ''
	$(MAKE) local_instances_stop

test_authentication_remote:
	grpcurl -d '{"username": "test", "password": "testpass"}' $(TEST_GRPC_TARGET) rellm.Rellm/CreateAccount
	! grpcurl -d '{"username": "test", "password": "expect_error_dup_username"}' $(TEST_GRPC_TARGET) rellm.Rellm/CreateAccount
	grpcurl -d '{"username": "test", "password": "testpass"}' $(TEST_GRPC_TARGET) rellm.Rellm/Login
	! grpcurl -d '{"username": "test", "password": "expect_error_wrong_password"}' $(TEST_GRPC_TARGET) rellm.Rellm/Login
	@echo ''
	@echo 'Authentication test successful.'
	@echo ''
