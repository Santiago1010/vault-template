#!/usr/bin/env bash
# =============================================================================
# Common — sourced by all scripts
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env.${ENV:-local}"

if [ ! -f "${ENV_FILE}" ]; then
  echo "[ERROR] Config not found: ${ENV_FILE}"
  echo "[INFO]  Local: copy config/.env.example to config/.env.local"
  echo "[INFO]  CI/CD: set environment variables in your pipeline"
  exit 1
fi

# shellcheck source=/dev/null
set -a
source "${ENV_FILE}"
set +a

# Derived
SECRETS_DIR="${ROOT_DIR}/secrets"
POLICIES_DIR="${ROOT_DIR}/policies"
TOKEN_FILE="${SECRETS_DIR}/operator-token.txt"
APPROLES_FILE="${SECRETS_DIR}/approles.json"
PKI_DIR="${SECRETS_DIR}/pki"

# Helpers
vaultcmd() {
  docker exec \
    -e VAULT_ADDR="${VAULT_ADDR}" \
    -e VAULT_TOKEN="$(cat "${TOKEN_FILE}")" \
    "${VAULT_CONTAINER}" vault "$@"
}

vaultexec() {
  # Use when passing VAULT_TOKEN explicitly (e.g. client tokens)
  local token="$1"; shift
  docker exec \
    -e VAULT_ADDR="${VAULT_ADDR}" \
    -e VAULT_TOKEN="${token}" \
    "${VAULT_CONTAINER}" vault "$@"
}

genpass() {
  python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))"
}

ok()   { echo "[OK]   $1"; }
fail() { echo "[FAIL] $1"; }
info() { echo "[INFO] $1"; }
