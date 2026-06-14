# =============================================================================
# Policy: cache
# Services: Redis
# =============================================================================

path "secret/data/kafka-template/+/cache/*" {
  capabilities = ["read"]
}

path "secret/metadata/kafka-template/+/cache/*" {
  capabilities = ["read", "list"]
}
