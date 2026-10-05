.NOTPARALLEL:

# Namespace the shared Traefik controller itself runs in. There is normally
# only ever one of these per cluster.
INGRESS_NAMESPACE ?= traefik-ingress

# Pinned Traefik version. Keep in sync with the `image:` tag in
# k8s/traefik.yaml -- the CRDs and the controller version should always match.
TRAEFIK_VERSION ?= v3.7.9
TRAEFIK_CRDS_URL := https://raw.githubusercontent.com/traefik/traefik/$(TRAEFIK_VERSION)/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml

# NAMESPACE/DOMAIN are intentionally NOT given defaults here: every
# add_ingress_domain/remove_ingress_domain call is specific to one of *your*
# domains, and should never silently fall back to a placeholder. EXTRA_DOMAINS
# is genuinely optional (see below), so it does default to empty.
EXTRA_DOMAINS ?=

# create_ingress: the one command that sets up the shared ingress. Contains
# no domain-specific configuration whatsoever -- safe to run as-is on any
# cluster. Run this once per cluster; then use add_ingress_domain below, once
# per domain you want to route through it.
create_ingress: deploy_ingress_crds deploy_ingress_controller_create

# remove_ingress: tears down the shared controller itself (the reverse of
# create_ingress). Deliberately does NOT touch the Traefik CRDs (deleting
# those would delete every IngressRoute/IngressRouteTCP object -- i.e. every
# domain's routes -- across every namespace in the cluster, not just the
# controller) or any per-domain routes added via add_ingress_domain (those are
# left behind, harmlessly inert, in their own namespaces; clean them up
# individually with remove_ingress_domain if you want them gone too).
remove_ingress: deploy_ingress_controller_delete

deploy_ingress_ensure_namespace:
	- kubectl create namespace $(INGRESS_NAMESPACE)

# Traefik's CRDs (IngressRoute, IngressRouteTCP, etc.) are cluster-scoped and
# tied to TRAEFIK_VERSION, so we apply them straight from upstream rather than
# vendoring a copy that could drift.
deploy_ingress_crds:
	kubectl apply -f $(TRAEFIK_CRDS_URL)

deploy_ingress_controller_create: deploy_ingress_ensure_namespace
	kubectl create -f k8s/traefik.yaml --save-config -n $(INGRESS_NAMESPACE)
deploy_ingress_controller_update:
	kubectl apply -f k8s/traefik.yaml -n $(INGRESS_NAMESPACE)
	$(MAKE) deploy_ingress_monitor_rollout
# Takes down every site's HTTP(S) routing at once, so -- like deploys/Makefile's other destructive
# targets -- it needs CONFIRM=$(INGRESS_NAMESPACE) (the namespace it deletes from) typed out.
deploy_ingress_controller_delete: check_ingress_delete_confirmed
	kubectl delete -f k8s/traefik.yaml -n $(INGRESS_NAMESPACE)

check_ingress_delete_confirmed:
	@test "$(CONFIRM)" = "$(INGRESS_NAMESPACE)" || (echo "This deletes the shared Traefik controller in $(INGRESS_NAMESPACE), taking down routing for EVERY domain on the cluster. Re-run with CONFIRM=$(INGRESS_NAMESPACE)." >&2 && exit 1)

deploy_ingress_monitor_rollout:
	kubectl rollout status deployment/traefik -n $(INGRESS_NAMESPACE) --timeout 2m
deploy_ingress_restart:
	kubectl rollout restart deployment traefik -n $(INGRESS_NAMESPACE)

get_ingress_external_ip:
# Suppress echoing this so `make get_ingress_external_ip` is easily composable.
	@kubectl get service traefik -n $(INGRESS_NAMESPACE) | sed -n 2p | awk '{print $$4}'

# Per-domain routes. NAMESPACE is the existing namespace your `rellm`
# backend/DB/certs already live in (see ../README.md); DOMAIN is that
# backend's public hostname. Both are required -- there are no defaults.
#
# EXTRA_DOMAINS (optional, space-separated) lets other hostnames that front
# the same backend -- e.g. a Cloudflare/CDN proxy in front of DOMAIN using its
# own name -- match to this same namespace too. This matters because SNI
# passthrough (443/27707) and Host-based routing (80/8000) both key off the
# hostname the *client at Traefik's doorstep* presents: if something in front
# of Traefik (a CDN, a proxy) connects to it using a different hostname than
# DOMAIN, Traefik won't recognize it unless it's listed here as well.
#
# Traefik v3's Host()/HostSNI() each take exactly ONE hostname (unlike v2,
# where they took several comma-separated) -- multiple hostnames must be
# joined with explicit `||`, e.g. Host(`a`) || Host(`b`).
HOST_MATCH := $(shell printf '%s\n' $(DOMAIN) $(EXTRA_DOMAINS) | sed 's/.*/Host(`&`)/' | paste -sd'~' - | sed 's/~/ || /g')
SNI_MATCH := $(shell printf '%s\n' $(DOMAIN) $(EXTRA_DOMAINS) | sed 's/.*/HostSNI(`&`)/' | paste -sd'~' - | sed 's/~/ || /g')

k8s/rellm-routes.$(NAMESPACE).generated.yaml: k8s/rellm-routes.template.yaml
	@test -n "$(NAMESPACE)" || (echo "NAMESPACE is required, e.g. NAMESPACE=bullcitysocial DOMAIN=bullcity.social.example.com make add_ingress_domain" && exit 1)
	@test -n "$(DOMAIN)" || (echo "DOMAIN is required, e.g. NAMESPACE=bullcitysocial DOMAIN=bullcity.social.example.com make add_ingress_domain" && exit 1)
	cat k8s/rellm-routes.template.yaml | \
	  sed -e 's/$${HOST_MATCH}/$(HOST_MATCH)/g' -e 's/$${SNI_MATCH}/$(SNI_MATCH)/g' \
	  > k8s/rellm-routes.$(NAMESPACE).generated.yaml

add_ingress_domain: k8s/rellm-routes.$(NAMESPACE).generated.yaml
	kubectl apply -f k8s/rellm-routes.$(NAMESPACE).generated.yaml -n $(NAMESPACE)

remove_ingress_domain: k8s/rellm-routes.$(NAMESPACE).generated.yaml
	kubectl delete -f k8s/rellm-routes.$(NAMESPACE).generated.yaml -n $(NAMESPACE)
	rm k8s/rellm-routes.$(NAMESPACE).generated.yaml

# Lists every namespace currently wired up to the shared ingress, straight
# from the cluster (not from local *.generated.yaml files, which are
# per-machine and gitignored, so they're not a reliable inventory).
list_ingress_domains:
	@kubectl get ingressroute -A -o json | \
	  jq -r '.items[] | select(.metadata.name == "rellm-http") | "\(.metadata.namespace): \(.spec.routes[0].match)"' | \
	  sed -E 's/Host\(//g; s/\)//g' | tr -d '`'
