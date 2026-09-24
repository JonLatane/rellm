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

local_object_storage_start:
	docker start rellm-dev-object-storage

local_object_storage_create:
	$(MAKE) local_object_storage_start || $(MAKE) _do_local_object_storage_create

# pgsty/silo, not quay.io/minio/minio -- MinIO's OSS project was archived in 2026 and
# quay.io/minio/minio now 401s "unauthorized" on anonymous pulls of every tag. pgsty/silo is
# a drop-in, MinIO-API-compatible fork that accepts the exact same `server /data
# --console-address ":9090"` invocation and MINIO_ROOT_USER/MINIO_ROOT_PASSWORD env vars.
_do_local_object_storage_create:
	docker run -d -p 9000:9000 -p 9090:9090 --name rellm-dev-object-storage -v $(MAKEFILE_DIR)/.object-storage-data:/data -e "MINIO_ROOT_USER=ROOTNAME" -e "MINIO_ROOT_PASSWORD=CHANGEME123" pgsty/silo:latest server /data --console-address ":9090"

local_object_storage_delete:
	docker stop rellm-dev-object-storage
	docker rm rellm-dev-object-storage


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
