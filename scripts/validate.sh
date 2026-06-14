#!/usr/bin/env bash
# =============================================================================
# Vault Validation
# Usage: ./scripts/validate.sh
#        ENV=staging ./scripts/validate.sh
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/common.sh"

PASS=0
FAIL=0

_ok()   { echo "[OK]   $1"; PASS=$((PASS + 1)); }
_fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

if ! docker ps --format '{{.Names}}' | grep -q "^${VAULT_CONTAINER}$"; then
  echo "[ERROR] Container ${VAULT_CONTAINER} is not running."
  exit 1
fi

# Status
info "Checking Vault status..."
STATUS=$(vaultcmd status -format=json 2>/dev/null || true)

echo "${STATUS}" | python3 -c "import sys,json; exit(0 if json.load(sys.stdin)['initialized'] else 1)" \
  && _ok "Vault is initialized" || _fail "Vault is NOT initialized"

echo "${STATUS}" | python3 -c "import sys,json; exit(0 if not json.load(sys.stdin)['sealed'] else 1)" \
  && _ok "Vault is unsealed" || _fail "Vault is sealed"

# Auth methods
info "Checking auth methods..."
AUTH=$(vaultcmd auth list -format=json 2>/dev/null || echo "{}")

echo "${AUTH}" | python3 -c "import sys,json; exit(0 if 'approle/' in json.load(sys.stdin) else 1)" \
  && _ok "AppRole auth enabled" || _fail "AppRole NOT enabled"

echo "${AUTH}" | python3 -c "import sys,json; exit(0 if 'token/' in json.load(sys.stdin) else 1)" \
  && _ok "Token auth enabled" || _fail "Token auth NOT enabled"

# Secrets engines
info "Checking secrets engines..."
MOUNTS=$(vaultcmd secrets list -format=json 2>/dev/null || echo "{}")

for engine in "secret/" "database/" "pki/"; do
  echo "${MOUNTS}" | python3 -c "import sys,json; exit(0 if '${engine}' in json.load(sys.stdin) else 1)" \
    && _ok "${engine} enabled" || _fail "${engine} NOT enabled"
done

# Audit log
info "Checking audit log..."
AUDIT=$(vaultcmd audit list -format=json 2>/dev/null || echo "{}")
echo "${AUDIT}" | python3 -c "import sys,json; exit(0 if 'file/' in json.load(sys.stdin) else 1)" \
  && _ok "Audit log enabled" || _fail "Audit log NOT enabled"

# KV smoke test
info "Running KV smoke test..."
vaultcmd kv put secret/validate/smoke test=ok > /dev/null 2>&1 \
  && _ok "KV write succeeded" || _fail "KV write FAILED"

READ=$(vaultcmd kv get -field=test secret/validate/smoke 2>/dev/null || echo "")
[ "${READ}" = "ok" ] && _ok "KV read succeeded" || _fail "KV read FAILED"
vaultcmd kv delete secret/validate/smoke > /dev/null 2>&1 || true

echo ""
echo "========================================"
echo " Validation complete"
echo " Project: ${VAULT_PROJECT} | Env: ${VAULT_ENV}"
echo " Passed: ${PASS} | Failed: ${FAIL}"
echo "========================================"

[ "${FAIL}" -eq 0 ] && exit 0 || exit 1
