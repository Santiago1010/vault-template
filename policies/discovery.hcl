# =============================================================================
# Policy: discovery
# Services: Consul
# =============================================================================

path "secret/data/kafka-template/+/discovery/*" {
  capabilities = ["read"]
}

path "secret/metadata/kafka-template/+/discovery/*" {
  capabilities = ["read", "list"]
}
