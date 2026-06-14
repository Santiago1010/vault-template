#!/usr/bin/env bash
# =============================================================================
# Vault Unseal
# Usage: ./scripts/unseal.sh
#        ENV=staging ./scripts/unseal.sh
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/common.sh"

KEYS_FILE="${SECRETS_DIR}/unseal-keys.json"

if ! docker ps --format '{{.Names}}' | grep -q "^${VAULT_CONTAINER}$"; then
  echo "[ERROR] Container ${VAULT_CONTAINER} is not running."
  exit 1
fi

if [ ! -f "${KEYS_FILE}" ]; then
  echo "[ERROR] Unseal keys not found. Run ./scripts/init.sh first."
  exit 1
fi

STATUS=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" "${VAULT_CONTAINER}" vault status -format=json 2>/dev/null || true)
SEALED=$(echo "${STATUS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['sealed'])" 2>/dev/null || echo "true")

if [ "${SEALED}" = "False" ]; then
  info "Vault is already unsealed."
  exit 0
fi

info "Unsealing Vault..."

KEYS=$(python3 -c "
import json
with open('${KEYS_FILE}') as f:
  data = json.load(f)
for key in data['unseal_keys_b64'][:3]:
  print(key)
")

while IFS= read -r key; do
  docker exec \
    -e VAULT_ADDR="${VAULT_ADDR}" \
    "${VAULT_CONTAINER}" vault operator unseal "${key}"
done <<< "${KEYS}"

ok "Vault unsealed."
