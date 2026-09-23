.NOTPARALLEL:
.PHONY: protos docs
.DEFAULT_GOAL := default


default: protos docs graphs

run_backend:
	$(MAKE) -C backend run
run_elm:
	$(MAKE) -C frontends/elm-spa run
run_tamagui:
	$(MAKE) -C frontends/tamagui run
run_flutter:
	$(MAKE) -C frontends/flutter run

# Backend on the left, Elm on the right, in one tmux session -- `mouse on` lets you click a pane to
# focus it (or drag its border to resize, or click the status bar to switch windows) instead of
# needing tmux's own keybindings. Pane titles (shown via `pane-border-status`) label which is which.
# `automatic-rename off` + `rename-window`/`set-titles-string` keep the window/terminal-tab title a
# fixed "rellm: run_tmux" -- without it, tmux relabels the window after whatever's currently in the
# foreground (`make`, then `cargo`/`npx`, etc.), which is how you got a tab just called "make".
# Kills any previous `rellm` session first so re-running this is always safe.
run_tmux:
	-tmux kill-session -t rellm 2>/dev/null
	tmux new-session -d -s rellm \; \
		set-option -g mouse on \; \
		set-option -g pane-border-status top \; \
		set-option -g automatic-rename off \; \
		set-option -g set-titles on \; \
		set-option -g set-titles-string 'rellm: run_tmux' \; \
		rename-window 'rellm: run_tmux' \; \
		select-pane -T 'Backend' \; \
		send-keys 'make run_backend' C-m \; \
		split-window -h \; \
		select-pane -T 'Elm' \; \
		send-keys 'make run_elm' C-m \; \
		select-pane -L \; \
		attach-session

build_backend:
	$(MAKE) -C backend build
build_elm:
	$(MAKE) -C frontends/elm-spa build
build_tamagui:
	$(MAKE) -C frontends/tamagui build
build_flutter:
	$(MAKE) -C frontends/flutter build

test: default test_backend test_elm test_tamagui test_flutter

test_backend:
	$(MAKE) -C backend test
test_elm:
	$(MAKE) -C frontends/elm-spa test
test_tamagui:
	$(MAKE) -C frontends/tamagui test
test_flutter:
	$(MAKE) -C frontends/flutter test


############################################################################
# DEPLOYMENT-RELATED TARGETS: More in deploys/Makefile
############################################################################
# Describe your BE deployment in the current namespace.
get_backend_all:
	$(MAKE) -C deploys get_backend_all

generate_vapid_push_key_pair:
	$(MAKE) -C deploys generate_vapid_push_key_pair

# Targets for deploying Rellm to your K8s cluster.
# Internal or external refers to whether the service is exposed to the internet.
# External is the default, but internal is useful for testing, and could
# save lots of money if you want to host many servers from a single LoadBalancer/IP.
create_external_backend:
	$(MAKE) -C deploys create_external_backend
create_internal_backend:
	$(MAKE) -C deploys create_internal_backend
update_external_backend:
	$(MAKE) -C deploys update_external_backend
update_internal_backend:
	$(MAKE) -C deploys update_internal_backend
restart_backend:
	$(MAKE) -C deploys restart_backend
delete_backend:
	$(MAKE) -C deploys delete_backend
get_backend_version:
	@$(MAKE) -C deploys/releases get_backend_version

# Targets for managing an existing deployment on your K8s cluster, so you can quickly setup DNS and setup an admin.
backend_shell:
	$(MAKE) -C deploys backend_shell
get_backend_external_ip:
	$(MAKE) -C deploys get_backend_external_ip
monitor_backend_rollout:
	$(MAKE) -C deploys monitor_backend_rollout

# General targets for creating/deleting Postgres/MinIO for Rellm. For more granuar control, use deploys/Makefile directly.
create_backend_data:
	$(MAKE) -C deploys create_backend_data
delete_backend_data:
	$(MAKE) -C deploys delete_backend_data
update_backend_data:
	$(MAKE) -C deploys update_backend_data


# Manage the shared Traefik ingress (lets many Rellm instances, each in
# their own namespace/domain, share a single LoadBalancer/external IP instead
# of one each). See deploys/ingress/README.md.
create_ingress:
	$(MAKE) -C deploys/ingress create_ingress
remove_ingress:
	$(MAKE) -C deploys/ingress remove_ingress
get_ingress_external_ip:
	$(MAKE) -C deploys/ingress get_ingress_external_ip
deploy_ingress_restart:
	$(MAKE) -C deploys/ingress deploy_ingress_restart
add_ingress_domain:
	$(MAKE) -C deploys/ingress add_ingress_domain
remove_ingress_domain:
	$(MAKE) -C deploys/ingress remove_ingress_domain
list_ingress_domains:
	$(MAKE) -C deploys/ingress list_ingress_domains

# Manage the shared Stalwart mail server (lets Rellm instances receive mail at
# <username>@yourdomain without each one speaking SMTP itself). See deploys/email/README.md.
create_email_admin_secret:
	$(MAKE) -C deploys/email create_email_admin_secret
create_email:
	$(MAKE) -C deploys/email create_email
remove_email:
	$(MAKE) -C deploys/email remove_email
restart_email:
	$(MAKE) -C deploys/email restart_email
deploy_email_get_ip:
	$(MAKE) -C deploys/email deploy_email_get_ip
deploy_email_restart:
	$(MAKE) -C deploys/email deploy_email_restart
deploy_email_admin_port_forward:
	$(MAKE) -C deploys/email deploy_email_admin_port_forward
add_email_domain:
	$(MAKE) -C deploys/email add_email_domain
list_email_domains:
	$(MAKE) -C deploys/email list_email_domains

############################################################################
# BE/LOCAL TESTING/DEVOPS RESEARCH TARGETS
############################################################################
local_db_create:
	$(MAKE) -C backend local_db_create
local_db_drop:
	$(MAKE) -C backend local_db_drop
local_db_reset:
	$(MAKE) -C backend local_db_reset
local_db_connect:
	$(MAKE) -C backend local_db_connect

local_minio_create:
	$(MAKE) -C backend local_minio_create
local_minio_delete:
	$(MAKE) -C backend local_minio_delete

############################################################################
# FULLSTACK DEV/RELEASE-RELATED TARGETS: More in deploys/releases/Makefile
############################################################################

# Update frontend protos and docs
protos:
	$(MAKE) -C frontends/flutter protos
	cd frontends/tamagui && yarn protos
	$(MAKE) -C frontends/elm-spa protos

# Full-Stack dev targets
# Excludes generated Dart and TypeScript Protobuf files we save in the repo.
lines_of_code:
	git ls-files | grep -v generated | xargs cloc

# Docs-related targets: more in docs/Makefile
docs:
	$(MAKE) -C docs docs

documentation:
	$(MAKE) -C docs documentation

html_docs:
	$(MAKE) -C docs html_docs

graphs:
	$(MAKE) -C docs graphs

