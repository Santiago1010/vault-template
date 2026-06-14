#!/usr/bin/env bash
# =============================================================================
# Vault API Template — Policy + AppRole
# =============================================================================

set -euo pipefail

CONTAINER="vault-template"
VAULT_ADDR="http://127.0.0.1:8200"
SECRETS_DIR="$(dirname "$0")/../secrets"
POLICIES_DIR="$(dirname "$0")/../policies"
TOKEN_FILE="${SECRETS_DIR}/root-token.txt"
APPROLES_FILE="${SECRETS_DIR}/approles.json"

ROOT_TOKEN=$(cat "${TOKEN_FILE}")

vaultcmd() {
  docker exec \
    -e VAULT_ADDR="${VAULT_ADDR}" \
    -e VAULT_TOKEN="${ROOT_TOKEN}" \
    "${CONTAINER}" vault "$@"
}

# -----------------------------------------------------------------------------
# Policy
# -----------------------------------------------------------------------------
echo "[INFO] Applying policy: api..."

docker cp "${POLICIES_DIR}/api.hcl" "${CONTAINER}:/tmp/api.hcl"

docker exec \
  -e VAULT_ADDR="${VAULT_ADDR}" \
  -e VAULT_TOKEN="${ROOT_TOKEN}" \
  "${CONTAINER}" vault policy write api /tmp/api.hcl

echo "[OK]   Policy applied: api"

# -----------------------------------------------------------------------------
# AppRole
# -----------------------------------------------------------------------------
echo "[INFO] Creating AppRole: api..."

vaultcmd write auth/approle/role/api \
  token_policies="api" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_ttl=0 \
  secret_id_num_uses=0

ROLE_ID=$(vaultcmd read -field=role_id auth/approle/role/api/role-id)
SECRET_ID=$(vaultcmd write -field=secret_id -f auth/approle/role/api/secret-id)

echo "[OK]   AppRole created: api"

# -----------------------------------------------------------------------------
# Save to approles.json
# -----------------------------------------------------------------------------
python3 << PYEOF
import json, os

approles_file = '${APPROLES_FILE}'

with open(approles_file) as f:
    data = json.load(f)

data['api'] = {
    'role_id': '${ROLE_ID}',
    'secret_id': '${SECRET_ID}'
}

with open(approles_file, 'w') as f:
    json.dump(data, f, indent=2)

os.chmod(approles_file, 0o600)
print(f'[OK]   api credentials saved to {approles_file}')
PYEOF

# -----------------------------------------------------------------------------
# Initial secrets
# -----------------------------------------------------------------------------
echo "[INFO] Writing initial secrets for api..."

genpass() {
  python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))"
}

vaultcmd kv put secret/kafka-template/local/services/api \
  app_secret="$(genpass)" \
  jwt_secret="$(genpass)"

echo "[OK]   Secrets written to secret/kafka-template/local/services/api"

echo ""
echo "========================================"
echo " api-template ready."
echo " Next: ./scripts/validate-approles.sh"
echo "========================================"
