#!/usr/bin/env bash
# =============================================================================
# Vault KV v2 — Initial Secrets
# Usage: ./scripts/setup-secrets.sh
#        ENV=staging ./scripts/setup-secrets.sh
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/common.sh"

BASE="secret/${VAULT_PROJECT}/${VAULT_ENV}"

info "Writing secrets | project=${VAULT_PROJECT} env=${VAULT_ENV}..."

# events
vaultcmd kv put "${BASE}/events/kafka" \
  sasl_username="kafka-admin" \
  sasl_password="$(genpass)" \
  keystore_password="$(genpass)" \
  truststore_password="$(genpass)"
ok "events/kafka"

vaultcmd kv put "${BASE}/events/rabbitmq" \
  username="rabbit-admin" \
  password="$(genpass)" \
  erlang_cookie="$(genpass)"
ok "events/rabbitmq"

# database
vaultcmd kv put "${BASE}/database/mysql" \
  root_password="$(genpass)" \
  debezium_username="debezium" \
  debezium_password="$(genpass)" \
  app_username="app" \
  app_password="$(genpass)"
ok "database/mysql"

vaultcmd kv put "${BASE}/database/postgresql" \
  root_password="$(genpass)" \
  app_username="app" \
  app_password="$(genpass)"
ok "database/postgresql"

# cache
vaultcmd kv put "${BASE}/cache/redis" \
  password="$(genpass)"
ok "cache/redis"

# gateway
vaultcmd kv put "${BASE}/gateway/kong" \
  pg_password="$(genpass)" \
  admin_token="$(genpass)"
ok "gateway/kong"

# discovery
vaultcmd kv put "${BASE}/discovery/consul" \
  gossip_key="$(python3 -c "import secrets,base64; print(base64.b64encode(secrets.token_bytes(32)).decode())")" \
  master_token="$(genpass)"
ok "discovery/consul"

# services
vaultcmd kv put "${BASE}/services/audit-log" \
  app_secret="$(genpass)"
ok "services/audit-log"

vaultcmd kv put "${BASE}/services/ia" \
  app_secret="$(genpass)"
ok "services/ia"

vaultcmd kv put "${BASE}/services/notifications" \
  app_secret="$(genpass)"
ok "services/notifications"

vaultcmd kv put "${BASE}/services/api" \
  app_secret="$(genpass)" \
  jwt_secret="$(genpass)"
ok "services/api"

echo ""
echo "========================================"
echo " Secrets written."
echo " Project: ${VAULT_PROJECT} | Env: ${VAULT_ENV}"
echo " Next: ./scripts/setup-hardening.sh"
echo "========================================"
