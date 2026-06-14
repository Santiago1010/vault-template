#!/usr/bin/env bash
# =============================================================================
# Vault AppRole Validation
# Usage: ./scripts/validate-approles.sh
#        ENV=staging ./scripts/validate-approles.sh
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/common.sh"

PASS=0
FAIL=0

_ok()   { echo "[OK]   $1"; PASS=$((PASS + 1)); }
_fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

declare -A SERVICE_PATHS
SERVICE_PATHS=(
  ["events"]="secret/data/${VAULT_PROJECT}/${VAULT_ENV}/events/kafka"
  ["database"]="secret/data/${VAULT_PROJECT}/${VAULT_ENV}/database/mysql"
  ["cache"]="secret/data/${VAULT_PROJECT}/${VAULT_ENV}/cache/redis"
  ["gateway"]="secret/data/${VAULT_PROJECT}/${VAULT_ENV}/gateway/kong"
  ["discovery"]="secret/data/${VAULT_PROJECT}/${VAULT_ENV}/discovery/consul"
  ["services"]="secret/data/${VAULT_PROJECT}/${VAULT_ENV}/services/audit-log"
  ["api"]="secret/data/${VAULT_PROJECT}/${VAULT_ENV}/services/api"
)

echo "========================================"
echo " AppRole Auth Flow Validation"
echo " Project: ${VAULT_PROJECT} | Env: ${VAULT_ENV}"
echo "========================================"
echo ""

for service in "${!SERVICE_PATHS[@]}"; do
  info "Testing service: ${service}"

  ROLE_ID=$(python3 -c "import json; d=json.load(open('${APPROLES_FILE}')); print(d['${service}']['role_id'])")
  SECRET_ID=$(python3 -c "import json; d=json.load(open('${APPROLES_FILE}')); print(d['${service}']['secret_id'])")
  TARGET_PATH="${SERVICE_PATHS[$service]}"

  LOGIN=$(docker exec \
    -e VAULT_ADDR="${VAULT_ADDR}" \
    "${VAULT_CONTAINER}" vault write -format=json auth/approle/login \
    role_id="${ROLE_ID}" \
    secret_id="${SECRET_ID}" 2>/dev/null || echo "")

  if [ -z "${LOGIN}" ]; then
    _fail "${service}: AppRole login FAILED"
    echo ""
    continue
  fi

  CLIENT_TOKEN=$(echo "${LOGIN}" | python3 -c "import sys,json; print(json.load(sys.stdin)['auth']['client_token'])" 2>/dev/null || echo "")

  if [ -z "${CLIENT_TOKEN}" ]; then
    _fail "${service}: Could not extract client token"
    echo ""
    continue
  fi

  _ok "${service}: AppRole login succeeded"

  READ=$(vaultexec "${CLIENT_TOKEN}" read -format=json "${TARGET_PATH}" 2>/dev/null || echo "")
  [ -n "${READ}" ] \
    && _ok "${service}: Secret read succeeded" \
    || _fail "${service}: Secret read FAILED (${TARGET_PATH})"

  if [ "${service}" != "events" ]; then
    FORBIDDEN="secret/data/${VAULT_PROJECT}/${VAULT_ENV}/events/kafka"
    DENIED=$(vaultexec "${CLIENT_TOKEN}" read -format=json "${FORBIDDEN}" 2>&1 || echo "permission denied")
    echo "${DENIED}" | grep -q "permission denied" \
      && _ok "${service}: Correctly denied access to events/kafka" \
      || _fail "${service}: Should NOT have access to events/kafka"
  fi

  echo ""
done

echo "========================================"
echo " AppRole validation complete"
echo " Passed: ${PASS} | Failed: ${FAIL}"
echo "========================================"

[ "${FAIL}" -eq 0 ] && exit 0 || exit 1
