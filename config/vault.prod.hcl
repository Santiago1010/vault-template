# =============================================================================
# Vault Server Configuration — Production
# Auto-unseal: AWS KMS
# TLS: certificados montados en /vault/certs/
# =============================================================================

ui = true

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/certs/vault.crt"
  tls_key_file  = "/vault/certs/vault.key"
}

seal "awskms" {
  region     = "${AWS_REGION}"
  kms_key_id = "${VAULT_KMS_KEY_ID}"
}

storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node-1"
}

api_addr     = "https://0.0.0.0:8200"
cluster_addr = "https://0.0.0.0:8201"

telemetry {
  disable_hostname = true
}

log_level  = "info"
log_format = "json"
