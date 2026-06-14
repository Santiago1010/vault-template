#!/usr/bin/env bash
# =============================================================================
# Vault Hardening — TTLs, file permissions
# Usage: ./scripts/setup-hardening.sh
#        ENV=staging ./scripts/setup-hardening.sh
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/common.sh"

info "Configuring system TTLs..."
vaultcmd write sys/auth/token/tune \
  default_lease_ttl=1h \
  max_lease_ttl=4h
ok "Token TTL: default=1h max=4h"

info "Tuning KV v2..."
vaultcmd secrets tune -default-lease-ttl=0 -max-lease-ttl=0 secret/
ok "KV v2 leases disabled"

info "Tuning Database engine..."
vaultcmd secrets tune -default-lease-ttl=1h -max-lease-ttl=24h database/
ok "Database creds TTL: default=1h max=24h"

info "Tuning PKI engine..."
vaultcmd secrets tune -max-lease-ttl=87600h pki/
ok "PKI max TTL: 87600h"

info "Enforcing file permissions..."
chmod 700 "${SECRETS_DIR}"
chmod 600 "${SECRETS_DIR}"/*.json 2>/dev/null || true
chmod 600 "${SECRETS_DIR}"/*.txt  2>/dev/null || true
ok "secrets/ permissions enforced"

echo ""
ls -la "${SECRETS_DIR}/"

echo ""
echo "========================================"
echo " Hardening complete."
echo " Project: ${VAULT_PROJECT} | Env: ${VAULT_ENV}"
echo " Next: ./scripts/validate.sh"
echo "========================================"
