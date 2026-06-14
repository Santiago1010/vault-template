#!/usr/bin/env bash
# =============================================================================
# Vault Auth Setup — Policies + AppRoles
# Run once after setup-engines.sh
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

vaultwrite() {
  docker exec \
    -e VAULT_ADDR="${VAULT_ADDR}" \
    -e VAULT_TOKEN="${ROOT_TOKEN}" \
    "${CONTAINER}" vault write "$@"
}

SERVICES=("events" "database" "cache" "gateway" "discovery" "services")

# -----------------------------------------------------------------------------
# Apply policies
# -----------------------------------------------------------------------------
echo "[INFO] Applying policies..."

for service in "${SERVICES[@]}"; do
  POLICY_FILE="${POLICIES_DIR}/${service}.hcl"

  if [ ! -f "${POLICY_FILE}" ]; then
    echo "[WARN] Policy file not found: ${POLICY_FILE} — skipping"
    continue
  fi

  docker cp "${POLICY_FILE}" "${CONTAINER}:/tmp/${service}.hcl"

  docker exec \
    -e VAULT_ADDR="${VAULT_ADDR}" \
    -e VAULT_TOKEN="${ROOT_TOKEN}" \
    "${CONTAINER}" vault policy write "${service}" "/tmp/${service}.hcl"

  echo "[OK]   Policy applied: ${service}"
done

# -----------------------------------------------------------------------------
# Create AppRoles
# -----------------------------------------------------------------------------
echo ""
echo "[INFO] Creating AppRoles..."

declare -A APPROLES

for service in "${SERVICES[@]}"; do
  # Create role
  vaultwrite "auth/approle/role/${service}" \
    token_policies="${service}" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=0 \
    secret_id_num_uses=0

  # Get role_id
  ROLE_ID=$(vaultcmd read -field=role_id "auth/approle/role/${service}/role-id")

  # Generate secret_id
  SECRET_ID=$(vaultcmd write -field=secret_id -f "auth/approle/role/${service}/secret-id")

  APPROLES["${service}"]=$(python3 -c "
import json
print(json.dumps({'role_id': '${ROLE_ID}', 'secret_id': '${SECRET_ID}'}))
")

  echo "[OK]   AppRole created: ${service}"
done

# -----------------------------------------------------------------------------
# Save approles to secrets/
# -----------------------------------------------------------------------------
python3 -c "
import json, sys

services = '${SERVICES[*]}'.split()
data = {}
" 

python3 << PYEOF
import json, subprocess, os

services = ['events', 'database', 'cache', 'gateway', 'discovery', 'services']
approles_file = '${APPROLES_FILE}'

data = {}
for service in services:
    role_id_result = subprocess.run(
        ['docker', 'exec',
         '-e', 'VAULT_ADDR=${VAULT_ADDR}',
         '-e', 'VAULT_TOKEN=${ROOT_TOKEN}',
         '${CONTAINER}', 'vault', 'read', '-field=role_id',
         f'auth/approle/role/{service}/role-id'],
        capture_output=True, text=True
    )
    secret_id_result = subprocess.run(
        ['docker', 'exec',
         '-e', 'VAULT_ADDR=${VAULT_ADDR}',
         '-e', 'VAULT_TOKEN=${ROOT_TOKEN}',
         '${CONTAINER}', 'vault', 'write', '-field=secret_id', '-f',
         f'auth/approle/role/{service}/secret-id'],
        capture_output=True, text=True
    )
    data[service] = {
        'role_id': role_id_result.stdout.strip(),
        'secret_id': secret_id_result.stdout.strip()
    }

with open(approles_file, 'w') as f:
    json.dump(data, f, indent=2)

os.chmod(approles_file, 0o600)
print(f'[OK]   AppRoles saved to {approles_file}')
PYEOF

echo ""
echo "========================================"
echo " Policies and AppRoles ready."
echo " Credentials: ${APPROLES_FILE}"
echo " Next: ./scripts/validate.sh"
echo "========================================"
