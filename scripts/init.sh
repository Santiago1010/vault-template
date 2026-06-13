#!/usr/bin/env bash
# =============================================================================
# Vault Init Script — Local Development
# Run once after first `docker compose up`
# Saves unseal keys and root token to secrets/ (gitignored)
# =============================================================================

set -euo pipefail

VAULT_ADDR="http://127.0.0.1:8200"
SECRETS_DIR="$(dirname "$0")/../secrets"
KEYS_FILE="${SECRETS_DIR}/unseal-keys.json"
TOKEN_FILE="${SECRETS_DIR}/root-token.txt"

export VAULT_ADDR

# -----------------------------------------------------------------------------
# Sanity checks
# -----------------------------------------------------------------------------
if ! docker ps --format '{{.Names}}' | grep -q '^vault$'; then
  echo "[ERROR] Vault container is not running. Run: docker compose up -d"
  exit 1
fi

mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"

# -----------------------------------------------------------------------------
# Check if already initialized
# -----------------------------------------------------------------------------
STATUS=$(vault status -format=json 2>/dev/null || true)
INITIALIZED=$(echo "${STATUS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['initialized'])" 2>/dev/null || echo "false")

if [ "${INITIALIZED}" = "True" ]; then
  echo "[INFO] Vault is already initialized. Skipping init."
  echo "[INFO] To unseal, run: scripts/unseal.sh"
  exit 0
fi

# -----------------------------------------------------------------------------
# Initialize Vault — 5 key shares, threshold 3
# -----------------------------------------------------------------------------
echo "[INFO] Initializing Vault..."

INIT_OUTPUT=$(vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json)

# Save unseal keys
echo "${INIT_OUTPUT}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
output = {
  'unseal_keys_b64': data['unseal_keys_b64'],
  'unseal_threshold': 3
}
print(json.dumps(output, indent=2))
" > "${KEYS_FILE}"
chmod 600 "${KEYS_FILE}"

# Save root token
echo "${INIT_OUTPUT}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data['root_token'], end='')
" > "${TOKEN_FILE}"
chmod 600 "${TOKEN_FILE}"

echo "[OK] Unseal keys saved to ${KEYS_FILE}"
echo "[OK] Root token saved to ${TOKEN_FILE}"

# -----------------------------------------------------------------------------
# Unseal with first 3 keys
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
  vault operator unseal "${key}"
done <<< "${KEYS}"

echo "[OK] Vault unsealed."

# -----------------------------------------------------------------------------
# Enable audit log
# -----------------------------------------------------------------------------
echo "[INFO] Enabling audit log..."

VAULT_TOKEN=$(cat "${TOKEN_FILE}")
export VAULT_TOKEN

vault audit enable file \
  file_path=/vault/logs/audit.log \
  log_raw=false || echo "[WARN] Audit log already enabled."

echo "[OK] Audit log enabled at /vault/logs/audit.log"
echo ""
echo "========================================"
echo " Vault initialized and unsealed."
echo " Root token: $(cat ${TOKEN_FILE})"
echo " Next step:  scripts/validate.sh"
echo "========================================"