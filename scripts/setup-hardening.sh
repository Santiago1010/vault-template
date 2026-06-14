#!/usr/bin/env bash
# =============================================================================
# Vault Hardening — TTLs, token policies, file permissions
# =============================================================================

set -euo pipefail

CONTAINER="vault-template"
VAULT_ADDR="http://127.0.0.1:8200"
SECRETS_DIR="$(dirname "$0")/../secrets"
TOKEN_FILE="${SECRETS_DIR}/root-token.txt"

ROOT_TOKEN=$(cat "${TOKEN_FILE}")

vaultcmd() {
  docker exec \
    -e VAULT_ADDR="${VAULT_ADDR}" \
    -e VAULT_TOKEN="${ROOT_TOKEN}" \
    "${CONTAINER}" vault "$@"
}

# -----------------------------------------------------------------------------
# 1. System-wide default TTLs
# -----------------------------------------------------------------------------
echo "[INFO] Configuring system TTLs..."

vaultcmd write sys/auth/token/tune \
  default_lease_ttl=1h \
  max_lease_ttl=4h

echo "[OK]   Token TTL: default=1h max=4h"

# -----------------------------------------------------------------------------
# 2. Tune KV v2 — no TTL on secrets (they don't expire)
# -----------------------------------------------------------------------------
echo "[INFO] Tuning KV v2..."

vaultcmd secrets tune \
  -default-lease-ttl=0 \
  -max-lease-ttl=0 \
  secret/

echo "[OK]   KV v2 leases disabled (secrets don't expire)"

# -----------------------------------------------------------------------------
# 3. Tune Database engine — short TTL for dynamic creds
# -----------------------------------------------------------------------------
echo "[INFO] Tuning Database engine..."

vaultcmd secrets tune \
  -default-lease-ttl=1h \
  -max-lease-ttl=24h \
  database/

echo "[OK]   Database creds TTL: default=1h max=24h"

# -----------------------------------------------------------------------------
# 4. Tune PKI engine
# -----------------------------------------------------------------------------
echo "[INFO] Tuning PKI engine..."

vaultcmd secrets tune \
  -max-lease-ttl=87600h \
  pki/

echo "[OK]   PKI max TTL: 87600h (10 years)"

# -----------------------------------------------------------------------------
# 5. File permissions on secrets/
# -----------------------------------------------------------------------------
echo "[INFO] Enforcing file permissions on secrets/..."

chmod 700 "${SECRETS_DIR}"
chmod 600 "${SECRETS_DIR}"/*.json 2>/dev/null || true
chmod 600 "${SECRETS_DIR}"/*.txt  2>/dev/null || true

echo "[OK]   secrets/ → 700"
echo "[OK]   secrets/*.json → 600"
echo "[OK]   secrets/*.txt  → 600"

# -----------------------------------------------------------------------------
# 6. Verify
# -----------------------------------------------------------------------------
echo ""
echo "[INFO] Current permissions:"
ls -la "${SECRETS_DIR}/"

echo ""
echo "========================================"
echo " Hardening complete."
echo " Next: ./scripts/validate.sh"
echo "========================================"
