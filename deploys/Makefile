.NOTPARALLEL:
.DEFAULT_GOAL := release_be_local

# Configure these variables to deploy/test the official Rellm images on your own cluster.
# NAMESPACE is intentionally NOT given a default (mirroring the NAMESPACE/DOMAIN-not-defaulted
# convention in ingress/Makefile and email/Makefile) -- nearly every target here acts on a specific
# namespace, and silently defaulting to "rellm" risks operating on the wrong cluster/namespace.
# copy_server_configuration (takes SOURCE/TARGET namespaces of its own, see that target's own doc
# below) and get_all_storage_credentials (reads every namespace) are the exceptions -- they don't
# act on a single NAMESPACE, so they're carved out of this guard.
ifndef NAMESPACE
ifeq ($(filter copy_server_configuration copy_server_cluster_configuration copy_server_vapid_configuration get_all_storage_credentials,$(MAKECMDGOALS)),)
$(error NAMESPACE is required, e.g. NAMESPACE=rellm make create_external_backend)
endif
endif

# Validated once, here, rather than in each individual target -- NAMESPACE ends up not just as a
# `kubectl -n` argument (which would just reject a bad value with kubectl's own error) but
# unquoted inside a generated YAML value (server_internal_central_data.yaml's
# OBJECT_STORAGE_BUCKET/DATABASE_URL), a sed replacement (which breaks if NAMESPACE contains sed's
# own `/` delimiter) and double-quoted SQL identifiers (central_storage/provision_namespace.sh's
# `CREATE ROLE/DATABASE "$(NAMESPACE)"`) -- so catch anything but a plain Kubernetes-namespace-shaped
# value up front, with one clear error, instead of a confusing failure three steps into whichever
# target you ran. Real Kubernetes namespace names are DNS-1123 labels: lowercase alphanumeric or
# '-', starting/ending alphanumeric, max 63 chars.
ifdef NAMESPACE
ifeq ($(shell printf '%s' "$(NAMESPACE)" | grep -Eq '^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$$' && echo valid),)
$(error NAMESPACE '$(NAMESPACE)' is not a valid Kubernetes namespace name -- use lowercase letters, digits and '-' only, starting/ending with a letter or digit (e.g. NAMESPACE=my-site))
endif
endif

# Selects which provider-specific k8s/*-$(K8S_PROVIDER).yaml manifests to use for the
# DB/object storage/StorageClass targets below (e.g. "digitalocean"; "eks" or others as they're added).
K8S_PROVIDER ?= digitalocean

# Which namespace central_storage/'s shared Postgres/object storage lives in -- see
# create_internal_central_data_backend and create_backend_central_data below, and
# central_storage/README.md. Defaults to match central_storage/Makefile's own STORAGE_NAMESPACE
# default, unlike NAMESPACE itself above (which is deliberately never defaulted).
STORAGE_NAMESPACE ?= rellm-storage
# Same validation as NAMESPACE above and for the same reasons (this also ends up in a sed
# replacement and inside generated YAML, as the ${STORAGE_NAMESPACE} half of a hostname).
ifeq ($(shell printf '%s' "$(STORAGE_NAMESPACE)" | grep -Eq '^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$$' && echo valid),)
$(error STORAGE_NAMESPACE '$(STORAGE_NAMESPACE)' is not a valid Kubernetes namespace name -- use lowercase letters, digits and '-' only, starting/ending with a letter or digit)
endif

TEST_GRPC_TARGET ?= $(shell $(MAKE) get_backend_external_ip):27707

# Used by the Postgres dump/restore targets below (e.g. during upgrade_backend_postgres).
PG_UPGRADE_LOCAL_PORT ?= 15432
PG_BACKUP_DIR ?= backups
# Overrides the Postgres password used by the dump/restore targets below; by default they read it
# from this namespace's rellm-data-credentials Secret (see create_backend_data_credentials).
PG_PASSWORD ?=
pg_password = $(if $(PG_PASSWORD),$(PG_PASSWORD),$$(kubectl get secret rellm-data-credentials -n $(NAMESPACE) -o jsonpath='{.data.postgres-password}' | base64 --decode))
# Replica count restored by start_backend after a stop_backend/start_backend maintenance window.
BACKEND_REPLICAS ?= 2

# K8s server deployment targets
# Use "internal" when deploying with a separate load balancer, and 
# use deploy_be_link_lb_service_account to link the load balancer to the
# internal Rellm service.
create_external_backend: deploy_ensure_namespace create_backend_data_credentials
	kubectl create -f k8s/server_external.yaml --save-config -n $(NAMESPACE)
	kubectl create -f k8s/preview_generator.yaml --save-config -n $(NAMESPACE)
create_internal_backend: deploy_ensure_namespace create_backend_data_credentials
	kubectl create -f k8s/server_internal.yaml --save-config -n $(NAMESPACE)
	kubectl create -f k8s/preview_generator.yaml --save-config -n $(NAMESPACE)
deploy_be_internal_insecure_create: deploy_ensure_namespace create_backend_data_credentials
	kubectl create -f k8s/server_internal_insecure.yaml --save-config -n $(NAMESPACE)
	kubectl create -f k8s/preview_generator.yaml --save-config -n $(NAMESPACE)

update_external_backend:
	kubectl apply -f k8s/server_external.yaml -n $(NAMESPACE)
	kubectl apply -f k8s/preview_generator.yaml -n $(NAMESPACE)
	$(MAKE) monitor_backend_rollout
update_internal_backend:
	kubectl apply -f k8s/server_internal.yaml -n $(NAMESPACE)
	kubectl apply -f k8s/preview_generator.yaml -n $(NAMESPACE)
	$(MAKE) monitor_backend_rollout
deploy_be_internal_insecure_update:
	kubectl apply -f k8s/server_internal_insecure.yaml -n $(NAMESPACE)
	kubectl apply -f k8s/preview_generator.yaml -n $(NAMESPACE)
	$(MAKE) monitor_backend_rollout

# Like create_internal_backend/update_internal_backend above, but points the new namespace at the
# shared Postgres/object storage in central_storage/ (see central_storage/README.md) instead of
# provisioning its own -- use this once you've hit your cluster's PVC limit (DOKS caps at 15;
# a normal per-namespace deploy uses 2), or just want to avoid using 2 more per domain. Requires
# central_storage's shared instances to already exist (`make -C central_storage
# create_central_storage`) and this namespace's database to already exist (`NAMESPACE=... make
# create_backend_central_data`) -- the object storage bucket needs no such step, Rellm creates it
# itself on first use (see backend/src/object_storage_connection.rs).
create_internal_central_data_backend: deploy_ensure_namespace k8s/server_internal_central_data.$(NAMESPACE).generated.yaml k8s/preview_generator_central_data.$(NAMESPACE).generated.yaml
	kubectl create -f k8s/server_internal_central_data.$(NAMESPACE).generated.yaml --save-config -n $(NAMESPACE)
	kubectl create -f k8s/preview_generator_central_data.$(NAMESPACE).generated.yaml --save-config -n $(NAMESPACE)
# This is how manifest changes (new env vars, ports, replicas, ...) get rolled out -- CI only bumps
# image tags (see .github/workflows/scripts/set_backend_images.sh), never manifests. The manifests'
# own image tags are just the base version, so this KEEPS whatever images the namespace's
# Deployments are running right now (CI's `<version>-<sha>` tags) instead of resetting them; pass
# REPO_IMAGES=1 to deploy the manifests' tags as written instead. Regenerates the per-namespace
# manifests from the templates every time (never trusts a stale .generated.yaml).
update_internal_central_data_backend:
	rm -f k8s/server_internal_central_data.$(NAMESPACE).generated.yaml k8s/preview_generator_central_data.$(NAMESPACE).generated.yaml
	$(MAKE) --no-print-directory k8s/server_internal_central_data.$(NAMESPACE).generated.yaml k8s/preview_generator_central_data.$(NAMESPACE).generated.yaml
	@if [ -z "$(REPO_IMAGES)" ]; then \
		live_server="$$(kubectl get deployment rellm -n $(NAMESPACE) --ignore-not-found -o jsonpath='{.spec.template.spec.containers[0].image}')"; \
		live_preview="$$(kubectl get deployment rellm-preview-generator -n $(NAMESPACE) --ignore-not-found -o jsonpath='{.spec.template.spec.containers[0].image}')"; \
		if [ -n "$$live_server" ]; then \
			sed -E "s#(image: )docker\.io/jonlatane/rellm:[^ ]+#\1$$live_server#" k8s/server_internal_central_data.$(NAMESPACE).generated.yaml > k8s/server_internal_central_data.$(NAMESPACE).generated.yaml.tmp && mv k8s/server_internal_central_data.$(NAMESPACE).generated.yaml.tmp k8s/server_internal_central_data.$(NAMESPACE).generated.yaml; \
			echo "Keeping live server image: $$live_server"; \
		fi; \
		if [ -n "$$live_preview" ]; then \
			sed -E "s#(image: )docker\.io/jonlatane/rellm_preview_generator:[^ ]+#\1$$live_preview#" k8s/preview_generator_central_data.$(NAMESPACE).generated.yaml > k8s/preview_generator_central_data.$(NAMESPACE).generated.yaml.tmp && mv k8s/preview_generator_central_data.$(NAMESPACE).generated.yaml.tmp k8s/preview_generator_central_data.$(NAMESPACE).generated.yaml; \
			echo "Keeping live preview generator image: $$live_preview"; \
		fi; \
	fi
	kubectl apply -f k8s/server_internal_central_data.$(NAMESPACE).generated.yaml -n $(NAMESPACE)
	kubectl apply -f k8s/preview_generator_central_data.$(NAMESPACE).generated.yaml -n $(NAMESPACE)
	$(MAKE) monitor_backend_rollout

# Generates this namespace's copy of the ${NAMESPACE}/${STORAGE_NAMESPACE}-templated central-data
# manifests above (mirrors ingress/Makefile's k8s/rellm-routes.$(NAMESPACE).generated.yaml rule).
# Gitignored like that file, and like it, never edit the .generated.yaml directly -- edit the
# template and let this rule regenerate it.
k8s/server_internal_central_data.$(NAMESPACE).generated.yaml: k8s/server_internal_central_data.yaml
	sed -e 's/$${NAMESPACE}/$(NAMESPACE)/g' -e 's/$${STORAGE_NAMESPACE}/$(STORAGE_NAMESPACE)/g' k8s/server_internal_central_data.yaml > k8s/server_internal_central_data.$(NAMESPACE).generated.yaml
k8s/preview_generator_central_data.$(NAMESPACE).generated.yaml: k8s/preview_generator_central_data.yaml
	sed -e 's/$${NAMESPACE}/$(NAMESPACE)/g' -e 's/$${STORAGE_NAMESPACE}/$(STORAGE_NAMESPACE)/g' k8s/preview_generator_central_data.yaml > k8s/preview_generator_central_data.$(NAMESPACE).generated.yaml

delete_backend:
	kubectl delete -f k8s/server_external.yaml -n $(NAMESPACE)
	kubectl delete -f k8s/preview_generator.yaml -n $(NAMESPACE)

monitor_backend_rollout:
	kubectl rollout status deployment/rellm -n $(NAMESPACE) --timeout 2m

restart_backend:
	kubectl rollout restart deployment rellm -n $(NAMESPACE)

# Scales the app to 0 so it can't write to Postgres during maintenance (e.g. upgrade_backend_postgres).
stop_backend:
	kubectl scale deployment rellm --replicas=0 -n $(NAMESPACE)
	kubectl wait --for=delete pod -l app=rellm -n $(NAMESPACE) --timeout=60s || true

# Restores the app to BACKEND_REPLICAS after a stop_backend maintenance window.
start_backend:
	kubectl scale deployment rellm --replicas=$(BACKEND_REPLICAS) -n $(NAMESPACE)
	$(MAKE) monitor_backend_rollout

get_backend_external_ip:
# Suppress echoing this so 'make get_backend_external_ip` is easily composable. 
	@kubectl get service rellm -n $(NAMESPACE) | sed -n 2p | awk '{print $$4}'

get_backend_all:
	kubectl get all -n $(NAMESPACE)

deploy_be_get_pods:
	kubectl get pods --selector=app=rellm -n $(NAMESPACE)

backend_shell:
	kubectl exec -it $$(kubectl get pods --selector=app=rellm -n $(NAMESPACE) -o jsonpath='{.items[0].metadata.name}') -n $(NAMESPACE) -- /bin/bash

# K8s server deployment test targets
deploy_test_be:
	@echo 'Getting services on target server...'
	grpcurl $(TEST_GRPC_TARGET) list
	@echo "\nGetting Rellm service version..."
	grpcurl $(TEST_GRPC_TARGET) rellm.Rellm/GetServiceVersion
	@echo "\nGetting available Rellm RPCs..."
	grpcurl $(TEST_GRPC_TARGET) list rellm.Rellm

deploy_test_be_unsecured:
	@echo 'Getting services on target server...'
	grpcurl -plaintext $(TEST_GRPC_TARGET) list
	@echo "\nGetting Rellm service version..."
	grpcurl -plaintext $(TEST_GRPC_TARGET) rellm.Rellm/GetServiceVersion
	@echo "\nGetting available Rellm RPCs..."
	grpcurl -plaintext $(TEST_GRPC_TARGET) list rellm.Rellm

deploy_test_be_tls_openssl:
	openssl s_client -connect $(TEST_GRPC_TARGET) -CAfile generated_certs/ca.pem

# Prints EVERY storage credential Secret in the cluster, decoded, for an admin to save in a password
# manager: central storage's admin credentials (rellm-central-postgres-credentials,
# rellm-central-object-storage-credentials in $(STORAGE_NAMESPACE)), each central_storage site's
# restricted ones (rellm-central-data) and each per-namespace deploy's (rellm-data-credentials).
# Output is PLAINTEXT SECRETS -- don't paste it into chat, tickets or CI logs. A namespace that
# predates rellm-data-credentials won't show up until you run
# data_migrations/adopt_legacy_data_credentials.sh on it (its credentials are still inline in its
# Deployments until then). Needs cluster-wide `get secrets` permission.
storage_credential_secrets = rellm-central-postgres-credentials rellm-central-object-storage-credentials rellm-central-data rellm-data-credentials
get_all_storage_credentials:
	@echo "# PLAINTEXT SECRETS -- save these in your password manager; don't paste them into chat, tickets or logs." >&2
	@for name in $(storage_credential_secrets); do \
		kubectl get secret --all-namespaces --field-selector metadata.name=$$name -o go-template='{{range .items}}[{{.metadata.namespace}}/{{.metadata.name}}]{{"\n"}}{{range $$k, $$v := .data}}  {{$$k}}={{$$v | base64decode}}{{"\n"}}{{end}}{{"\n"}}{{end}}' || exit 1; \
	done

# Generates this namespace's own Postgres password and object storage credentials, randomly, into
# a rellm-data-credentials Secret -- read by k8s-postgres-*.yaml, k8s-object-storage-*.yaml and the
# server/preview-generator manifests, so no credential is ever a checked-in value. Idempotent: it
# NEVER regenerates an existing Secret (Postgres and the object storage server only read their
# credentials when initializing an empty data volume, so a new value would silently stop matching
# the real one). A namespace deployed before this existed has no such Secret: create one from its
# live values with data_migrations/adopt_legacy_data_credentials.sh instead of this target.
create_backend_data_credentials: deploy_ensure_namespace
	@command -v openssl >/dev/null || (echo "openssl is required to generate credentials" >&2 && exit 1)
	@if kubectl get secret rellm-data-credentials -n $(NAMESPACE) >/dev/null 2>&1; then \
		echo "rellm-data-credentials already exists in $(NAMESPACE) -- leaving it as-is."; \
	else \
		kubectl create secret generic rellm-data-credentials -n $(NAMESPACE) \
			--from-literal=postgres-password="$$(openssl rand -hex 24)" \
			--from-literal=object-storage-user=rellm \
			--from-literal=object-storage-password="$$(openssl rand -hex 24)"; \
	fi

create_backend_data: create_backend_postgres create_backend_object_storage
update_backend_data: update_backend_postgres update_backend_object_storage
delete_backend_data: delete_backend_postgres delete_backend_object_storage
restart_backend_data: restart_backend_postgres restart_backend_object_storage

# Central-storage counterpart to create_backend_data above: unlike that target (which provisions
# a whole new Postgres/object storage instance), this carves out this namespace's slice of the
# already-running shared instances in central_storage/ (see central_storage/README.md): a
# database + login role, a bucket + user, and a Secret (rellm-central-data) in $(NAMESPACE) with
# freshly generated random credentials for both, each restricted to only that namespace's own
# data. See central_storage/provision_namespace.sh for exactly what's created/restricted. Extra
# flags: make create_backend_central_data ARGS=--reset (drops/recreates a half-finished run).
create_backend_central_data:
	STORAGE_NAMESPACE=$(STORAGE_NAMESPACE) ./central_storage/provision_namespace.sh $(ARGS) $(NAMESPACE)

# The reverse of create_backend_central_data: PERMANENTLY deletes this namespace's central-storage
# database + role, bucket (and every object in it) + user/policy and its rellm-central-data Secret
# -- for cleaning up a smoke test (delete the namespace's site first, e.g. `kubectl delete
# namespace $(NAMESPACE)`, then run this) or retiring a site. Refuses while a `rellm` Deployment in
# the namespace still runs against central storage, and requires CONFIRM=$(NAMESPACE) explicitly.
delete_backend_central_data:
	@test "$(CONFIRM)" = "$(NAMESPACE)" || (echo "This PERMANENTLY deletes $(NAMESPACE)'s central-storage database, bucket (and all its objects) and credentials. Re-run with CONFIRM=$(NAMESPACE)." >&2 && exit 1)
	STORAGE_NAMESPACE=$(STORAGE_NAMESPACE) ./central_storage/deprovision_namespace.sh --yes $(NAMESPACE)

# Moves an already-deployed namespace's data onto central_storage/'s shared Postgres/object
# storage (takes the site down for the duration -- see that script's own header for exactly what it
# does, and doesn't, touch). Extra flags: make transition_backend_to_central_data ARGS="--yes".
transition_backend_to_central_data:
	STORAGE_NAMESPACE=$(STORAGE_NAMESPACE) ./transition_jonline_namespace_to_central_storage.sh $(ARGS) $(NAMESPACE)

# Succeeds only if this namespace's live `rellm` Deployment already points at central_storage's
# Postgres AND object storage -- guards delete_backend_data_pvcs below against removing the
# storage a site is still actually using.
check_backend_on_central_data:
	@kubectl get deployment rellm -n $(NAMESPACE) >/dev/null 2>&1 || (echo "No 'rellm' Deployment in $(NAMESPACE) -- refusing to guess whether its old data is still in use." >&2 && exit 1)
	@db_secret="$$(kubectl get deployment rellm -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DATABASE_URL")].valueFrom.secretKeyRef.name}')"; \
	os_url="$$(kubectl get deployment rellm -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="OBJECT_STORAGE_ENDPOINT")].value}')"; \
	test "$$db_secret" = "rellm-central-data" || { echo "$(NAMESPACE)'s rellm DATABASE_URL doesn't come from the rellm-central-data Secret (central Postgres) -- refusing." >&2; exit 1; }; \
	case "$$os_url" in http://rellm-central-object-storage.$(STORAGE_NAMESPACE).svc.cluster.local:*) ;; *) echo "$(NAMESPACE)'s rellm OBJECT_STORAGE_ENDPOINT is '$$os_url', not central object storage -- refusing." >&2; exit 1;; esac

# Cleans up a namespace's OLD per-namespace Postgres/object storage after
# transition_jonline_namespace_to_central_storage.sh (which deliberately leaves them alone) once
# you've verified the site works against central storage: deletes their StatefulSets/Services
# (delete_backend_data), waits for the pods to go, then deletes both PVCs (postgres-pv-claim,
# object-storage-pv-claim) -- freeing the 2 PVCs this namespace was using against the cluster
# limit. Refuses unless check_backend_on_central_data passes and CONFIRM=$(NAMESPACE) is passed
# explicitly. NOT undoable, though the underlying PVs/cloud volumes survive as "Released": PVs
# provisioned on plain do-block-storage (reclaimPolicy: Delete -- most older namespaces' Postgres
# PVCs) are patched to Retain first, so nothing is deleted with the PVC. The PV
# names are printed below; delete those PVs (and then the cloud volumes, e.g. in the DigitalOcean
# console) by hand once you're certain, which is what actually stops the billing.
delete_backend_data_pvcs: check_backend_on_central_data check_delete_backend_data_pvcs_confirmed delete_backend_data
	@pvs="$$(kubectl get pvc postgres-pv-claim object-storage-pv-claim -n $(NAMESPACE) --ignore-not-found -o jsonpath='{range .items[*]}{.spec.volumeName}{" "}{end}')"; \
	for pv in $$pvs; do kubectl patch pv $$pv --type merge -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}' || exit 1; done; \
	kubectl wait --for=delete pod/rellm-postgres-0 pod/rellm-object-storage-0 -n $(NAMESPACE) --timeout=2m 2>/dev/null; \
	kubectl delete pvc postgres-pv-claim object-storage-pv-claim -n $(NAMESPACE) --ignore-not-found && \
	kubectl delete secret rellm-data-credentials -n $(NAMESPACE) --ignore-not-found && \
	echo "Done. Retained PVs (delete with 'kubectl delete pv <name>', then remove the cloud volumes): $${pvs:-<none>}"

check_delete_backend_data_pvcs_confirmed:
	@test "$(CONFIRM)" = "$(NAMESPACE)" || (echo "This permanently deletes $(NAMESPACE)'s OLD Postgres/object storage StatefulSets and PVCs. If central storage is verified good, re-run with CONFIRM=$(NAMESPACE)." >&2 && exit 1)

# Cluster-scoped, so this is safe/idempotent to (re)apply from any namespace's create target.
deploy_ensure_storageclass_retain:
	kubectl apply -f k8s/storageclass-retain-$(K8S_PROVIDER).yaml

# K8s DB deployment targets (optional if using managed DB)
create_backend_postgres: deploy_ensure_namespace deploy_ensure_storageclass_retain create_backend_data_credentials
	kubectl create -f k8s/k8s-postgres-pvc-$(K8S_PROVIDER).yaml --save-config -n $(NAMESPACE)
	kubectl create -f k8s/k8s-postgres-$(K8S_PROVIDER).yaml --save-config -n $(NAMESPACE)

update_backend_postgres:
	kubectl apply -f k8s/k8s-postgres-$(K8S_PROVIDER).yaml -n $(NAMESPACE)

delete_backend_postgres:
	- kubectl delete -f k8s/k8s-postgres-$(K8S_PROVIDER).yaml -n $(NAMESPACE)

# Separate from delete_backend_postgres since it's rarely wanted: releases the PVC (data itself
# is safe either way, since the PV's reclaimPolicy is Retain -- see storageclass-retain-*.yaml --
# but this makes the volume unbound/orphaned from any PVC until manually reclaimed).
delete_backend_postgres_pvc:
	- kubectl delete -f k8s/k8s-postgres-pvc-$(K8S_PROVIDER).yaml -n $(NAMESPACE)

# REQUESTED is what's asked for (spec.resources.requests.storage); ACTUAL is what's live
# (status.capacity.storage) -- they briefly differ mid-resize (see resize_backend_postgres_pvc).
get_backend_postgres_pvc_size:
	kubectl get pvc postgres-pv-claim -n $(NAMESPACE) -o custom-columns='NAME:.metadata.name,REQUESTED:.spec.resources.requests.storage,ACTUAL:.status.capacity.storage,STATUS:.status.phase'

# Expands postgres-pv-claim in place -- no pod restart or delete/recreate needed, since
# do-block-storage-retain has allowVolumeExpansion: true (see k8s/storageclass-retain-*.yaml) and
# resources.requests is the one PVC field that's mutable after binding (see
# k8s/k8s-postgres-pvc-digitalocean.yaml's own comment on that). One-directional only -- SIZE must
# be bigger than the current REQUESTED size, kubectl/the CSI driver will reject a shrink. This
# only bumps the live PVC; it deliberately does NOT touch k8s/k8s-postgres-pvc-$(K8S_PROVIDER).yaml
# (that file's `storage:` is just the *initial* size a brand new namespace's PVC is created with).
resize_backend_postgres_pvc:
	@test -n "$(SIZE)" || (echo "SIZE is required, e.g. NAMESPACE=rellm SIZE=5Gi make resize_backend_postgres_pvc" && exit 1)
	@printf '%s' "$(SIZE)" | grep -Eq '^[0-9]+(\.[0-9]+)?(Ki|Mi|Gi|Ti|Pi|Ei|[kMGTPE])?$$' || (echo "SIZE '$(SIZE)' doesn't look like a valid Kubernetes storage quantity -- e.g. 5Gi, 500Mi, 1Ti (see https://kubernetes.io/docs/reference/kubernetes-api/common-definitions/quantity/)" >&2 && exit 1)
	kubectl patch pvc postgres-pv-claim -n $(NAMESPACE) --type merge -p '{"spec":{"resources":{"requests":{"storage":"$(SIZE)"}}}}'
	@echo "Requested -- expansion can take a few minutes. Check progress with: NAMESPACE=$(NAMESPACE) make get_backend_postgres_pvc_size"

restart_backend_postgres:
	kubectl rollout restart statefulset rellm-postgres -n $(NAMESPACE)

# Scales Postgres to 0. Data is untouched (PV reclaimPolicy is Retain) -- this just stops the pod.
# Run dump_backend_postgres (or upgrade_backend_postgres, which does this for you) BEFORE this,
# since it needs Postgres running to connect to.
stop_backend_postgres:
	kubectl scale statefulset rellm-postgres --replicas=0 -n $(NAMESPACE)
	kubectl wait --for=delete pod/rellm-postgres-0 -n $(NAMESPACE) --timeout=60s || true

wait_backend_postgres_ready:
	kubectl wait --for=condition=ready pod/rellm-postgres-0 -n $(NAMESPACE) --timeout=2m

# Dumps the `rellm` database (schema + data) from the currently-running rellm-postgres-0 pod
# to a local file, via a temporary port-forward. Uses the local pg_dump (works against older *or*
# newer servers), so it doubles as a general-purpose backup target and as the first step of
# upgrade_backend_postgres. Override the output path with DUMP_FILE=path/to/file.sql.
DUMP_FILE ?= $(PG_BACKUP_DIR)/$(NAMESPACE)-$(shell date +%Y%m%d%H%M%S).sql
dump_backend_postgres:
	@mkdir -p $(PG_BACKUP_DIR)
	rm -f /tmp/pgpf-$(NAMESPACE).log; \
	kubectl port-forward -n $(NAMESPACE) rellm-postgres-0 $(PG_UPGRADE_LOCAL_PORT):5432 >/tmp/pgpf-$(NAMESPACE).log 2>&1 & \
	echo $$! > /tmp/pgpf-$(NAMESPACE).pid; \
	for i in 1 2 3 4 5 6 7 8 9 10; do grep -q "Forwarding from" /tmp/pgpf-$(NAMESPACE).log 2>/dev/null && break; sleep 1; done; \
	if ! grep -q "Forwarding from" /tmp/pgpf-$(NAMESPACE).log 2>/dev/null; then \
		echo "ERROR: port-forward to $(NAMESPACE)/rellm-postgres-0 on port $(PG_UPGRADE_LOCAL_PORT) never came up (port may already be in use by another tunnel -- check /tmp/pgpf-$(NAMESPACE).log, or override PG_UPGRADE_LOCAL_PORT)" >&2; \
		cat /tmp/pgpf-$(NAMESPACE).log >&2; \
		kill $$(cat /tmp/pgpf-$(NAMESPACE).pid) 2>/dev/null; \
		rm -f /tmp/pgpf-$(NAMESPACE).pid; \
		exit 1; \
	fi; \
	PGPASSWORD="$(pg_password)" pg_dump -h localhost -p $(PG_UPGRADE_LOCAL_PORT) -U admin -d rellm --clean --if-exists -f $(DUMP_FILE); \
	DUMP_STATUS=$$?; \
	kill $$(cat /tmp/pgpf-$(NAMESPACE).pid) 2>/dev/null; \
	rm -f /tmp/pgpf-$(NAMESPACE).pid; \
	exit $$DUMP_STATUS

# Restores a dump produced by dump_backend_postgres into the currently-running rellm-postgres-0
# pod (must already have an empty/initialized `rellm` database -- i.e. run this after
# update_backend_postgres has brought up the new version). Usage: make restore_backend_postgres
# DUMP_FILE=backups/foo.sql
# Retries once on failure -- the dump's --clean --if-exists means a full re-run is idempotent even
# if a prior attempt got partway through (e.g. kubectl port-forward's SPDY tunnel dropping mid-COPY
# under a large transfer, which happens occasionally and isn't a sign of real DB corruption).
restore_backend_postgres:
	@test -n "$(DUMP_FILE)" || (echo "Usage: make restore_backend_postgres DUMP_FILE=path/to/dump.sql NAMESPACE=..." >&2 && exit 1)
	for attempt in 1 2; do \
		rm -f /tmp/pgpf-$(NAMESPACE).log; \
		kubectl port-forward -n $(NAMESPACE) rellm-postgres-0 $(PG_UPGRADE_LOCAL_PORT):5432 >/tmp/pgpf-$(NAMESPACE).log 2>&1 & \
		echo $$! > /tmp/pgpf-$(NAMESPACE).pid; \
		for i in 1 2 3 4 5 6 7 8 9 10; do grep -q "Forwarding from" /tmp/pgpf-$(NAMESPACE).log 2>/dev/null && break; sleep 1; done; \
		if ! grep -q "Forwarding from" /tmp/pgpf-$(NAMESPACE).log 2>/dev/null; then \
			echo "ERROR: port-forward to $(NAMESPACE)/rellm-postgres-0 on port $(PG_UPGRADE_LOCAL_PORT) never came up (port may already be in use by another tunnel -- check /tmp/pgpf-$(NAMESPACE).log, or override PG_UPGRADE_LOCAL_PORT)" >&2; \
			cat /tmp/pgpf-$(NAMESPACE).log >&2; \
			kill $$(cat /tmp/pgpf-$(NAMESPACE).pid) 2>/dev/null; \
			rm -f /tmp/pgpf-$(NAMESPACE).pid; \
			exit 1; \
		fi; \
		PGPASSWORD="$(pg_password)" psql -h localhost -p $(PG_UPGRADE_LOCAL_PORT) -U admin -d rellm -v ON_ERROR_STOP=1 -f $(DUMP_FILE); \
		RESTORE_STATUS=$$?; \
		kill $$(cat /tmp/pgpf-$(NAMESPACE).pid) 2>/dev/null; \
		rm -f /tmp/pgpf-$(NAMESPACE).pid; \
		if [ $$RESTORE_STATUS -eq 0 ]; then exit 0; fi; \
		echo "restore_backend_postgres: attempt $$attempt failed (status $$RESTORE_STATUS)$$([ $$attempt -eq 1 ] && echo ', retrying...' || echo '.')" >&2; \
	done; \
	exit 1

# Full Postgres major-version upgrade: dumps the live (old-version) database, stops the app and
# Postgres, applies the new k8s-postgres-$(K8S_PROVIDER).yaml (new image + new subPath, so the
# new version initdb's a fresh data directory alongside -- not over -- the old one), restores the
# dump into it, then brings the app back up. The old version's data directory is left in place on
# the same PVC as an instant rollback; once you've confirmed the app is healthy on the new
# version, clean it up by hand with delete_backend_postgres_old_data.
upgrade_backend_postgres:
	@echo "== Upgrading Postgres in namespace $(NAMESPACE) (see k8s/k8s-postgres-$(K8S_PROVIDER).yaml for target version) =="
	$(MAKE) dump_backend_postgres NAMESPACE=$(NAMESPACE) DUMP_FILE=$(PG_BACKUP_DIR)/$(NAMESPACE)-preupgrade.sql
	$(MAKE) stop_backend NAMESPACE=$(NAMESPACE)
	$(MAKE) stop_backend_postgres NAMESPACE=$(NAMESPACE)
	$(MAKE) update_backend_postgres NAMESPACE=$(NAMESPACE)
	$(MAKE) wait_backend_postgres_ready NAMESPACE=$(NAMESPACE)
	$(MAKE) restore_backend_postgres NAMESPACE=$(NAMESPACE) DUMP_FILE=$(PG_BACKUP_DIR)/$(NAMESPACE)-preupgrade.sql
	$(MAKE) start_backend NAMESPACE=$(NAMESPACE)
	@echo "== Done. Verify the app, then (once confident) run: make delete_backend_postgres_old_data NAMESPACE=$(NAMESPACE) =="

# DESTRUCTIVE, manual-only: permanently deletes the pre-upgrade Postgres data directory left
# behind (at PVC subPath "postgres") by upgrade_backend_postgres. Only run this per-namespace,
# once you've confirmed the app is healthy on the new version -- there is no undo.
delete_backend_postgres_old_data:
	@echo "This permanently deletes the pre-upgrade Postgres data at postgres-pv-claim:/postgres in namespace $(NAMESPACE)."
	kubectl exec -n $(NAMESPACE) rellm-postgres-0 -- rm -rf /var/lib/postgresql/data/postgres

# K8s object storage deployment targets (optional if using managed S3/object storage)
create_backend_object_storage: deploy_ensure_namespace deploy_ensure_storageclass_retain create_backend_data_credentials
	kubectl create -f k8s/k8s-object-storage-pvc-$(K8S_PROVIDER).yaml --save-config -n $(NAMESPACE)
	kubectl create -f k8s/k8s-object-storage-$(K8S_PROVIDER).yaml --save-config -n $(NAMESPACE)

update_backend_object_storage:
	kubectl apply -f k8s/k8s-object-storage-$(K8S_PROVIDER).yaml -n $(NAMESPACE)

delete_backend_object_storage:
	- kubectl delete -f k8s/k8s-object-storage-$(K8S_PROVIDER).yaml -n $(NAMESPACE)

# Separate from delete_backend_object_storage since it's rarely wanted: releases the PVC (data
# itself is safe either way, since the PV's reclaimPolicy is Retain -- see
# storageclass-retain-*.yaml -- but this makes the volume unbound/orphaned from any PVC until
# manually reclaimed).
delete_backend_object_storage_pvc:
	- kubectl delete -f k8s/k8s-object-storage-pvc-$(K8S_PROVIDER).yaml -n $(NAMESPACE)

# See get_backend_postgres_pvc_size's identical comment.
get_backend_object_storage_pvc_size:
	kubectl get pvc object-storage-pv-claim -n $(NAMESPACE) -o custom-columns='NAME:.metadata.name,REQUESTED:.spec.resources.requests.storage,ACTUAL:.status.capacity.storage,STATUS:.status.phase'

# See resize_backend_postgres_pvc's identical comment.
resize_backend_object_storage_pvc:
	@test -n "$(SIZE)" || (echo "SIZE is required, e.g. NAMESPACE=rellm SIZE=10Gi make resize_backend_object_storage_pvc" && exit 1)
	@printf '%s' "$(SIZE)" | grep -Eq '^[0-9]+(\.[0-9]+)?(Ki|Mi|Gi|Ti|Pi|Ei|[kMGTPE])?$$' || (echo "SIZE '$(SIZE)' doesn't look like a valid Kubernetes storage quantity -- e.g. 5Gi, 500Mi, 1Ti (see https://kubernetes.io/docs/reference/kubernetes-api/common-definitions/quantity/)" >&2 && exit 1)
	kubectl patch pvc object-storage-pv-claim -n $(NAMESPACE) --type merge -p '{"spec":{"resources":{"requests":{"storage":"$(SIZE)"}}}}'
	@echo "Requested -- expansion can take a few minutes. Check progress with: NAMESPACE=$(NAMESPACE) make get_backend_object_storage_pvc_size"

restart_backend_object_storage:
	kubectl rollout restart statefulset rellm-object-storage -n $(NAMESPACE)

wait_backend_object_storage_ready:
	kubectl wait --for=condition=ready pod/rellm-object-storage-0 -n $(NAMESPACE) --timeout=2m

# Useful things
deploy_ensure_namespace:
	- kubectl create namespace $(NAMESPACE)

# Certificate-related targets
get_backend_generated_certs:
	kubectl get secret rellm-generated-tls -n $(NAMESPACE)
get_backend_generated_ca_certs:
	kubectl get configmap rellm-generated-ca -n $(NAMESPACE)

# Web Push-related targets
# Generates a VAPID keypair for Web Push notifications (see `backend/src/web_push`) -- paste the
# printed Public/Private Key into a server's Web Push Configuration (FederationTab.elm, as an
# admin) or directly into that server's `server_configurations.web_push_config` JSONB column.
generate_vapid_push_key_pair:
	npx web-push generate-vapid-keys

############################################################################
# INGRESS-RELATED TARGETS: passthroughs to deploys/ingress/Makefile (mirrors the root
# Makefile's own passthroughs to this Makefile), so `rellm deploy <target>` -- which only ever
# runs `make -C deploys` -- can also reach ingress/email/cert targets without a separate `-C`.
############################################################################
create_ingress:
	$(MAKE) -C ingress create_ingress
remove_ingress:
	$(MAKE) -C ingress remove_ingress
deploy_ingress_ensure_namespace:
	$(MAKE) -C ingress deploy_ingress_ensure_namespace
deploy_ingress_crds:
	$(MAKE) -C ingress deploy_ingress_crds
deploy_ingress_controller_create:
	$(MAKE) -C ingress deploy_ingress_controller_create
deploy_ingress_controller_update:
	$(MAKE) -C ingress deploy_ingress_controller_update
deploy_ingress_controller_delete:
	$(MAKE) -C ingress deploy_ingress_controller_delete
deploy_ingress_monitor_rollout:
	$(MAKE) -C ingress deploy_ingress_monitor_rollout
deploy_ingress_restart:
	$(MAKE) -C ingress deploy_ingress_restart
get_ingress_external_ip:
	$(MAKE) -C ingress get_ingress_external_ip
add_ingress_domain:
	$(MAKE) -C ingress add_ingress_domain
remove_ingress_domain:
	$(MAKE) -C ingress remove_ingress_domain
list_ingress_domains:
	$(MAKE) -C ingress list_ingress_domains

############################################################################
# EMAIL-RELATED TARGETS: passthroughs to deploys/email/Makefile. See that Makefile's own
# comments for the create_email_admin_secret -> create_email -> add_email_domain ordering.
############################################################################
create_email:
	$(MAKE) -C email create_email
update_email:
	$(MAKE) -C email update_email
restart_email:
	$(MAKE) -C email restart_email
remove_email:
	$(MAKE) -C email remove_email
create_email_admin_secret:
	$(MAKE) -C email create_email_admin_secret
deploy_email_get_ip:
	$(MAKE) -C email deploy_email_get_ip
deploy_email_restart:
	$(MAKE) -C email deploy_email_restart
deploy_email_monitor_rollout:
	$(MAKE) -C email deploy_email_monitor_rollout
deploy_email_admin_port_forward:
	$(MAKE) -C email deploy_email_admin_port_forward
deploy_email_admin_stop_port_forwarding:
	$(MAKE) -C email deploy_email_admin_stop_port_forwarding
add_email_domain:
	$(MAKE) -C email add_email_domain
remove_email_domain:
	$(MAKE) -C email remove_email_domain
list_email_domains:
	$(MAKE) -C email list_email_domains

############################################################################
# CENTRAL STORAGE-RELATED TARGETS: passthroughs to deploys/central_storage/Makefile. See that
# directory's README.md -- create_backend_central_data/create_internal_central_data_backend
# above are what you actually run per-namespace once the shared instances below exist.
############################################################################
create_central_storage:
	$(MAKE) -C central_storage create_central_storage
update_central_storage:
	$(MAKE) -C central_storage update_central_storage
delete_central_storage:
	$(MAKE) -C central_storage delete_central_storage
restart_central_storage:
	$(MAKE) -C central_storage restart_central_storage
get_central_storage_all:
	$(MAKE) -C central_storage get_central_storage_all

############################################################################
# TLS CERTIFICATE-RELATED TARGETS: passthroughs to deploys/generated_certs/Makefile.
# get_backend_generated_certs, get_backend_generated_ca_certs and deploy_ensure_namespace are
# deliberately NOT re-passed-through here -- generated_certs/Makefile duplicates those three
# verbatim (for standalone use from within that directory), and this Makefile already defines
# them itself above.
############################################################################
deploy_certmanager:
	$(MAKE) -C generated_certs deploy_certmanager
deploy_certmanager_credential:
	$(MAKE) -C generated_certs deploy_certmanager_credential
deploy_certmanager_credential_apply:
	$(MAKE) -C generated_certs deploy_certmanager_credential_apply
deploy_certmanager_credential_clean:
	$(MAKE) -C generated_certs deploy_certmanager_credential_clean
deploy_certmanager_credential_digitalocean_clean:
	$(MAKE) -C generated_certs deploy_certmanager_credential_digitalocean_clean
deploy_certmanager_credential_digitalocean_store_apitoken:
	$(MAKE) -C generated_certs deploy_certmanager_credential_digitalocean_store_apitoken
deploy_certmanager_credential_digitalocean_prepare:
	$(MAKE) -C generated_certs deploy_certmanager_credential_digitalocean_prepare
deploy_certmanager_credential_digitalocean_apply:
	$(MAKE) -C generated_certs deploy_certmanager_credential_digitalocean_apply
deploy_certmanager_credential_digitalocean_delete:
	$(MAKE) -C generated_certs deploy_certmanager_credential_digitalocean_delete
certs_generate:
	$(MAKE) -C generated_certs certs_generate
certs_ca_generate:
	$(MAKE) -C generated_certs certs_ca_generate
certs_server_generate:
	$(MAKE) -C generated_certs certs_server_generate
certs_store_in_k8s:
	$(MAKE) -C generated_certs certs_store_in_k8s
certs_delete_from_k8s:
	$(MAKE) -C generated_certs certs_delete_from_k8s
certs_server_store_in_k8s:
	$(MAKE) -C generated_certs certs_server_store_in_k8s
certs_server_delete_from_k8s:
	$(MAKE) -C generated_certs certs_server_delete_from_k8s
certs_ca_store_in_k8s:
	$(MAKE) -C generated_certs certs_ca_store_in_k8s
certs_ca_delete_from_k8s:
	$(MAKE) -C generated_certs certs_ca_delete_from_k8s
certs_gen_test:
	$(MAKE) -C generated_certs certs_gen_test
certs_gen_test_pass_openssl_verify:
	$(MAKE) -C generated_certs certs_gen_test_pass_openssl_verify

# Copies one server_configurations column (e.g. stripe_config, twilio_config) from SOURCE's
# active row to TARGET's -- see copy_server_configuration.sh's own doc for exactly how (clones
# TARGET's active row with the new value, retires the old one, all in a transaction, same
# pattern ConfigureServer itself uses). SOURCE/TARGET/COLUMN, not NAMESPACE -- this is the one
# target in this Makefile that acts on two namespaces at once (see the NAMESPACE guard above).
#
#   make copy_server_configuration SOURCE=rellm-org TARGET=jonline COLUMN=stripe_config
copy_server_configuration:
	./copy_server_configuration.sh --source $(SOURCE) --destination $(TARGET) --column $(COLUMN)

# Like copy_server_configuration for cluster_resources, but also replaces the copied value's
# namespace_id with TARGET, so TARGET identifies itself to the cluster conductor as itself.
#
#   make copy_server_cluster_configuration SOURCE=rellm-org TARGET=neurospicysteve-bullcity-social
copy_server_cluster_configuration:
	./copy_server_configuration.sh --source $(SOURCE) --destination $(TARGET) --column cluster_resources --set-cluster-namespace-id

# Convenience for copying web_push_config (the VAPID keypair) -- see copy_server_configuration.
#
#   make copy_server_vapid_configuration SOURCE=rellm-org TARGET=neurospicysteve-bullcity-social
copy_server_vapid_configuration:
	./copy_server_configuration.sh --source $(SOURCE) --destination $(TARGET) --column web_push_config
