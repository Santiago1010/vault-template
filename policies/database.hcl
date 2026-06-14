# =============================================================================
# Policy: database
# Services: MySQL, PostgreSQL
# =============================================================================

path "secret/data/kafka-template/+/database/*" {
  capabilities = ["read"]
}

path "secret/metadata/kafka-template/+/database/*" {
  capabilities = ["read", "list"]
}

# Dynamic credentials via database engine
path "database/creds/+" {
  capabilities = ["read"]
}
