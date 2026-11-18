#!/bin/bash
# .github/workflows/scripts/apply_backend_manifests.sh (what CI runs to deploy): what it applies,
# the image rewrite and templating, and the safety rails (missing Deployments, scaled-to-0 sites).
. "$(dirname "$0")/lib.sh"
sandbox_init
begin "CI manifest apply"

SCRIPT="$DEPLOYS_SRC/../.github/workflows/scripts/apply_backend_manifests.sh"

# Stub kubectl: `get deployment <name>` answers from $STUB_DEPLOYMENTS (space-separated
# <deployment>:<container>:<replicas>); `apply -f -` stores the manifest it was fed; the rest is recorded.
cat > "$SANDBOX/bin/kubectl" <<'STUB'
#!/bin/bash
echo "kubectl $*" >> "$STUB_LOG"
if [ "$1" = apply ]; then cat > "$STUB_LOG.applied"; exit 0; fi
if [ "$1" = get ] && [ "$2" = deployment ]; then
  for e in $STUB_DEPLOYMENTS; do
    IFS=: read -r d c r <<< "$e"
    if [ "$d" = "$3" ]; then
      case "$*" in *containers\[\*\].name*) echo "$c" ;; *spec.replicas*) echo "$r" ;; *) echo "old-image" ;; esac
    fi
  done
fi
exit 0
STUB
chmod +x "$SANDBOX/bin/kubectl"

run_script() { : > "$STUB_LOG"; rm -f "$STUB_LOG.applied"; OUT="$(bash "$SCRIPT" "$@" 2>&1)"; STATUS=$?; LOG="$(cat "$STUB_LOG")"; APPLIED="$(cat "$STUB_LOG.applied" 2>/dev/null)"; }
no_apply() { case "$LOG" in *"kubectl apply"*) fail "$1 -- but it applied" ;; *) pass "$1" ;; esac; }

export STUB_DEPLOYMENTS="rellm:rellm:2 rellm-jobs:rellm-jobs:1"
run_script server my-site 0.5.554-x u
check_status "server apply succeeds" 0 "$STATUS"
check_contains "applies into the namespace" "$LOG" "kubectl apply -f - -n my-site"
check_contains "rewrites the server image (both Deployments) to the CI tag" "$(printf '%s' "$APPLIED" | grep -c 'image: docker.io/u/rellm:0.5.554-x')" "2"
check_contains "templates \${STORAGE_NAMESPACE}" "$APPLIED" "rellm-central-object-storage.rellm-storage.svc.cluster.local"
case "$APPLIED" in *'${NAMESPACE}'*|*'${STORAGE_NAMESPACE}'*) fail "no template placeholders should remain" ;; *) pass "no template placeholders remain" ;; esac

export STUB_DEPLOYMENTS="rellm-preview-generator:rellm-preview-generator:1"
run_script preview my-site 0.5.554-x u
check_contains "preview image rewritten" "$APPLIED" "image: docker.io/u/rellm_preview_generator:0.5.554-x"

export STUB_DEPLOYMENTS="rellm-central-embedding:embedding:1"
run_script embedding rellm-storage 0.5.554-x u
check_contains "embedding applies into the storage namespace" "$LOG" "kubectl apply -f - -n rellm-storage"
check_contains "embedding image rewritten" "$APPLIED" "image: docker.io/u/rellm_embeddings:0.5.554-x"
check_contains "embedding manifest does a surge rollout" "$APPLIED" "maxUnavailable: 0"

export STUB_DEPLOYMENTS=""
run_script embedding rellm-storage 0.5.554-x u
check_status "embedding skipped when not deployed" 0 "$STATUS"; check_contains "...and says so" "$OUT" "not deployed (optional)"; no_apply "nothing applied for a missing optional Deployment"
run_script vector my-site 0.5.554-x u
check_status "vector skipped when not deployed" 0 "$STATUS"; no_apply "nothing applied for a missing vector service"
run_script server my-site 0.5.554-x u
check_nonzero "server fails when its Deployments are missing" "$STATUS"; no_apply "nothing applied when a required Deployment is missing"

export STUB_DEPLOYMENTS="rellm:rellm:0 rellm-jobs:rellm-jobs:0"
run_script server my-site 0.5.554-x u
check_status "a scaled-down site still succeeds" 0 "$STATUS"
no_apply "a site scaled to 0 is NOT applied (it would scale back up)"
check_contains "...it gets an image-only bump instead" "$LOG" "kubectl set image deployment/rellm rellm=docker.io/u/rellm:0.5.554-x -n my-site"

export STUB_DEPLOYMENTS="rellm:rellm:2 rellm-jobs:rellm-jobs:0"
run_script server my-site 0.5.554-x u
no_apply "if ANY Deployment of the component is scaled to 0, nothing is applied"

run_script bogus my-site 0.5.554-x u
check_nonzero "unknown component is rejected" "$STATUS"
run_script server 'Bad_NS' 0.5.554-x u
check_nonzero "bad namespace is rejected" "$STATUS"

finish
