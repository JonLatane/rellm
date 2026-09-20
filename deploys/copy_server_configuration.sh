#!/usr/bin/env zsh
# Copies one `server_configurations` column's value from one namespace's active row to another's
# -- e.g. copying `stripe_config` from `rellm-org` to `jonline` after setting up Stripe once and
# wanting every community to bill through the same account.
#
# Mirrors `ConfigureServer`'s own persistence pattern (see
# backend/src/rpcs/server_configuration/configure_server.rs) rather than a bare in-place UPDATE:
# the destination's current active row is cloned with the one column replaced, the old row is
# marked `active = false`, and the new row (fresh `created_at`/`updated_at`, `active = true` --
# both via the table's own column defaults, same as a real ConfigureServer call) is inserted, all
# in a single transaction. So a copy is auditable/rollback-able the same way a normal admin edit
# through the app is -- every prior configuration row is still there, just inactive -- and every
# *other* column (media settings, permissions, custom tabs, etc.) is preserved from the
# destination's own current configuration, never overwritten.
#
# Usage:
#   ./copy_server_configuration.sh --source <namespace> --destination <namespace> --column <column>
#
# Example:
#   ./copy_server_configuration.sh --source rellm-org --destination jonline --column stripe_config
#
# The copied value passes from psql to a shell variable to an exported env var to psql's own
# `\getenv`, and is substituted into SQL only via a `\getenv`-bound psql variable (`:'new_value'`)
# -- never interpolated into a SQL string, never passed as a `-v`/`-c` command-line argument, and
# never echoed -- so it never appears in your terminal, shell history, or a `set -x` trace, and
# never even reaches your process list (unlike a `-v`/`-c` argument would).
#
# Prerequisites: kubectl pointed at the right cluster (see cutover_jonline_namespace.sh's own doc
# for the `doctl kubernetes cluster kubeconfig save` incantation), psql installed locally (15+,
# for `\getenv`).
set -euo pipefail

# Captured up front -- inside a zsh function, $0 is the function's own name, not the script's (a
# real difference from bash), so usage() below can't just read $0 itself.
SCRIPT_NAME=$0

PG_SVC=rellm-postgres
PG_PORT=5432
PG_USER=admin
# Matches deploys/k8s/k8s-postgres-*.yaml's own POSTGRES_PASSWORD -- not a real secret (it's
# already checked into this repo in plaintext), just this cluster's DB auth.
PG_PASSWORD=secure_password1
PG_DB=rellm

# Every `server_configurations` column that's actually copyable this way -- everything except
# `id`/`active`/`created_at`/`updated_at`, which this script manages itself (see the header doc
# above). Keep this in sync with backend/src/schema.rs's own `server_configurations` table! --
# there's no way to derive it live without a DB round-trip this script doesn't otherwise need.
typeset -a COPYABLE_COLUMNS
COPYABLE_COLUMNS=(
  server_info anonymous_user_permissions default_user_permissions basic_user_permissions
  people_settings group_settings post_settings event_settings external_cdn_config
  private_user_strategy authentication_features federation_info web_push_config custom_tabs
  cluster_resources twilio_config bird_config preferred_verification_apis media_settings
  stripe_config market_settings
)

usage() {
  echo "Usage: $SCRIPT_NAME --source <namespace> --destination <namespace> --column <column>" >&2
  echo >&2
  echo "Copyable columns:" >&2
  printf '  %s\n' "${COPYABLE_COLUMNS[@]}" >&2
  exit 1
}

SOURCE_NS=""
DEST_NS=""
COLUMN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE_NS="${2:-}"; shift 2 ;;
    --destination) DEST_NS="${2:-}"; shift 2 ;;
    --column) COLUMN="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$SOURCE_NS" && -n "$DEST_NS" && -n "$COLUMN" ]] || usage

if [[ "$SOURCE_NS" == "$DEST_NS" ]]; then
  echo "Source and destination namespaces are the same ($SOURCE_NS) -- nothing to do." >&2
  exit 1
fi

# `COPYABLE_COLUMNS` is also this script's whole defense against SQL injection via `--column` --
# every column name that ends up in a SQL string below came from this fixed array, never directly
# from `$COLUMN` itself.
COLUMN_OK=0
for c in "${COPYABLE_COLUMNS[@]}"; do
  [[ "$c" == "$COLUMN" ]] && COLUMN_OK=1
done
if [[ "$COLUMN_OK" -ne 1 ]]; then
  echo "Refusing to copy column '$COLUMN' -- not in the copyable set." >&2
  usage
fi

# Port-forwards $1's rellm-postgres to a scratch local port, waits until it's actually accepting
# connections (a plain psql retry loop -- portable across zsh, unlike bash's /dev/tcp), and leaves
# PF_PID/PF_PORT set for the caller. Always paired with stop_port_forward.
PF_PID=""
PF_PORT=""
start_port_forward() {
  local ns=$1
  PF_PORT=$(( (RANDOM % 5000) + 20000 ))
  kubectl port-forward -n "$ns" "svc/$PG_SVC" "$PF_PORT:$PG_PORT" \
    >"/tmp/pgpf-copy-server-configuration-$ns.log" 2>&1 &
  PF_PID=$!
  local attempt
  for attempt in {1..30}; do
    if PGPASSWORD="$PG_PASSWORD" psql -h 127.0.0.1 -p "$PF_PORT" -U "$PG_USER" -d "$PG_DB" \
      -tAc "SELECT 1;" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  echo "Timed out waiting for port-forward to $ns -- see /tmp/pgpf-copy-server-configuration-$ns.log" >&2
  kill "$PF_PID" 2>/dev/null || true
  return 1
}

stop_port_forward() {
  [[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null
  wait "$PF_PID" 2>/dev/null || true
  PF_PID=""
}

run_psql() {
  PGPASSWORD="$PG_PASSWORD" psql -h 127.0.0.1 -p "$PF_PORT" -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1 "$@"
}

trap stop_port_forward EXIT

echo "== Reading $COLUMN from $SOURCE_NS's active server_configurations row =="
start_port_forward "$SOURCE_NS"
IS_NULL=$(run_psql -tAc "SELECT ($COLUMN IS NULL) FROM server_configurations WHERE active = true;")
if [[ "$IS_NULL" == t ]]; then
  NEW_VALUE=""
  NEW_VALUE_IS_NULL=1
else
  # `::text` works uniformly whether $COLUMN is jsonb or varchar (every copyable column is one or
  # the other) -- see this script's own header doc.
  NEW_VALUE=$(run_psql -tAc "SELECT ${COLUMN}::text FROM server_configurations WHERE active = true;")
  NEW_VALUE_IS_NULL=0
fi
stop_port_forward
echo "   Read ${#NEW_VALUE} bytes (not shown)."

echo "== Cloning $DEST_NS's active row with the new $COLUMN, retiring the old one =="

SELECT_LIST=""
for col in "${COPYABLE_COLUMNS[@]}"; do
  if [[ "$col" == "$COLUMN" ]]; then
    if [[ "$NEW_VALUE_IS_NULL" == 1 ]]; then
      SELECT_LIST+="NULL, "
    else
      SELECT_LIST+=":'new_value', "
    fi
  else
    SELECT_LIST+="$col, "
  fi
done
SELECT_LIST="${SELECT_LIST%, }"
COLUMN_LIST="${(j:, :)COPYABLE_COLUMNS}"

start_port_forward "$DEST_NS"
export COPY_SERVER_CONFIGURATION_NEW_VALUE="$NEW_VALUE"
run_psql <<SQL
BEGIN;
SELECT id AS old_id FROM server_configurations WHERE active = true \gset
\getenv new_value COPY_SERVER_CONFIGURATION_NEW_VALUE
UPDATE server_configurations SET active = false WHERE id = :old_id;
INSERT INTO server_configurations ($COLUMN_LIST)
SELECT $SELECT_LIST
FROM server_configurations WHERE id = :old_id;
COMMIT;
SQL
unset COPY_SERVER_CONFIGURATION_NEW_VALUE
stop_port_forward
trap - EXIT

echo "== Done: copied $COLUMN from $SOURCE_NS to $DEST_NS =="
