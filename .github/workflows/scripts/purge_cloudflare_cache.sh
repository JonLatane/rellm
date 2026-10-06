#!/usr/bin/env bash
# Clears Cloudflare's entire edge cache for a Rellm web deployment's zone
# ("Purge Everything" -- one API call, no URL lists).
#
# Note this includes /media/ (cached for 12h, see backend/src/web/media.rs):
# the first requests after a deploy repopulate it from the origin.
#
# Usage:   purge_cloudflare_cache.sh <domain>   (domain is only used for logging)
# Env:     CLOUDFLARE_ZONE, CLOUDFLARE_TOKEN (required)
set -euo pipefail

domain="${1:?usage: purge_cloudflare_cache.sh <domain>}"
: "${CLOUDFLARE_ZONE:?CLOUDFLARE_ZONE must be set}"
: "${CLOUDFLARE_TOKEN:?CLOUDFLARE_TOKEN must be set}"

echo "Clearing the entire Cloudflare cache for ${domain}..."

curl -sS --fail -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE}/purge_cache" \
  -H "Authorization: Bearer ${CLOUDFLARE_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"purge_everything": true}'
echo
