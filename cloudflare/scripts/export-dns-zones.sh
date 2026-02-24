#!/usr/bin/env bash
# Export all Cloudflare DNS zones to BIND-format files under EXPORT_DIR.
# Requires: EXPORT_DIR, CLOUDFLARE_API_TOKEN, EXPORT_DELAY_SEC (optional, default 25)
set -euo pipefail

: "${EXPORT_DIR:?EXPORT_DIR not set}"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN not set}"
EXPORT_DELAY_SEC="${EXPORT_DELAY_SEC:-25}"

BASE_URL="https://api.cloudflare.com/client/v4"
PAGE=1
PER_PAGE=50
EXPORTED=0
FAILED=0

mkdir -p "$EXPORT_DIR"

while true; do
  RESULT=$(curl -s -X GET "${BASE_URL}/zones?page=${PAGE}&per_page=${PER_PAGE}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json")

  if [[ "$(echo "$RESULT" | jq -r '.success')" != "true" ]]; then
    echo "::error::List zones failed: $RESULT"
    exit 1
  fi

  ZONES=$(echo "$RESULT" | jq -c '.result[]')
  [[ -z "$ZONES" || "$ZONES" == "null" ]] && break

  while IFS= read -r Z; do
    ZONE_ID=$(echo "$Z" | jq -r '.id')
    ZONE_NAME=$(echo "$Z" | jq -r '.name')
    OUT="${EXPORT_DIR}/${ZONE_NAME}.zone"

    echo "Exporting zone: $ZONE_NAME ($ZONE_ID) -> $OUT"
    HTTP=$(curl -s -w "%{http_code}" -o /tmp/zone.$$ \
      -X GET "${BASE_URL}/zones/${ZONE_ID}/dns_records/export" \
      -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
      -H "Content-Type: application/json")

    if [[ "$HTTP" != "200" ]]; then
      echo "::warning::Export failed for $ZONE_NAME (HTTP $HTTP), skipping."
      rm -f /tmp/zone.$$
      ((FAILED += 1)) || true
      sleep "$EXPORT_DELAY_SEC"
      continue
    fi

    mv /tmp/zone.$$ "$OUT"
    ((EXPORTED += 1)) || true
    sleep "$EXPORT_DELAY_SEC"
  done <<< "$ZONES"

  COUNT=$(echo "$RESULT" | jq '.result | length')
  [[ "$COUNT" -lt "$PER_PAGE" ]] && break
  ((PAGE++)) || true
done

echo "Exported $EXPORTED zone(s). Failed: $FAILED."
if [[ "$EXPORTED" -eq 0 ]]; then
  echo "::error::No zones were exported. Check token permissions and account zones."
  exit 1
fi
