#!/usr/bin/env bash
# =============================================================================
# Vault Policies + AppRoles
# Usage: ./scripts/setup-auth.sh
#        ENV=staging ./scripts/setup-auth.sh
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/common.sh"

SERVICES=("events" "database" "cache" "gateway" "discovery" "services" "api")

# -----------------------------------------------------------------------------
# Apply policies
# -----------------------------------------------------------------------------
info "Applying policies..."

for service in "${SERVICES[@]}"; do
  POLICY_FILE="${POLICIES_DIR}/${service}.hcl"

  if [ ! -f "${POLICY_FILE}" ]; then
    info "Policy not found: ${service} — skipping"
    continue
  fi

  docker cp "${POLICY_FILE}" "${VAULT_CONTAINER}:/tmp/${service}.hcl"

  docker exec \
    -e VAULT_ADDR="${VAULT_ADDR}" \
    -e VAULT_TOKEN="$(cat "${TOKEN_FILE}")" \
    "${VAULT_CONTAINER}" vault policy write "${service}" "/tmp/${service}.hcl"

  ok "Policy applied: ${service}"
done

# -----------------------------------------------------------------------------
# Create AppRoles + save credentials
# -----------------------------------------------------------------------------
info "Creating AppRoles..."

declare -A ROLE_DATA

for service in "${SERVICES[@]}"; do
  vaultcmd write "auth/approle/role/${service}" \
    token_policies="${service}" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=0 \
    secret_id_num_uses=0

  ok "AppRole created: ${service}"
done

python3 << PYEOF
import json, subprocess, os

services = ['events', 'database', 'cache', 'gateway', 'discovery', 'services', 'api']
container = '${VAULT_CONTAINER}'
vault_addr = '${VAULT_ADDR}'
token = open('${TOKEN_FILE}').read().strip()
approles_file = '${APPROLES_FILE}'

data = {}
for service in services:
    role_id = subprocess.run(
        ['docker', 'exec',
         '-e', f'VAULT_ADDR={vault_addr}',
         '-e', f'VAULT_TOKEN={token}',
         container, 'vault', 'read', '-field=role_id',
         f'auth/approle/role/{service}/role-id'],
        capture_output=True, text=True
    ).stdout.strip()

    secret_id = subprocess.run(
        ['docker', 'exec',
         '-e', f'VAULT_ADDR={vault_addr}',
         '-e', f'VAULT_TOKEN={token}',
         container, 'vault', 'write', '-field=secret_id', '-f',
         f'auth/approle/role/{service}/secret-id'],
        capture_output=True, text=True
    ).stdout.strip()

    data[service] = {'role_id': role_id, 'secret_id': secret_id}
    print(f'[OK]   Credentials saved: {service}')

with open(approles_file, 'w') as f:
    json.dump(data, f, indent=2)
os.chmod(approles_file, 0o600)

print(f'[OK]   AppRoles file: {approles_file}')
PYEOF

echo ""
echo "========================================"
echo " Auth ready."
echo " Project: ${VAULT_PROJECT} | Env: ${VAULT_ENV}"
echo " Next: ./scripts/setup-secrets.sh"
echo "========================================"
