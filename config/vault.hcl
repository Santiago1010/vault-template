# =============================================================================
# Vault Server Configuration — Local Development
# Auto-unseal: Shamir via vault-unseal container (see docker-compose.yml)
# Production:  AWS KMS via Ansible (see ansible/roles/vault/templates/vault.hcl.j2)
# =============================================================================

ui = true

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node-1"
}

api_addr     = "http://0.0.0.0:8200"
cluster_addr = "http://0.0.0.0:8201"

telemetry {
  disable_hostname = true
}

log_level  = "info"
log_format = "json"
