# =============================================================================
# Policy: services
# Services: audit-log, ia, notifications
# Each service reads only its own path.
# Add a new stanza here when onboarding a new microservice.
# =============================================================================

path "secret/data/kafka-template/+/services/audit-log" {
  capabilities = ["read"]
}

path "secret/metadata/kafka-template/+/services/audit-log" {
  capabilities = ["read", "list"]
}

path "secret/data/kafka-template/+/services/ia" {
  capabilities = ["read"]
}

path "secret/metadata/kafka-template/+/services/ia" {
  capabilities = ["read", "list"]
}

path "secret/data/kafka-template/+/services/notifications" {
  capabilities = ["read"]
}

path "secret/metadata/kafka-template/+/services/notifications" {
  capabilities = ["read", "list"]
}
