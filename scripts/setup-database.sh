#!/usr/bin/env bash
# =============================================================================
# Vault Database Engine — Dynamic credentials
# Supports: mysql | postgresql
# Usage: ./scripts/setup-database.sh
#        ENV=staging ./scripts/setup-database.sh
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/common.sh"

# -----------------------------------------------------------------------------
# Engine config
# -----------------------------------------------------------------------------
case "${VAULT_DB_ENGINE}" in
  mysql)
    DB_PLUGIN="mysql-database-plugin"
    DB_CONNECTION_URL="{{username}}:{{password}}@tcp(${VAULT_DB_HOST}:${VAULT_DB_PORT})/"
    DB_DEBEZIUM_GRANTS="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO '{{name}}'@'%';FLUSH PRIVILEGES;"
    DB_APP_GRANTS="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT, INSERT, UPDATE, DELETE ON \`${VAULT_PROJECT}\`.* TO '{{name}}'@'%';FLUSH PRIVILEGES;"
    DB_REVOKE="DROP USER IF EXISTS '{{name}}'@'%';"
    ;;
  postgresql)
    DB_PLUGIN="postgresql-database-plugin"
    DB_CONNECTION_URL="postgresql://{{username}}:{{password}}@${VAULT_DB_HOST}:${VAULT_DB_PORT}/postgres?sslmode=disable"
    DB_DEBEZIUM_GRANTS="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";ALTER ROLE \"{{name}}\" REPLICATION;"
    DB_APP_GRANTS="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";"
    DB_REVOKE="DROP ROLE IF EXISTS \"{{name}}\";"
    ;;
  *)
    echo "[ERROR] Unsupported VAULT_DB_ENGINE: ${VAULT_DB_ENGINE}"
    exit 1
    ;;
esac

info "Database engine: ${VAULT_DB_ENGINE} @ ${VAULT_DB_HOST}:${VAULT_DB_PORT}"

# -----------------------------------------------------------------------------
# 1. Read root password from Vault KV
# -----------------------------------------------------------------------------
info "Reading root password from Vault KV..."

DB_ROOT_PASSWORD=$(vaultcmd kv get \
  -field=root_password \
  "secret/${VAULT_PROJECT}/${VAULT_ENV}/database/${VAULT_DB_ENGINE}")

ok "Root password retrieved"

# -----------------------------------------------------------------------------
# 2. Create Vault management user
# -----------------------------------------------------------------------------
info "Creating Vault management user in ${VAULT_DB_ENGINE}..."

VAULT_DB_PASS=$(openssl rand -hex 16)

case "${VAULT_DB_ENGINE}" in
  mysql)
    docker exec \
      -e MYSQL_PWD="${DB_ROOT_PASSWORD}" \
      "${VAULT_DB_HOST}" \
      mysql -u"${VAULT_DB_ROOT_USER}" -e \
      "CREATE USER IF NOT EXISTS 'vault'@'%' IDENTIFIED BY '${VAULT_DB_PASS}';
       GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, RELOAD, PROCESS,
             REFERENCES, INDEX, ALTER, SHOW DATABASES, CREATE TEMPORARY TABLES,
             LOCK TABLES, EXECUTE, REPLICATION SLAVE, REPLICATION CLIENT,
             CREATE VIEW, SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE,
             CREATE USER, EVENT, TRIGGER ON *.* TO 'vault'@'%' WITH GRANT OPTION;
       FLUSH PRIVILEGES;"
    ;;
  postgresql)
    docker exec \
      -e PGPASSWORD="${DB_ROOT_PASSWORD}" \
      "${VAULT_DB_HOST}" \
      psql -U "${VAULT_DB_ROOT_USER}" -c \
      "CREATE ROLE vault WITH LOGIN PASSWORD '${VAULT_DB_PASS}' CREATEROLE;
       GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO vault;"
    ;;
esac

vaultcmd kv patch "secret/${VAULT_PROJECT}/${VAULT_ENV}/database/${VAULT_DB_ENGINE}" \
  vault_username="vault" \
  vault_password="${VAULT_DB_PASS}"

ok "Vault management user created"

# -----------------------------------------------------------------------------
# 3. Configure database engine connection
# -----------------------------------------------------------------------------
info "Configuring ${VAULT_DB_ENGINE} connection in Vault..."

vaultcmd write "database/config/${VAULT_DB_ENGINE}" \
  plugin_name="${DB_PLUGIN}" \
  connection_url="${DB_CONNECTION_URL}" \
  allowed_roles="debezium,app" \
  username="vault" \
  password="${VAULT_DB_PASS}"

ok "${VAULT_DB_ENGINE} connection configured"

# -----------------------------------------------------------------------------
# 4. Debezium role
# -----------------------------------------------------------------------------
info "Creating Debezium role..."

vaultcmd write "database/roles/debezium" \
  db_name="${VAULT_DB_ENGINE}" \
  creation_statements="${DB_DEBEZIUM_GRANTS}" \
  revocation_statements="${DB_REVOKE}" \
  default_ttl=4h \
  max_ttl=24h

ok "Debezium role created (TTL: 4h / max: 24h)"

# -----------------------------------------------------------------------------
# 5. App role
# -----------------------------------------------------------------------------
info "Creating app role..."

vaultcmd write "database/roles/app" \
  db_name="${VAULT_DB_ENGINE}" \
  creation_statements="${DB_APP_GRANTS}" \
  revocation_statements="${DB_REVOKE}" \
  default_ttl=1h \
  max_ttl=4h

ok "App role created (TTL: 1h / max: 4h)"

# -----------------------------------------------------------------------------
# 6. Smoke test
# -----------------------------------------------------------------------------
info "Testing dynamic credential generation..."

CREDS=$(vaultcmd read -format=json "database/creds/debezium")
DB_USER=$(echo "${CREDS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['username'])")

case "${VAULT_DB_ENGINE}" in
  mysql)
    USER_EXISTS=$(docker exec \
      -e MYSQL_PWD="${DB_ROOT_PASSWORD}" \
      "${VAULT_DB_HOST}" \
      mysql -u"${VAULT_DB_ROOT_USER}" \
      -se "SELECT COUNT(*) FROM mysql.user WHERE User='${DB_USER}';" 2>/dev/null || echo "0")
    [ "${USER_EXISTS}" = "1" ] \
      && ok "Dynamic Debezium user verified: ${DB_USER}" \
      || fail "Dynamic user NOT found in MySQL"
    ;;
  postgresql)
    USER_EXISTS=$(docker exec \
      -e PGPASSWORD="${DB_ROOT_PASSWORD}" \
      "${VAULT_DB_HOST}" \
      psql -U "${VAULT_DB_ROOT_USER}" \
      -tAc "SELECT COUNT(*) FROM pg_roles WHERE rolname='${DB_USER}';" 2>/dev/null || echo "0")
    [ "${USER_EXISTS}" = "1" ] \
      && ok "Dynamic Debezium user verified: ${DB_USER}" \
      || fail "Dynamic user NOT found in PostgreSQL"
    ;;
esac

echo ""
echo "========================================"
echo " Database engine ready."
echo " Project:  ${VAULT_PROJECT} | Env: ${VAULT_ENV}"
echo " Engine:   ${VAULT_DB_ENGINE}"
echo " Roles:    debezium (4h), app (1h)"
echo " Next:     ./scripts/validate.sh"
echo "========================================"
