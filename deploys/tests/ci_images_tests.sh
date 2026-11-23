#!/bin/bash
# .github/workflows/scripts/set_backend_images.sh (what CI runs to deploy): which Deployments and
# containers each component bumps, and that the optional ones (embedding, vector) skip when absent.
. "$(dirname "$0")/lib.sh"
sandbox_init
begin "CI image bumps"

SCRIPT="$DEPLOYS_SRC/../.github/workflows/scripts/set_backend_images.sh"

# Replaces the stub kubectl: `get deployment <name>` answers from $STUB_DEPLOYMENTS (space-separated
# <deployment>:<container>:<image>), everything else is just recorded.
cat > "$SANDBOX/bin/kubectl" <<'STUB'
#!/bin/bash
echo "kubectl $*" >> "$STUB_LOG"
if [ "$1" = get ] && [ "$2" = deployment ]; then
  for e in $STUB_DEPLOYMENTS; do
    IFS=: read -r d c i <<< "$e"
    if [ "$d" = "$3" ]; then
      case "$*" in *containers\[\*\].name*) echo "$c" ;; *) echo "$i" ;; esac
    fi
  done
fi
exit 0
STUB
chmod +x "$SANDBOX/bin/kubectl"

run_script() { OUT="$(bash "$SCRIPT" "$@" 2>&1)"; STATUS=$?; }

export STUB_DEPLOYMENTS="rellm-central-embedding:embedding:docker.io/u/rellm_embeddings:0.5.553"
: > "$STUB_LOG"; run_script embedding rellm-storage 0.5.554-x u
check_status "embedding bump succeeds" 0 "$STATUS"
check_contains "embedding sets the container named 'embedding' on rellm-central-embedding" "$(cat "$STUB_LOG")" "kubectl set image deployment/rellm-central-embedding embedding=docker.io/u/rellm_embeddings:0.5.554-x -n rellm-storage"

export STUB_DEPLOYMENTS=""
: > "$STUB_LOG"; run_script embedding rellm-storage 0.5.554-x u
check_status "embedding is skipped, not failed, when not deployed" 0 "$STATUS"
check_contains "...and says so" "$OUT" "not deployed (optional)"
case "$(cat "$STUB_LOG")" in *"set image"*) fail "nothing should be rolled when embedding isn't deployed" ;; *) pass "nothing rolled when embedding isn't deployed" ;; esac

: > "$STUB_LOG"; run_script vector my-site 0.5.554-x u
check_status "vector is skipped when the namespace has none" 0 "$STATUS"

export STUB_DEPLOYMENTS="rellm-vector:rellm-vector:old"
: > "$STUB_LOG"; run_script vector my-site 0.5.554-x u
check_contains "vector bumps rellm-vector to the embeddings image" "$(cat "$STUB_LOG")" "kubectl set image deployment/rellm-vector rellm-vector=docker.io/u/rellm_embeddings:0.5.554-x -n my-site"

export STUB_DEPLOYMENTS=""
run_script server my-site 0.5.554-x u
check_nonzero "server still fails when its deployments are missing" "$STATUS"
run_script bogus my-site 0.5.554-x u
check_nonzero "unknown component is rejected" "$STATUS"

export STUB_DEPLOYMENTS="rellm-central-embedding:wrong:old"
run_script embedding rellm-storage 0.5.554-x u
check_nonzero "an existing deployment with an unexpected container name fails" "$STATUS"

finish
