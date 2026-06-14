#!/usr/bin/env bash
# =============================================================================
# Vault Secrets Engines + Auth Methods
# Usage: ./scripts/setup-engines.sh
#        ENV=staging ./scripts/setup-engines.sh
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/common.sh"

info "Enabling KV v2 at secret/..."
vaultcmd secrets enable -path=secret -version=2 kv \
  && ok "KV v2 enabled" || info "Already enabled"

info "Enabling AppRole auth..."
vaultcmd auth enable approle \
  && ok "AppRole enabled" || info "Already enabled"

info "Enabling Database engine..."
vaultcmd secrets enable database \
  && ok "Database engine enabled" || info "Already enabled"

info "Enabling PKI engine..."
vaultcmd secrets enable pki \
  && ok "PKI engine enabled" || info "Already enabled"

vaultcmd secrets tune -max-lease-ttl=87600h pki
ok "PKI max TTL set to 87600h"

echo ""
echo "========================================"
echo " Engines ready."
echo " Project: ${VAULT_PROJECT} | Env: ${VAULT_ENV}"
echo " Next: ./scripts/setup-auth.sh"
echo "========================================"
