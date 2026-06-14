# =============================================================================
# Policy: services
# Services: audit-log, ia, notifications
# =============================================================================

path "secret/data/kafka-template/+/services/*" {
  capabilities = ["read"]
}

path "secret/metadata/kafka-template/+/services/*" {
  capabilities = ["read", "list"]
}
