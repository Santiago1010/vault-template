#!/usr/bin/env bash
# =============================================================================
# Vault Validation Script — Local Development
# Run after init to verify Vault is fully operational
# =============================================================================

set -euo pipefail

VAULT_ADDR="http://127.0.0.1:8200"
SECRETS_DIR="$(dirname "$0")/../secrets"
TOKEN_FILE="${SECRETS_DIR}/root-token.txt"

export VAULT_ADDR

PASS=0
FAIL=0

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
ok()   { echo "[OK]   $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }
info() { echo "[INFO] $1"; }

# -----------------------------------------------------------------------------
# Sanity checks
# -----------------------------------------------------------------------------
if ! docker ps --format '{{.Names}}' | grep -q '^vault-template$'; then
  echo "[ERROR] Vault container is not running."
  exit 1
fi

if [ ! -f "${TOKEN_FILE}" ]; then
  echo "[ERROR] Root token not found at ${TOKEN_FILE}"
  echo "[INFO]  Run scripts/init.sh first."
  exit 1
fi

VAULT_TOKEN=$(cat "${TOKEN_FILE}")
export VAULT_TOKEN

# -----------------------------------------------------------------------------
# 1. Vault status
# -----------------------------------------------------------------------------
info "Checking Vault status..."

STATUS=$(docker exec vault-template vault status -format=json 2>/dev/null || true)

INITIALIZED=$(echo "${STATUS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['initialized'])" 2>/dev/null || echo "false")
SEALED=$(echo "${STATUS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['sealed'])" 2>/dev/null || echo "true")

[ "${INITIALIZED}" = "True" ] && ok "Vault is initialized" || fail "Vault is NOT initialized"
[ "${SEALED}"      = "False" ] && ok "Vault is unsealed"   || fail "Vault is sealed"

# -----------------------------------------------------------------------------
# 2. Auth methods
# -----------------------------------------------------------------------------
info "Checking auth methods..."

AUTH=$(docker exec vault-template vault auth list -format=json 2>/dev/null || echo "{}")

echo "${AUTH}" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'approle/' in d else 1)" 2>/dev/null \
  && ok "AppRole auth enabled" || fail "AppRole auth NOT enabled"

echo "${AUTH}" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'token/' in d else 1)" 2>/dev/null \
  && ok "Token auth enabled" || fail "Token auth NOT enabled"

# -----------------------------------------------------------------------------
# 3. Secrets engines
# -----------------------------------------------------------------------------
info "Checking secrets engines..."

MOUNTS=$(docker exec vault-template vault secrets list -format=json 2>/dev/null || echo "{}")

echo "${MOUNTS}" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'secret/' in d else 1)" 2>/dev/null \
  && ok "KV v2 engine enabled (secret/)" || fail "KV v2 engine NOT enabled"

echo "${MOUNTS}" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'database/' in d else 1)" 2>/dev/null \
  && ok "Database engine enabled" || fail "Database engine NOT enabled (will enable later)"

echo "${MOUNTS}" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'pki/' in d else 1)" 2>/dev/null \
  && ok "PKI engine enabled" || fail "PKI engine NOT enabled (will enable later)"

# -----------------------------------------------------------------------------
# 4. Audit log
# -----------------------------------------------------------------------------
info "Checking audit log..."

AUDIT=$(docker exec vault-template vault audit list -format=json 2>/dev/null || echo "{}")

echo "${AUDIT}" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'file/' in d else 1)" 2>/dev/null \
  && ok "Audit log enabled (file/)" || fail "Audit log NOT enabled"

# -----------------------------------------------------------------------------
# 5. KV write/read smoke test
# -----------------------------------------------------------------------------
info "Running KV smoke test..."

docker exec vault-template vault kv put secret/validate/smoke test=ok > /dev/null 2>&1 \
  && ok "KV write succeeded" || fail "KV write FAILED"

READ=$(docker exec vault-template vault kv get -field=test secret/validate/smoke 2>/dev/null || echo "")
[ "${READ}" = "ok" ] \
  && ok "KV read succeeded" || fail "KV read FAILED"

docker exec vault-template vault kv delete secret/validate/smoke > /dev/null 2>&1 || true

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "========================================"
echo " Validation complete"
echo " Passed: ${PASS}"
echo " Failed: ${FAIL}"
echo "========================================"

[ "${FAIL}" -eq 0 ] && exit 0 || exit 1