#!/usr/bin/env bash
# =============================================================================
# Vault PKI — Root CA + Intermediate CA + Kafka role + first cert
# Usage: ./scripts/setup-pki.sh
#        ENV=staging ./scripts/setup-pki.sh
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/common.sh"

mkdir -p "${PKI_DIR}"
chmod 700 "${PKI_DIR}"

# -----------------------------------------------------------------------------
# 1. Root CA
# -----------------------------------------------------------------------------
info "Generating root CA..."

vaultcmd write -format=json pki/root/generate/internal \
  common_name="${VAULT_PROJECT} Root CA" \
  ttl=87600h \
  key_type=rsa \
  key_bits=4096 \
| python3 -c "
import sys, json
data = json.load(sys.stdin)
with open('${PKI_DIR}/root-ca.crt', 'w') as f:
    f.write(data['data']['certificate'])
print('[OK]   Root CA saved: secrets/pki/root-ca.crt')
"

vaultcmd write pki/config/urls \
  issuing_certificates="${VAULT_ADDR}/v1/pki/ca" \
  crl_distribution_points="${VAULT_ADDR}/v1/pki/crl"

ok "Root CA URLs configured"

# -----------------------------------------------------------------------------
# 2. Intermediate CA
# -----------------------------------------------------------------------------
info "Setting up intermediate CA..."

vaultcmd secrets enable -path=pki_int pki 2>/dev/null \
  || info "pki_int already enabled"

vaultcmd secrets tune -max-lease-ttl=43800h pki_int

# Generate CSR
vaultcmd write -format=json pki_int/intermediate/generate/internal \
  common_name="${VAULT_PROJECT} Intermediate CA" \
  key_type=rsa \
  key_bits=4096 \
| python3 -c "
import sys, json
data = json.load(sys.stdin)
with open('${PKI_DIR}/intermediate.csr', 'w') as f:
    f.write(data['data']['csr'])
print('[OK]   Intermediate CSR saved')
"

# Sign CSR with root CA
docker cp "${PKI_DIR}/intermediate.csr" "${VAULT_CONTAINER}:/tmp/intermediate.csr"

docker exec \
  -e VAULT_ADDR="${VAULT_ADDR}" \
  -e VAULT_TOKEN="$(cat "${TOKEN_FILE}")" \
  "${VAULT_CONTAINER}" \
  vault write -format=json pki/root/sign-intermediate \
  common_name="${VAULT_PROJECT} Intermediate CA" \
  ttl=43800h \
  csr=@/tmp/intermediate.csr \
| python3 -c "
import sys, json
data = json.load(sys.stdin)
with open('${PKI_DIR}/intermediate.crt', 'w') as f:
    f.write(data['data']['certificate'])
print('[OK]   Intermediate cert signed')
"

# Set signed cert in Vault
docker cp "${PKI_DIR}/intermediate.crt" "${VAULT_CONTAINER}:/tmp/intermediate.crt"

docker exec \
  -e VAULT_ADDR="${VAULT_ADDR}" \
  -e VAULT_TOKEN="$(cat "${TOKEN_FILE}")" \
  "${VAULT_CONTAINER}" \
  vault write pki_int/intermediate/set-signed \
  certificate=@/tmp/intermediate.crt

ok "Intermediate CA active in Vault"

vaultcmd write pki_int/config/urls \
  issuing_certificates="${VAULT_ADDR}/v1/pki_int/ca" \
  crl_distribution_points="${VAULT_ADDR}/v1/pki_int/crl"

ok "Intermediate CA URLs configured"

# -----------------------------------------------------------------------------
# 3. Kafka role
# -----------------------------------------------------------------------------
info "Creating Kafka PKI role..."

vaultcmd write pki_int/roles/kafka \
  allowed_domains="${VAULT_DOMAIN},${VAULT_PROJECT}" \
  allow_subdomains=true \
  allow_localhost=true \
  allow_ip_sans=true \
  key_type=rsa \
  key_bits=2048 \
  max_ttl=8760h \
  ttl=720h

ok "Kafka PKI role created"

# -----------------------------------------------------------------------------
# 4. Issue first cert
# -----------------------------------------------------------------------------
info "Issuing Kafka certificate..."

vaultcmd write -format=json pki_int/issue/kafka \
  common_name="kafka.${VAULT_DOMAIN}" \
  alt_names="localhost" \
  ip_sans="127.0.0.1" \
  ttl=720h \
| python3 -c "
import sys, json, os

data = json.load(sys.stdin)['data']
pki_dir = '${PKI_DIR}'

files = {
    'kafka.crt': data['certificate'],
    'kafka.key': data['private_key'],
    'kafka-ca-chain.crt': '\n'.join(data['ca_chain']),
}

for filename, content in files.items():
    path = os.path.join(pki_dir, filename)
    with open(path, 'w') as f:
        f.write(content)
    os.chmod(path, 0o600)
    print(f'[OK]   {filename} saved')
"

# -----------------------------------------------------------------------------
# 5. Update events policy with PKI access
# -----------------------------------------------------------------------------
info "Updating events policy for PKI..."

cat >> "${POLICIES_DIR}/events.hcl" << 'POLICY'

# PKI — issue certs for Kafka
path "pki_int/issue/kafka" {
  capabilities = ["create", "update"]
}

path "pki_int/cert/*" {
  capabilities = ["read"]
}
POLICY

docker cp "${POLICIES_DIR}/events.hcl" "${VAULT_CONTAINER}:/tmp/events.hcl"

docker exec \
  -e VAULT_ADDR="${VAULT_ADDR}" \
  -e VAULT_TOKEN="$(cat "${TOKEN_FILE}")" \
  "${VAULT_CONTAINER}" vault policy write events /tmp/events.hcl

ok "events policy updated with PKI access"

echo ""
echo "========================================"
echo " PKI ready."
echo " Project: ${VAULT_PROJECT} | Env: ${VAULT_ENV}"
echo " Certs:   secrets/pki/"
echo " Next:    ./scripts/setup-database.sh"
echo "========================================"
