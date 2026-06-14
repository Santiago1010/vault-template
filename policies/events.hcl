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

# PKI — issue certs for Kafka
path "pki_int/issue/kafka" {
  capabilities = ["create", "update"]
}

path "pki_int/cert/*" {
  capabilities = ["read"]
}
