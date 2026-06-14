# =============================================================================
# Policy: events
# Services: Kafka, RabbitMQ
# =============================================================================

path "secret/data/kafka-template/+/events/*" {
  capabilities = ["read"]
}

path "secret/metadata/kafka-template/+/events/*" {
  capabilities = ["read", "list"]
}
