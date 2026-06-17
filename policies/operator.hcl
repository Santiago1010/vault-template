# =============================================================================
# Policy: operator
# Used by: CI/CD scripts, automated workflows
# NOT for: root token generation, emergency access (use admin.hcl)
# =============================================================================

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

# Auth methods — manage AppRoles and policies, but no sudo
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/policies/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/audit*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/health" {
  capabilities = ["read"]
}

path "sys/seal-status" {
  capabilities = ["read"]
}

path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/mounts" {
  capabilities = ["read", "list"]
}

path "auth/token/create" {
  capabilities = ["create", "update"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}

path "sys/auth" {
  capabilities = ["read"]
}
