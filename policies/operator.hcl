# =============================================================================
# Policy: operator
# For: admin scripts, CI/CD
# NOT for services — use AppRole per service
# =============================================================================

# Secrets engines
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "database/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "pki/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "pki_int/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Auth methods
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Policies
path "sys/policies/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Audit
path "sys/audit*" {
  capabilities = ["read", "list"]
}

# Health + seal status
path "sys/health" {
  capabilities = ["read"]
}

path "sys/seal-status" {
  capabilities = ["read"]
}

# Secrets engine management
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/mounts" {
  capabilities = ["read", "list"]
}

# Token management — own tokens only
path "auth/token/create" {
  capabilities = ["create", "update"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}
