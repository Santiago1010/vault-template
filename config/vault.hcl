# =============================================================================
# Vault Server Configuration — Local Development
# Production overrides: TLS listener, AWS KMS auto-unseal
# =============================================================================

ui = true

# -----------------------------------------------------------------------------
# Listener — plaintext for local, TLS for production
# -----------------------------------------------------------------------------
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = true

  # Production: replace with:
  # tls_disable       = false
  # tls_cert_file     = "/vault/tls/vault.crt"
  # tls_key_file      = "/vault/tls/vault.key"
}

# -----------------------------------------------------------------------------
# Storage — Raft integrated (single node for local)
# -----------------------------------------------------------------------------
storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node-1"
}

# -----------------------------------------------------------------------------
# Cluster addresses
# -----------------------------------------------------------------------------
api_addr     = "http://0.0.0.0:8200"
cluster_addr = "http://0.0.0.0:8201"

# -----------------------------------------------------------------------------
# Telemetry
# -----------------------------------------------------------------------------
telemetry {
  disable_hostname = true
}

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log_level  = "info"
log_format = "json"

# -----------------------------------------------------------------------------
# Auto-unseal — AWS KMS (production only)
# Uncomment when deploying to EC2
# -----------------------------------------------------------------------------
# seal "awskms" {
#   region     = "us-east-1"
#   kms_key_id = "alias/vault-unseal"
# }