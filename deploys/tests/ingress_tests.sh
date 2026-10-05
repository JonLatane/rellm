#!/bin/bash
# deploys/ingress targets, run through deploys/Makefile's passthroughs (as `rellm deploy` does), against
# stub kubectl.
. "$(dirname "$0")/lib.sh"
sandbox_init
begin "ingress"

routes="$SANDBOX/deploys/ingress/k8s/rellm-routes.my-site.generated.yaml"

# The shared controller is cluster-wide: no namespace, lives in INGRESS_NAMESPACE.
run bash -c 'cd "$1" && make -n -C ingress create_ingress' _ "$SANDBOX/deploys"
check_contains "create_ingress installs the controller into traefik-ingress" "$OUT" "kubectl create -f k8s/traefik.yaml --save-config -n traefik-ingress"
run bash -c 'cd "$1" && make -n -C ingress create_ingress INGRESS_NAMESPACE=elsewhere' _ "$SANDBOX/deploys"
check_contains "INGRESS_NAMESPACE is honored" "$OUT" "-n elsewhere"

# Composable output (what `$(rellm deploy get_ingress_external_ip)` relies on): just the IP.
mk get_ingress_external_ip
check_eq "get_ingress_external_ip prints only the IP" "203.0.113.7" "$OUT"

# add_ingress_domain
reset_stub_log
mk add_ingress_domain NAMESPACE=my-site
check_nonzero "add_ingress_domain without DOMAIN fails" "$STATUS"
check_contains "add_ingress_domain without DOMAIN says so" "$OUT" "DOMAIN is required"
check_not_contains "add_ingress_domain without DOMAIN doesn't touch the cluster" "$(stub_calls)" "apply"

reset_stub_log
mk add_ingress_domain NAMESPACE=my-site DOMAIN=a.example.com
check_status "add_ingress_domain NAMESPACE=my-site DOMAIN=a.example.com" 0 "$STATUS"
check_contains "applies the generated routes into the site's namespace" "$(stub_calls)" "kubectl apply -f k8s/rellm-routes.my-site.generated.yaml -n my-site"
if [ -f "$routes" ]; then
  yaml="$(cat "$routes")"
  check_contains "routes match the domain by Host" "$yaml" 'Host(`a.example.com`)'
  check_contains "routes match the domain by SNI" "$yaml" 'HostSNI(`a.example.com`)'
  check_not_contains "no leftover placeholders" "$yaml" '${'
else
  fail "add_ingress_domain should generate $routes"
fi

mk add_ingress_domain NAMESPACE=my-site DOMAIN=a.example.com EXTRA_DOMAINS="b.example.com c.example.com"
rm -f "$routes"
mk add_ingress_domain NAMESPACE=my-site DOMAIN=a.example.com EXTRA_DOMAINS="b.example.com c.example.com"
check_contains "EXTRA_DOMAINS are ORed into the Host match" "$(cat "$routes")" 'Host(`a.example.com`) || Host(`b.example.com`) || Host(`c.example.com`)'

# remove_ingress_domain
reset_stub_log
mk remove_ingress_domain NAMESPACE=my-site DOMAIN=a.example.com
check_status "remove_ingress_domain" 0 "$STATUS"
check_contains "deletes the routes from the site's namespace" "$(stub_calls)" "kubectl delete -f k8s/rellm-routes.my-site.generated.yaml -n my-site"
if [ ! -f "$routes" ]; then pass "remove_ingress_domain removes the generated file"; else fail "remove_ingress_domain should remove the generated file"; fi

# list_ingress_domains reads from the cluster (needs jq)
if command -v jq > /dev/null 2>&1; then
  mk list_ingress_domains
  check_eq "list_ingress_domains lists only rellm-http routes, as namespace: domain" "site-a: a.example.com" "$OUT"
else
  echo "  (skipping list_ingress_domains: jq not installed)"
fi

finish
