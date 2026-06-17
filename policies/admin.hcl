# =============================================================================
# Policy: admin
# Used by: humans only, emergency access
# NEVER assign to CI/CD tokens or AppRoles
# Requires: manual token creation with short TTL (max 1h)
# =============================================================================

path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "sys/audit*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "sys/auth*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "sys/health" {
  capabilities = ["read", "sudo"]
}

path "sys/policies/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "auth/token/create" {
  capabilities = ["create", "update", "sudo"]
}

path "auth/token/revoke" {
  capabilities = ["update", "sudo"]
}

path "auth/token/revoke-accessor" {
  capabilities = ["update", "sudo"]
}

path "sys/generate-root/*" {
  capabilities = ["create", "update", "sudo"]
}
