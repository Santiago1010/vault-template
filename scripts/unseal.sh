#!/usr/bin/env bash
# =============================================================================
# Vault Unseal Script — Local Development
# Run after every container restart
# =============================================================================

set -euo pipefail

VAULT_ADDR="http://127.0.0.1:8200"
SECRETS_DIR="$(dirname "$0")/../secrets"
KEYS_FILE="${SECRETS_DIR}/unseal-keys.json"

export VAULT_ADDR

# -----------------------------------------------------------------------------
# Sanity checks
# -----------------------------------------------------------------------------
if ! docker ps --format '{{.Names}}' | grep -q '^vault$'; then
  echo "[ERROR] Vault container is not running. Run: docker compose up -d"
  exit 1
fi

if [ ! -f "${KEYS_FILE}" ]; then
  echo "[ERROR] Unseal keys not found at ${KEYS_FILE}"
  echo "[INFO]  Run scripts/init.sh first."
  exit 1
fi

# -----------------------------------------------------------------------------
# Check if already unsealed
# -----------------------------------------------------------------------------
STATUS=$(vault status -format=json 2>/dev/null || true)
SEALED=$(echo "${STATUS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['sealed'])" 2>/dev/null || echo "true")

if [ "${SEALED}" = "False" ]; then
  echo "[INFO] Vault is already unsealed."
  exit 0
fi

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