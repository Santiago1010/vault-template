#!/usr/bin/env bash
# =============================================================================
# Vault AppRole Validation — Tests real auth flow per service
# =============================================================================

set -euo pipefail

CONTAINER="vault-template"
VAULT_ADDR="http://127.0.0.1:8200"
SECRETS_DIR="$(dirname "$0")/../secrets"
APPROLES_FILE="${SECRETS_DIR}/approles.json"
ENV="local"
PROJECT="kafka-template"

PASS=0
FAIL=0

ok()   { echo "[OK]   $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }
info() { echo "[INFO] $1"; }

# service -> path to read
declare -A SERVICE_PATHS
SERVICE_PATHS=(
  ["events"]="secret/data/${PROJECT}/${ENV}/events/kafka"
  ["database"]="secret/data/${PROJECT}/${ENV}/database/mysql"
  ["cache"]="secret/data/${PROJECT}/${ENV}/cache/redis"
  ["gateway"]="secret/data/${PROJECT}/${ENV}/gateway/kong"
  ["discovery"]="secret/data/${PROJECT}/${ENV}/discovery/consul"
  ["services"]="secret/data/${PROJECT}/${ENV}/services/audit-log"
  ["api"]="secret/data/${PROJECT}/${ENV}/services/api"
)

if [ ! -f "${APPROLES_FILE}" ]; then
  echo "[ERROR] ${APPROLES_FILE} not found. Run setup-auth.sh first."
  exit 1
fi

echo "========================================"
echo " AppRole Auth Flow Validation"
echo "========================================"
echo ""

for service in "${!SERVICE_PATHS[@]}"; do
  info "Testing service: ${service}"

  ROLE_ID=$(python3 -c "import json; d=json.load(open('${APPROLES_FILE}')); print(d['${service}']['role_id'])")
  SECRET_ID=$(python3 -c "import json; d=json.load(open('${APPROLES_FILE}')); print(d['${service}']['secret_id'])")
  TARGET_PATH="${SERVICE_PATHS[$service]}"

  # Login with AppRole — get client token
  LOGIN=$(docker exec \
    -e VAULT_ADDR="${VAULT_ADDR}" \
    "${CONTAINER}" vault write -format=json auth/approle/login \
    role_id="${ROLE_ID}" \
    secret_id="${SECRET_ID}" 2>/dev/null || echo "")

  if [ -z "${LOGIN}" ]; then
    fail "${service}: AppRole login FAILED"
    echo ""
    continue
  fi

  CLIENT_TOKEN=$(echo "${LOGIN}" | python3 -c "import sys,json; print(json.load(sys.stdin)['auth']['client_token'])" 2>/dev/null || echo "")

  if [ -z "${CLIENT_TOKEN}" ]; then
    fail "${service}: Could not extract client token"
    echo ""
    continue
  fi

  ok "${service}: AppRole login succeeded"

  # Read secret with client token
  READ=$(docker exec \
    -e VAULT_ADDR="${VAULT_ADDR}" \
    -e VAULT_TOKEN="${CLIENT_TOKEN}" \
    "${CONTAINER}" vault read -format=json "${TARGET_PATH}" 2>/dev/null || echo "")

  if [ -z "${READ}" ]; then
    fail "${service}: Secret read FAILED (${TARGET_PATH})"
  else
    ok "${service}: Secret read succeeded (${TARGET_PATH})"
  fi

  # Verify service cannot read another service's secrets
  FORBIDDEN_PATH="secret/data/${PROJECT}/${ENV}/events/kafka"
  if [ "${service}" != "events" ]; then
    DENIED=$(docker exec \
      -e VAULT_ADDR="${VAULT_ADDR}" \
      -e VAULT_TOKEN="${CLIENT_TOKEN}" \
      "${CONTAINER}" vault read -format=json "${FORBIDDEN_PATH}" 2>&1 || echo "permission denied")

    if echo "${DENIED}" | grep -q "permission denied"; then
      ok "${service}: Correctly denied access to events/kafka"
    else
      fail "${service}: Should NOT have access to events/kafka"
    fi
  fi

  echo ""
done

echo "========================================"
echo " AppRole validation complete"
echo " Passed: ${PASS}"
echo " Failed: ${FAIL}"
echo "========================================"

[ "${FAIL}" -eq 0 ] && exit 0 || exit 1
