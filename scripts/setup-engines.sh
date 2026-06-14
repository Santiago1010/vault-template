#!/usr/bin/env bash
# =============================================================================
# Vault Secrets Engines & Auth Methods Setup
# Run once after init
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
# KV v2
# -----------------------------------------------------------------------------
echo "[INFO] Enabling KV v2 at secret/..."
vaultcmd secrets enable -path=secret -version=2 kv \
  && echo "[OK] KV v2 enabled" \
  || echo "[WARN] Already enabled"

# -----------------------------------------------------------------------------
# AppRole
# -----------------------------------------------------------------------------
echo "[INFO] Enabling AppRole auth..."
vaultcmd auth enable approle \
  && echo "[OK] AppRole enabled" \
  || echo "[WARN] Already enabled"

# -----------------------------------------------------------------------------
# Database engine (placeholder — configured per service later)
# -----------------------------------------------------------------------------
echo "[INFO] Enabling Database secrets engine..."
vaultcmd secrets enable database \
  && echo "[OK] Database engine enabled" \
  || echo "[WARN] Already enabled"

# -----------------------------------------------------------------------------
# PKI engine (placeholder — configured in Phase 6)
# -----------------------------------------------------------------------------
echo "[INFO] Enabling PKI secrets engine..."
vaultcmd secrets enable pki \
  && echo "[OK] PKI engine enabled" \
  || echo "[WARN] Already enabled"

vaultcmd secrets tune -max-lease-ttl=87600h pki \
  && echo "[OK] PKI max TTL set to 10 years"

echo ""
echo "========================================"
echo " Engines and auth methods ready."
echo " Next: ./scripts/validate.sh"
echo "========================================"
