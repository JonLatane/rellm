.NOTPARALLEL:

# create_central_storage: boots the shared Postgres + Silo (object storage) instances that many
# Rellm namespaces can point at instead of each provisioning their own -- see ../README.md's
# "Central Storage" section. Exists because most managed K8s providers cap how many PVCs a
# cluster can attach (DigitalOcean's DOKS: 15) -- each per-namespace Rellm deploy normally uses 2
# (Postgres + object storage), so that runs out fast once you're hosting more than a handful of
# domains. This deploy uses exactly 2 PVCs total, no matter how many namespaces point at it.
#
# Deliberately named STORAGE_NAMESPACE, not NAMESPACE -- ../Makefile's own NAMESPACE is a
# required, never-defaulted, per-*site* namespace (see its comment), and every target here is
# meant to be run on its own, without a site's NAMESPACE also set in the same invocation; reusing
# that name would risk silently deploying the shared instance into whichever site namespace
# happened to be set in the environment. Defaults to rellm-storage, matching ../Makefile's own
# STORAGE_NAMESPACE default -- there's normally exactly one of these per cluster, so unlike
# NAMESPACE, defaulting it is safe.
STORAGE_NAMESPACE ?= rellm-storage
# Validated since it's used unquoted below (kubectl -n, and as part of a generated hostname in
# ../k8s/server_internal_central_data.yaml) -- real Kubernetes namespace names are DNS-1123
# labels: lowercase alphanumeric or '-', starting/ending alphanumeric, max 63 chars.
ifeq ($(shell printf '%s' "$(STORAGE_NAMESPACE)" | grep -Eq '^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$$' && echo valid),)
$(error STORAGE_NAMESPACE '$(STORAGE_NAMESPACE)' is not a valid Kubernetes namespace name -- use lowercase letters, digits and '-' only, starting/ending with a letter or digit)
endif

# Selects which provider-specific k8s/*-$(K8S_PROVIDER).yaml manifests to use, same convention as
# ../Makefile's own K8S_PROVIDER.
K8S_PROVIDER ?= digitalocean

create_central_storage: create_central_postgres create_central_object_storage
update_central_storage: update_central_postgres update_central_object_storage
delete_central_storage: delete_central_postgres delete_central_object_storage
restart_central_storage: restart_central_postgres restart_central_object_storage

deploy_central_storage_ensure_namespace:
	- kubectl create namespace $(STORAGE_NAMESPACE)

# Cluster-scoped, so this is safe/idempotent to (re)apply from either create target below. Reuses
# ../k8s's copy rather than vendoring a second one.
deploy_central_storage_ensure_storageclass_retain:
	kubectl apply -f ../k8s/storageclass-retain-$(K8S_PROVIDER).yaml

# The instances' own admin credentials are randomly generated, once, into Secrets in
# $(STORAGE_NAMESPACE) -- never a checked-in value, and never regenerated if the Secret already
# exists (Postgres only reads POSTGRES_PASSWORD on a totally empty data volume, so silently
# rotating it here would just desynchronize the Secret from the real password). Sites never use
# these: provision_namespace.sh gives each one its own restricted role/user instead.
create_central_postgres_credentials: deploy_central_storage_ensure_namespace
	@command -v openssl >/dev/null || (echo "openssl is required to generate credentials" >&2 && exit 1)
	@if kubectl get secret rellm-central-postgres-credentials -n $(STORAGE_NAMESPACE) >/dev/null 2>&1; then \
		echo "rellm-central-postgres-credentials already exists -- leaving it as-is."; \
	else \
		kubectl create secret generic rellm-central-postgres-credentials -n $(STORAGE_NAMESPACE) --from-literal=password="$$(openssl rand -hex 24)"; \
	fi
create_central_object_storage_credentials: deploy_central_storage_ensure_namespace
	@command -v openssl >/dev/null || (echo "openssl is required to generate credentials" >&2 && exit 1)
	@if kubectl get secret rellm-central-object-storage-credentials -n $(STORAGE_NAMESPACE) >/dev/null 2>&1; then \
		echo "rellm-central-object-storage-credentials already exists -- leaving it as-is."; \
	else \
		kubectl create secret generic rellm-central-object-storage-credentials -n $(STORAGE_NAMESPACE) --from-literal=root-user=rellm-central-admin --from-literal=root-password="$$(openssl rand -hex 24)"; \
	fi

# K8s central Postgres deployment targets
create_central_postgres: deploy_central_storage_ensure_namespace deploy_central_storage_ensure_storageclass_retain create_central_postgres_credentials
	kubectl create -f k8s/k8s-central-postgres-pvc-$(K8S_PROVIDER).yaml --save-config -n $(STORAGE_NAMESPACE)
	kubectl create -f k8s/k8s-central-postgres-$(K8S_PROVIDER).yaml --save-config -n $(STORAGE_NAMESPACE)
update_central_postgres:
	kubectl apply -f k8s/k8s-central-postgres-$(K8S_PROVIDER).yaml -n $(STORAGE_NAMESPACE)
delete_central_postgres:
	- kubectl delete -f k8s/k8s-central-postgres-$(K8S_PROVIDER).yaml -n $(STORAGE_NAMESPACE)
# Separate from delete_central_postgres since it's rarely wanted -- see
# k8s/k8s-central-postgres-pvc-digitalocean.yaml's sibling comment for why this is split out at
# all (data itself is safe either way, PV reclaimPolicy is Retain -- this just orphans the PVC).
delete_central_postgres_pvc:
	- kubectl delete -f k8s/k8s-central-postgres-pvc-$(K8S_PROVIDER).yaml -n $(STORAGE_NAMESPACE)

# REQUESTED is what's asked for (spec.resources.requests.storage); ACTUAL is what's live
# (status.capacity.storage) -- they briefly differ mid-resize (see resize_central_postgres_pvc).
# Since this PVC holds every onboarded namespace's database, watch this rather than any single
# namespace's own usage.
get_central_postgres_pvc_size:
	kubectl get pvc central-postgres-pv-claim -n $(STORAGE_NAMESPACE) -o custom-columns='NAME:.metadata.name,REQUESTED:.spec.resources.requests.storage,ACTUAL:.status.capacity.storage,STATUS:.status.phase'

# Expands central-postgres-pv-claim in place -- no pod restart or delete/recreate needed, since
# do-block-storage-retain has allowVolumeExpansion: true (see ../k8s/storageclass-retain-*.yaml)
# and resources.requests is the one PVC field that's mutable after binding (see
# k8s/k8s-central-postgres-pvc-digitalocean.yaml's own comment on that). One-directional only --
# SIZE must be bigger than the current REQUESTED size, kubectl/the CSI driver will reject a
# shrink. This only bumps the live PVC; it deliberately does NOT touch
# k8s/k8s-central-postgres-pvc-$(K8S_PROVIDER).yaml (that file's `storage:` is just the initial
# size a brand new cluster's central Postgres is created with).
resize_central_postgres_pvc:
	@test -n "$(SIZE)" || (echo "SIZE is required, e.g. SIZE=20Gi make resize_central_postgres_pvc" && exit 1)
	@printf '%s' "$(SIZE)" | grep -Eq '^[0-9]+(\.[0-9]+)?(Ki|Mi|Gi|Ti|Pi|Ei|[kMGTPE])?$$' || (echo "SIZE '$(SIZE)' doesn't look like a valid Kubernetes storage quantity -- e.g. 5Gi, 500Mi, 1Ti (see https://kubernetes.io/docs/reference/kubernetes-api/common-definitions/quantity/)" >&2 && exit 1)
	kubectl patch pvc central-postgres-pv-claim -n $(STORAGE_NAMESPACE) --type merge -p '{"spec":{"resources":{"requests":{"storage":"$(SIZE)"}}}}'
	@echo "Requested -- expansion can take a few minutes. Check progress with: make get_central_postgres_pvc_size"

restart_central_postgres:
	kubectl rollout restart statefulset rellm-central-postgres -n $(STORAGE_NAMESPACE)
wait_central_postgres_ready:
	kubectl wait --for=condition=ready pod/rellm-central-postgres-0 -n $(STORAGE_NAMESPACE) --timeout=2m

# K8s central object storage deployment targets
create_central_object_storage: deploy_central_storage_ensure_namespace deploy_central_storage_ensure_storageclass_retain create_central_object_storage_credentials
	kubectl create -f k8s/k8s-central-object-storage-pvc-$(K8S_PROVIDER).yaml --save-config -n $(STORAGE_NAMESPACE)
	kubectl create -f k8s/k8s-central-object-storage-$(K8S_PROVIDER).yaml --save-config -n $(STORAGE_NAMESPACE)
update_central_object_storage:
	kubectl apply -f k8s/k8s-central-object-storage-$(K8S_PROVIDER).yaml -n $(STORAGE_NAMESPACE)
delete_central_object_storage:
	- kubectl delete -f k8s/k8s-central-object-storage-$(K8S_PROVIDER).yaml -n $(STORAGE_NAMESPACE)
delete_central_object_storage_pvc:
	- kubectl delete -f k8s/k8s-central-object-storage-pvc-$(K8S_PROVIDER).yaml -n $(STORAGE_NAMESPACE)

# See get_central_postgres_pvc_size's identical comment.
get_central_object_storage_pvc_size:
	kubectl get pvc central-object-storage-pv-claim -n $(STORAGE_NAMESPACE) -o custom-columns='NAME:.metadata.name,REQUESTED:.spec.resources.requests.storage,ACTUAL:.status.capacity.storage,STATUS:.status.phase'

# See resize_central_postgres_pvc's identical comment.
resize_central_object_storage_pvc:
	@test -n "$(SIZE)" || (echo "SIZE is required, e.g. SIZE=40Gi make resize_central_object_storage_pvc" && exit 1)
	@printf '%s' "$(SIZE)" | grep -Eq '^[0-9]+(\.[0-9]+)?(Ki|Mi|Gi|Ti|Pi|Ei|[kMGTPE])?$$' || (echo "SIZE '$(SIZE)' doesn't look like a valid Kubernetes storage quantity -- e.g. 5Gi, 500Mi, 1Ti (see https://kubernetes.io/docs/reference/kubernetes-api/common-definitions/quantity/)" >&2 && exit 1)
	kubectl patch pvc central-object-storage-pv-claim -n $(STORAGE_NAMESPACE) --type merge -p '{"spec":{"resources":{"requests":{"storage":"$(SIZE)"}}}}'
	@echo "Requested -- expansion can take a few minutes. Check progress with: make get_central_object_storage_pvc_size"

restart_central_object_storage:
	kubectl rollout restart statefulset rellm-central-object-storage -n $(STORAGE_NAMESPACE)
wait_central_object_storage_ready:
	kubectl wait --for=condition=ready pod/rellm-central-object-storage-0 -n $(STORAGE_NAMESPACE) --timeout=2m

get_central_storage_all:
	kubectl get all -n $(STORAGE_NAMESPACE)
