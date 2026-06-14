#!/usr/bin/env bash
# =============================================================================
# Vault Init Script — Local Development
# Runs vault CLI inside the container via docker exec
# =============================================================================

set -euo pipefail

CONTAINER="vault-template"
VAULT_ADDR="http://127.0.0.1:8200"
SECRETS_DIR="$(dirname "$0")/../secrets"
KEYS_FILE="${SECRETS_DIR}/unseal-keys.json"
TOKEN_FILE="${SECRETS_DIR}/root-token.txt"

vaultcmd() {
  docker exec -e VAULT_ADDR="${VAULT_ADDR}" "${CONTAINER}" vault "$@"
}

# -----------------------------------------------------------------------------
# Sanity checks
# -----------------------------------------------------------------------------
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "[ERROR] Container ${CONTAINER} is not running."
  exit 1
fi

mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"

# -----------------------------------------------------------------------------
# Check if already initialized
# -----------------------------------------------------------------------------
STATUS=$(vaultcmd status -format=json 2>/dev/null || true)
INITIALIZED=$(echo "${STATUS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['initialized'])" 2>/dev/null || echo "false")

if [ "${INITIALIZED}" = "True" ]; then
  echo "[INFO] Vault is already initialized. Run: scripts/unseal.sh"
  exit 0
fi

# -----------------------------------------------------------------------------
# Initialize Vault
# -----------------------------------------------------------------------------
echo "[INFO] Initializing Vault..."

INIT_OUTPUT=$(vaultcmd operator init -key-shares=5 -key-threshold=3 -format=json)

echo "${INIT_OUTPUT}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(json.dumps({'unseal_keys_b64': data['unseal_keys_b64'], 'unseal_threshold': 3}, indent=2))
" > "${KEYS_FILE}"
chmod 600 "${KEYS_FILE}"

echo "${INIT_OUTPUT}" | python3 -c "
import sys, json
print(json.load(sys.stdin)['root_token'], end='')
" > "${TOKEN_FILE}"
chmod 600 "${TOKEN_FILE}"

echo "[OK] Keys  → ${KEYS_FILE}"
echo "[OK] Token → ${TOKEN_FILE}"

# -----------------------------------------------------------------------------
# Unseal
# -----------------------------------------------------------------------------
echo "[INFO] Unsealing Vault..."

KEYS=$(python3 -c "
import json
with open('${KEYS_FILE}') as f:
  data = json.load(f)
for key in data['unseal_keys_b64'][:3]:
  print(key)
")

while IFS= read -r key; do
  vaultcmd operator unseal "${key}"
done <<< "${KEYS}"

echo "[OK] Vault unsealed."

# -----------------------------------------------------------------------------
# Enable audit log
# -----------------------------------------------------------------------------
echo "[INFO] Enabling audit log..."

ROOT_TOKEN=$(cat "${TOKEN_FILE}")

docker exec \
  -e VAULT_ADDR="${VAULT_ADDR}" \
  -e VAULT_TOKEN="${ROOT_TOKEN}" \
  "${CONTAINER}" \
  vault audit enable file file_path=/vault/logs/audit.log log_raw=false \
  || echo "[WARN] Audit log already enabled."

echo "[OK] Audit log enabled."
echo ""
echo "========================================"
echo " Vault initialized and unsealed."
echo " Root token: $(cat "${TOKEN_FILE}")"
echo " Next: scripts/validate.sh"
echo "========================================"
