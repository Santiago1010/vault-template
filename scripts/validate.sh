#!/usr/bin/env bash
# =============================================================================
# Vault Validation Script — Local Development
# =============================================================================

set -euo pipefail

CONTAINER="vault-template"
VAULT_ADDR="http://127.0.0.1:8200"
SECRETS_DIR="$(dirname "$0")/../secrets"
TOKEN_FILE="${SECRETS_DIR}/root-token.txt"

PASS=0
FAIL=0

ok()   { echo "[OK]   $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }
info() { echo "[INFO] $1"; }

# -----------------------------------------------------------------------------
# Sanity checks
# -----------------------------------------------------------------------------
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "[ERROR] Container ${CONTAINER} is not running."
  exit 1
fi

if [ ! -f "${TOKEN_FILE}" ]; then
  echo "[ERROR] Root token not found. Run scripts/init.sh first."
  exit 1
fi

ROOT_TOKEN=$(cat "${TOKEN_FILE}")

vaultcmd() {
  docker exec \
    -e VAULT_ADDR="${VAULT_ADDR}" \
    -e VAULT_TOKEN="${ROOT_TOKEN}" \
    "${CONTAINER}" vault "$@"
}

# -----------------------------------------------------------------------------
# 1. Status
# -----------------------------------------------------------------------------
info "Checking Vault status..."

STATUS=$(vaultcmd status -format=json 2>/dev/null || true)

echo "${STATUS}" | python3 -c "import sys,json; exit(0 if json.load(sys.stdin)['initialized'] else 1)" \
  && ok "Vault is initialized" || fail "Vault is NOT initialized"

echo "${STATUS}" | python3 -c "import sys,json; exit(0 if not json.load(sys.stdin)['sealed'] else 1)" \
  && ok "Vault is unsealed" || fail "Vault is sealed"

# -----------------------------------------------------------------------------
# 2. Auth methods
# -----------------------------------------------------------------------------
info "Checking auth methods..."

AUTH=$(vaultcmd auth list -format=json 2>/dev/null || echo "{}")

echo "${AUTH}" | python3 -c "import sys,json; exit(0 if 'approle/' in json.load(sys.stdin) else 1)" \
  && ok "AppRole auth enabled" || fail "AppRole auth NOT enabled (will enable later)"

echo "${AUTH}" | python3 -c "import sys,json; exit(0 if 'token/' in json.load(sys.stdin) else 1)" \
  && ok "Token auth enabled" || fail "Token auth NOT enabled"

# -----------------------------------------------------------------------------
# 3. Secrets engines
# -----------------------------------------------------------------------------
info "Checking secrets engines..."

MOUNTS=$(vaultcmd secrets list -format=json 2>/dev/null || echo "{}")

echo "${MOUNTS}" | python3 -c "import sys,json; exit(0 if 'secret/' in json.load(sys.stdin) else 1)" \
  && ok "KV v2 enabled (secret/)" || fail "KV v2 NOT enabled (will enable later)"

echo "${MOUNTS}" | python3 -c "import sys,json; exit(0 if 'database/' in json.load(sys.stdin) else 1)" \
  && ok "Database engine enabled" || fail "Database engine NOT enabled (will enable later)"

echo "${MOUNTS}" | python3 -c "import sys,json; exit(0 if 'pki/' in json.load(sys.stdin) else 1)" \
  && ok "PKI engine enabled" || fail "PKI engine NOT enabled (will enable later)"

# -----------------------------------------------------------------------------
# 4. Audit log
# -----------------------------------------------------------------------------
info "Checking audit log..."

AUDIT=$(vaultcmd audit list -format=json 2>/dev/null || echo "{}")

echo "${AUDIT}" | python3 -c "import sys,json; exit(0 if 'file/' in json.load(sys.stdin) else 1)" \
  && ok "Audit log enabled (file/)" || fail "Audit log NOT enabled"

# -----------------------------------------------------------------------------
# 5. KV smoke test
# -----------------------------------------------------------------------------
info "Running KV smoke test..."

vaultcmd kv put secret/validate/smoke test=ok > /dev/null 2>&1 \
  && ok "KV write succeeded" || fail "KV write FAILED"

READ=$(vaultcmd kv get -field=test secret/validate/smoke 2>/dev/null || echo "")
[ "${READ}" = "ok" ] \
  && ok "KV read succeeded" || fail "KV read FAILED"

vaultcmd kv delete secret/validate/smoke > /dev/null 2>&1 || true

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
