# =============================================================================
# Policy: gateway
# Services: Kong
# =============================================================================

path "secret/data/kafka-template/+/gateway/*" {
  capabilities = ["read"]
}

path "secret/metadata/kafka-template/+/gateway/*" {
  capabilities = ["read", "list"]
}
