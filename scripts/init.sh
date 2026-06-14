#!/usr/bin/env bash
# =============================================================================
# Vault Init — Initialize, unseal, enable audit log
# Usage: ./scripts/init.sh
#        ENV=staging ./scripts/init.sh
# =============================================================================

set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

mkdir -p "${SECRETS_DIR}" "${PKI_DIR}"
chmod 700 "${SECRETS_DIR}"

# -----------------------------------------------------------------------------
# Sanity check
# -----------------------------------------------------------------------------
if ! docker ps --format '{{.Names}}' | grep -q "^${VAULT_CONTAINER}$"; then
  echo "[ERROR] Container ${VAULT_CONTAINER} is not running."
  exit 1
fi

# -----------------------------------------------------------------------------
# Check if already initialized
# -----------------------------------------------------------------------------
STATUS=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" "${VAULT_CONTAINER}" vault status -format=json 2>/dev/null || true)
INITIALIZED=$(echo "${STATUS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['initialized'])" 2>/dev/null || echo "false")

if [ "${INITIALIZED}" = "True" ]; then
  info "Vault already initialized. Run: ./scripts/unseal.sh"
  exit 0
fi

# -----------------------------------------------------------------------------
# Initialize
# -----------------------------------------------------------------------------
info "Initializing Vault..."

INIT_OUTPUT=$(docker exec \
  -e VAULT_ADDR="${VAULT_ADDR}" \
  "${VAULT_CONTAINER}" vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json)

echo "${INIT_OUTPUT}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(json.dumps({'unseal_keys_b64': data['unseal_keys_b64'], 'unseal_threshold': 3}, indent=2))
" > "${SECRETS_DIR}/unseal-keys.json"
chmod 600 "${SECRETS_DIR}/unseal-keys.json"

echo "${INIT_OUTPUT}" | python3 -c "
import sys, json
print(json.load(sys.stdin)['root_token'], end='')
" > "${TOKEN_FILE}"
chmod 600 "${TOKEN_FILE}"

ok "Keys  → ${SECRETS_DIR}/unseal-keys.json"
ok "Token → ${TOKEN_FILE}"

# -----------------------------------------------------------------------------
# Unseal
# -----------------------------------------------------------------------------
info "Unsealing Vault..."

KEYS=$(python3 -c "
import json
with open('${SECRETS_DIR}/unseal-keys.json') as f:
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

# -----------------------------------------------------------------------------
# Audit log
# -----------------------------------------------------------------------------
info "Enabling audit log..."

vaultcmd audit enable file \
  file_path=/vault/logs/audit.log \
  log_raw=false \
  || info "Audit log already enabled."

ok "Audit log enabled."

echo ""
echo "========================================"
echo " Vault initialized and unsealed."
echo " Project:  ${VAULT_PROJECT}"
echo " Env:      ${VAULT_ENV}"
echo " Token:    $(cat "${TOKEN_FILE}")"
echo " Next:     ./scripts/setup-engines.sh"
echo "========================================"
