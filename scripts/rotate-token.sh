#!/usr/bin/env bash
# =============================================================================
# Rotate operator token — revoke old, create new, save to disk
# Usage: ./scripts/rotate-token.sh
#        ENV=staging ./scripts/rotate-token.sh
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/common.sh"

info "Reading current operator token..."
OLD_TOKEN=$(cat "${TOKEN_FILE}")

info "Creating new operator token..."
NEW_TOKEN=$(docker exec \
  -e VAULT_ADDR="${VAULT_ADDR}" \
  -e VAULT_TOKEN="${OLD_TOKEN}" \
  "${VAULT_CONTAINER}" vault token create \
  -policy=operator \
  -ttl=720h \
  -renewable=true \
  -orphan=true \
  -format=json \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['auth']['client_token'])")

if [ -z "${NEW_TOKEN}" ]; then
  echo "[ERROR] Failed to create new operator token. Aborting — old token is still valid."
  exit 1
fi

info "Saving new token..."
echo "${NEW_TOKEN}" > "${TOKEN_FILE}"
chmod 600 "${TOKEN_FILE}"
ok "New token saved to ${TOKEN_FILE}"

info "Revoking old token..."
docker exec \
  -e VAULT_ADDR="${VAULT_ADDR}" \
  -e VAULT_TOKEN="${NEW_TOKEN}" \
  "${VAULT_CONTAINER}" vault token revoke "${OLD_TOKEN}" \
  && ok "Old token revoked." \
  || echo "[WARN] Could not revoke old token — it may have already expired."

echo ""
echo "========================================"
echo " Operator token rotated."
echo " Project: ${VAULT_PROJECT} | Env: ${VAULT_ENV}"
echo "========================================"
