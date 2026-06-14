# =============================================================================
# Policy: api
# Services: api-template
# =============================================================================

# Own secrets — full control
path "secret/data/kafka-template/+/services/api" {
  capabilities = ["create", "update", "read", "delete"]
}

path "secret/data/kafka-template/+/services/api/*" {
  capabilities = ["create", "update", "read", "delete"]
}

path "secret/metadata/kafka-template/+/services/api" {
  capabilities = ["read", "list", "delete"]
}

path "secret/metadata/kafka-template/+/services/api/*" {
  capabilities = ["read", "list", "delete"]
}

# Read-only access to shared services (expand as needed)
path "secret/data/kafka-template/+/database/*" {
  capabilities = ["read"]
}

path "secret/data/kafka-template/+/cache/*" {
  capabilities = ["read"]
}
