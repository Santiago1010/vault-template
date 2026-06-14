#!/usr/bin/env bash
# =============================================================================
# Vault KV v2 — Initial Secrets
# Auto-generates all passwords. Run once after setup-auth.sh.
# =============================================================================

set -euo pipefail

CONTAINER="vault-template"
VAULT_ADDR="http://127.0.0.1:8200"
SECRETS_DIR="$(dirname "$0")/../secrets"
TOKEN_FILE="${SECRETS_DIR}/root-token.txt"
ENV="${1:-local}"
PROJECT="kafka-template"

ROOT_TOKEN=$(cat "${TOKEN_FILE}")

vaultcmd() {
  docker exec \
    -e VAULT_ADDR="${VAULT_ADDR}" \
    -e VAULT_TOKEN="${ROOT_TOKEN}" \
    "${CONTAINER}" vault "$@"
}

genpass() {
  python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))"
}

BASE="secret/${PROJECT}/${ENV}"

echo "[INFO] Writing secrets for project=${PROJECT} env=${ENV}..."

# -----------------------------------------------------------------------------
# events/ — Kafka + RabbitMQ
# -----------------------------------------------------------------------------
echo "[INFO] events/kafka..."
vaultcmd kv put "${BASE}/events/kafka" \
  sasl_username="kafka-admin" \
  sasl_password="$(genpass)" \
  keystore_password="$(genpass)" \
  truststore_password="$(genpass)"

echo "[INFO] events/rabbitmq..."
vaultcmd kv put "${BASE}/events/rabbitmq" \
  username="rabbit-admin" \
  password="$(genpass)" \
  erlang_cookie="$(genpass)"

# -----------------------------------------------------------------------------
# database/ — MySQL, PostgreSQL
# -----------------------------------------------------------------------------
echo "[INFO] database/mysql..."
vaultcmd kv put "${BASE}/database/mysql" \
  root_password="$(genpass)" \
  debezium_username="debezium" \
  debezium_password="$(genpass)" \
  app_username="app" \
  app_password="$(genpass)"

echo "[INFO] database/postgresql..."
vaultcmd kv put "${BASE}/database/postgresql" \
  root_password="$(genpass)" \
  app_username="app" \
  app_password="$(genpass)"

# -----------------------------------------------------------------------------
# cache/ — Redis
# -----------------------------------------------------------------------------
echo "[INFO] cache/redis..."
vaultcmd kv put "${BASE}/cache/redis" \
  password="$(genpass)"

# -----------------------------------------------------------------------------
# gateway/ — Kong
# -----------------------------------------------------------------------------
echo "[INFO] gateway/kong..."
vaultcmd kv put "${BASE}/gateway/kong" \
  pg_password="$(genpass)" \
  admin_token="$(genpass)"

# -----------------------------------------------------------------------------
# discovery/ — Consul
# -----------------------------------------------------------------------------
echo "[INFO] discovery/consul..."
vaultcmd kv put "${BASE}/discovery/consul" \
  gossip_key="$(python3 -c "import secrets; import base64; print(base64.b64encode(secrets.token_bytes(32)).decode())")" \
  master_token="$(genpass)"

# -----------------------------------------------------------------------------
# services/
# -----------------------------------------------------------------------------
echo "[INFO] services/audit-log..."
vaultcmd kv put "${BASE}/services/audit-log" \
  app_secret="$(genpass)"

echo "[INFO] services/ia..."
vaultcmd kv put "${BASE}/services/ia" \
  app_secret="$(genpass)"

echo "[INFO] services/notifications..."
vaultcmd kv put "${BASE}/services/notifications" \
  app_secret="$(genpass)"

echo ""
echo "========================================"
echo " Secrets written for env: ${ENV}"
echo " Verify: vault kv list secret/${PROJECT}/${ENV}/"
echo "========================================"
