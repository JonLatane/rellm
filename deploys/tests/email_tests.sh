#!/bin/bash
# deploys/email targets, run through deploys/Makefile's passthroughs (as `rellm deploy` does), against
# stub kubectl.
. "$(dirname "$0")/lib.sh"
sandbox_init
begin "email"

# create_email_admin_secret: no default password, on purpose.
reset_stub_log
mk create_email_admin_secret
check_nonzero "create_email_admin_secret without ADMIN_PASSWORD fails" "$STATUS"
check_contains "create_email_admin_secret without ADMIN_PASSWORD says so" "$OUT" "ADMIN_PASSWORD is required"
check_not_contains "create_email_admin_secret without ADMIN_PASSWORD doesn't touch the cluster" "$(stub_calls)" "secret"

reset_stub_log
mk create_email_admin_secret ADMIN_PASSWORD=s3cret
check_status "create_email_admin_secret ADMIN_PASSWORD=s3cret (no NAMESPACE needed)" 0 "$STATUS"
check_contains "stores admin:<password> in the stalwart-admin Secret" "$(stub_calls)" "kubectl create secret generic stalwart-admin -n rellm-email --from-literal=credentials=admin:s3cret"
reset_stub_log
mk create_email_admin_secret ADMIN_PASSWORD=s3cret ADMIN_USER=root
check_contains "ADMIN_USER is honored" "$(stub_calls)" "credentials=root:s3cret"

# Composable output: just the IP.
mk deploy_email_get_ip
check_eq "deploy_email_get_ip prints only the ingress IP" "203.0.113.7" "$OUT"

# Domain management needs both NAMESPACE and DOMAIN, and checks before starting any port-forward.
mk add_email_domain
check_nonzero "add_email_domain without NAMESPACE fails" "$STATUS"
check_contains "add_email_domain without NAMESPACE says so" "$OUT" "NAMESPACE is required"
reset_stub_log
mk add_email_domain NAMESPACE=my-site
check_nonzero "add_email_domain without DOMAIN fails" "$STATUS"
check_contains "add_email_domain without DOMAIN says so" "$OUT" "DOMAIN is required"
check_not_contains "add_email_domain without DOMAIN doesn't start a port-forward" "$(stub_calls)" "port-forward"
mk remove_email_domain NAMESPACE=my-site
check_contains "remove_email_domain without DOMAIN says so" "$OUT" "DOMAIN is required"

# Rollouts/port-forward target the shared rellm-email namespace.
run bash -c 'cd "$1" && make -n -C email deploy_email_restart deploy_email_admin_port_forward' _ "$SANDBOX/deploys"
check_contains "deploy_email_restart restarts stalwart in rellm-email" "$OUT" "kubectl rollout restart deployment stalwart -n rellm-email"
check_contains "deploy_email_admin_port_forward forwards the admin UI to localhost:8080" "$OUT" "kubectl port-forward service/stalwart-admin -n rellm-email 8080:8080"

finish
