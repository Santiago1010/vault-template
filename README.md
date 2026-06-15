# vault-template

Production-grade HashiCorp Vault setup for secrets management across all services in the stack. Designed to run on AWS EC2 via Docker, with full local development support.

Although this repository is service-agnostic, it is purpose-built to integrate with the following infrastructure repositories:

- **Terraform**: [Santiago1010/terraform-template](https://github.com/Santiago1010/terraform-template) — provisions the EC2 instance, security groups, IAM roles, and SSM parameters that Vault depends on.
- **Ansible**: [Santiago1010/ansible-template](https://github.com/Santiago1010/ansible-template) — installs Docker, deploys the Vault container, and runs initialization on EC2.

---

## Services consuming Vault

Any service that needs secrets must authenticate via AppRole and read from its designated KV path. Below is the current list of integrated services:

| Service | AppRole | KV Path |
|---|---|---|
| Kafka | `events` | `secret/<project>/<env>/events/kafka` |
| RabbitMQ | `events` | `secret/<project>/<env>/events/rabbitmq` |
| MySQL / PostgreSQL | `database` | `secret/<project>/<env>/database/<engine>` |
| Redis | `cache` | `secret/<project>/<env>/cache/redis` |
| Kong | `gateway` | `secret/<project>/<env>/gateway/kong` |
| Consul | `discovery` | `secret/<project>/<env>/discovery/consul` |
| Microservices | `services` | `secret/<project>/<env>/services/<name>` |
| API | `api` | `secret/<project>/<env>/services/api` |

> Add your service here once it is integrated.

---

## Architecture

```
┌─────────────────────────────────────────┐
│              Vault (Docker)             │
│                                         │
│  ┌─────────┐  ┌──────────┐  ┌───────┐  │
│  │  KV v2  │  │   PKI    │  │  DB   │  │
│  │ secrets │  │   certs  │  │ creds │  │
│  └─────────┘  └──────────┘  └───────┘  │
│                                         │
│  ┌──────────────────────────────────┐   │
│  │  AppRole per service (least      │   │
│  │  privilege — read only)          │   │
│  └──────────────────────────────────┘   │
│                                         │
│  Storage: Raft (integrated)             │
│  Audit:   /vault/logs/audit.log         │
└─────────────────────────────────────────┘
```

---

## Prerequisites

### Local development

- Docker + Docker Compose
- Python 3.11+
- An existing Docker network: `kafka-network`

```bash
docker network create kafka-network
```

- OpenSSL (for password generation in `setup-database.sh`)

```bash
# Debian/Ubuntu
sudo apt install openssl
```

### AWS (staging / production)

Provisioned via [terraform-template](https://github.com/Santiago1010/terraform-template):

- EC2 instance (`t3.small`, Ubuntu 22.04)
- EBS volume (20 GB, gp3, encrypted) mounted at `/vault/data`
- Security group allowing ports `8200` and `8201` within the VPC
- IAM instance profile with `AmazonSSMManagedInstanceCore`
- SSM Parameter Store for Vault private IP

---

## Directory structure

```
vault-template/
├── config/
│   └── vault.hcl               # Vault server config (Raft storage, TCP listener)
├── policies/
│   ├── api.hcl                 # Policy for api-template
│   ├── cache.hcl               # Policy for Redis
│   ├── database.hcl            # Policy for MySQL / PostgreSQL
│   ├── discovery.hcl           # Policy for Consul
│   ├── events.hcl              # Policy for Kafka + RabbitMQ
│   ├── gateway.hcl             # Policy for Kong
│   ├── operator.hcl            # Policy for admin scripts and CI/CD
│   └── services.hcl            # Policy for microservices
├── scripts/
│   ├── common.sh               # Shared helpers — sourced by all scripts
│   ├── entrypoint-unseal.sh    # Auto-unseal on container start
│   ├── init.sh                 # Initialize Vault, unseal, enable audit log
│   ├── setup-api.sh            # Policy + AppRole for api-template
│   ├── setup-auth.sh           # Apply all policies + create AppRoles
│   ├── setup-database.sh       # Database engine — dynamic credentials
│   ├── setup-engines.sh        # Enable KV v2, AppRole, Database, PKI
│   ├── setup-hardening.sh      # TTLs, file permissions
│   ├── setup-pki.sh            # Root CA, Intermediate CA, Kafka role + cert
│   ├── setup-secrets.sh        # Write initial secrets (auto-generated passwords)
│   ├── unseal.sh               # Manual unseal after restart
│   ├── validate-approles.sh    # Validate AppRole auth flow per service
│   └── validate.sh             # Validate Vault status, engines, audit log
├── .github/
│   └── workflows/
│       ├── deploy.yml          # Full deploy: Terraform → Ansible → Vault setup
│       ├── validate.yml        # PR validation: lint + config checks
│       └── rotate.yml          # Weekly secret rotation
├── docker-compose.yml
├── .env.example
└── .env.local                  # gitignored — local environment config
```

---

## Environment configuration

All scripts read configuration from environment variables. Locally, these come from `.env.local`. In CI/CD, they are injected by GitHub Actions.

Copy the example file and fill in your values:

```bash
cp .env.example .env.local
```

`.env.example`:

```bash
VAULT_PROJECT=kafka-template    # Project identifier — matches Terraform prefix
VAULT_ENV=local                 # Environment: local | dev | staging | prod
VAULT_CONTAINER=vault-template  # Docker container name
VAULT_ADDR=http://127.0.0.1:8200
VAULT_DOMAIN=localhost          # Domain for PKI cert SANs
AWS_REGION=us-east-1

VAULT_DB_ENGINE=mysql           # mysql | postgresql
VAULT_DB_HOST=mysql             # Docker service name or private IP
VAULT_DB_PORT=3306
VAULT_DB_ROOT_USER=root
```

For staging/production, `VAULT_DB_ENGINE=postgresql` and the host/port point to the PostgreSQL EC2 instance.

---

## Local setup — step by step

### 1. Start Vault

```bash
docker compose up -d
```

Vault starts sealed. The `vault-unseal` service automatically unseals it on every restart.

### 2. Initialize (first time only)

```bash
./scripts/init.sh
```

This generates 5 unseal keys (threshold: 3), saves them to `secrets/unseal-keys.json`, saves the root token to `secrets/root-token.txt`, and enables the audit log. **Back up `secrets/` immediately — losing the unseal keys means losing access to Vault.**

### 3. Enable secrets engines and auth methods

```bash
./scripts/setup-engines.sh
```

Enables: KV v2 at `secret/`, AppRole auth, Database engine, PKI engine.

### 4. Apply policies and create AppRoles

```bash
./scripts/setup-auth.sh
```

Creates one AppRole per service with least-privilege policies. Credentials saved to `secrets/approles.json`.

### 5. Write initial secrets

```bash
./scripts/setup-secrets.sh
```

Auto-generates all passwords and writes them to KV v2. **Never hardcode passwords** — always use this script or rotate via `rotate.yml`.

### 6. Configure PKI

```bash
./scripts/setup-pki.sh
```

Generates Root CA → Intermediate CA → Kafka PKI role → issues first TLS certificate. Certs saved to `secrets/pki/`.

### 7. Configure database engine

```bash
./scripts/setup-database.sh
```

Creates a Vault management user in MySQL or PostgreSQL, configures dynamic credential roles (`debezium` with 4h TTL, `app` with 1h TTL). The database engine auto-creates and revokes temporary users — services never hold permanent credentials.

### 8. Harden

```bash
./scripts/setup-hardening.sh
```

Sets system-wide token TTLs, tunes secrets engine leases, enforces file permissions on `secrets/`.

### 9. Create operator token and revoke root

```bash
# Apply operator policy
docker cp policies/operator.hcl vault-template:/tmp/operator.hcl
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 \
  -e VAULT_TOKEN=$(cat secrets/root-token.txt) \
  vault-template vault policy write operator /tmp/operator.hcl

# Create operator token (used by scripts instead of root)
OPERATOR_TOKEN=$(docker exec \
  -e VAULT_ADDR=http://127.0.0.1:8200 \
  -e VAULT_TOKEN=$(cat secrets/root-token.txt) \
  vault-template vault token create \
  -policy=operator -ttl=720h -renewable=true -orphan=true -format=json \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['auth']['client_token'])")

echo "${OPERATOR_TOKEN}" > secrets/operator-token.txt
chmod 600 secrets/operator-token.txt

# Revoke root token
ROOT_TOKEN=$(cat secrets/root-token.txt)
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 \
  -e VAULT_TOKEN="${ROOT_TOKEN}" \
  vault-template vault token revoke "${ROOT_TOKEN}"

rm secrets/root-token.txt
```

After this step, `common.sh` uses `secrets/operator-token.txt` for all operations. The root token no longer exists.

### 10. Validate

```bash
./scripts/validate.sh && ./scripts/validate-approles.sh
```

Expected output: `Passed: 10 | Failed: 0` and `Passed: 20 | Failed: 0`.

---

## Secret rotation

### Manual

```bash
./scripts/setup-secrets.sh          # Rotates all KV secrets
ENV=staging ./scripts/setup-secrets.sh  # Specific environment
```

### Automatic (CI/CD)

The `rotate.yml` workflow runs every Sunday at 2am UTC and rotates all KV secrets via SSM on the Vault EC2 instance. Dynamic credentials (database engine) rotate automatically via TTL — no manual intervention needed.

### Secret types and rotation schedule

| Type | Rotation | How |
|---|---|---|
| KV v2 static secrets | Weekly (scheduled) or on demand | `setup-secrets.sh` |
| Database dynamic creds | Automatic — every 1–4h | Vault database engine TTL |
| PKI certificates | Automatic — before expiry | Vault Agent (when integrated) |
| AppRole `secret_id` | On demand | Re-run `setup-auth.sh` |
| Operator token | Every 30 days (manual) | `vault token renew` or recreate |

---

## Recovering the root token

If you need to perform operations that require the root token (e.g. recreating the operator token), generate a new one using the unseal keys:

```bash
# Step 1 — start generation, note OTP and Nonce
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 \
  vault-template vault operator generate-root -init -format=json \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('OTP:', d['otp']); print('Nonce:', d['nonce'])"

# Step 2 — apply 3 unseal keys
KEYS=$(python3 -c "
import json
with open('secrets/unseal-keys.json') as f:
  data = json.load(f)
for key in data['unseal_keys_b64'][:3]:
  print(key)
")

while IFS= read -r key; do
  docker exec -e VAULT_ADDR=http://127.0.0.1:8200 \
    vault-template vault operator generate-root \
    -nonce="<NONCE>" -format=json "${key}"
done <<< "${KEYS}"

# Step 3 — decode encoded_root_token with OTP
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 \
  vault-template vault operator generate-root \
  -decode="<ENCODED_TOKEN>" -otp="<OTP>" -format=json \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])"
```

**Revoke the root token again as soon as you finish.**

---

## IAM permissions

### Recommended: use terraform-template

The [terraform-template](https://github.com/Santiago1010/terraform-template) repository provisions a dedicated IAM user `github-actions-vault` with the exact permissions required. Run `terraform apply` in `environments/dev` and use the outputs:

```bash
terraform output github_actions_vault_access_key_id
terraform output -raw github_actions_vault_secret_access_key
```

### Manual setup

If you are not using terraform-template, create an IAM user with the following policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformState",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::tf-state-sca-2026-9xk2", "arn:aws:s3:::tf-state-sca-2026-9xk2/*"]
    },
    {
      "Sid": "TerraformLocks",
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"],
      "Resource": "arn:aws:dynamodb:us-east-1:*:table/terraform-locks"
    },
    {
      "Sid": "EC2",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*", "ec2:CreateSecurityGroup", "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress", "ec2:DeleteSecurityGroup", "ec2:RunInstances",
        "ec2:TerminateInstances", "ec2:CreateVolume", "ec2:DeleteVolume",
        "ec2:AttachVolume", "ec2:DetachVolume", "ec2:CreateTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSM",
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand", "ssm:GetCommandInvocation", "ssm:DescribeInstanceInformation",
        "ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter", "ssm:DescribeParameters"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMPassRole",
      "Effect": "Allow",
      "Action": ["iam:PassRole", "iam:GetRole", "iam:GetInstanceProfile"],
      "Resource": "*"
    }
  ]
}
```

---

## GitHub Actions secrets and variables

### Secrets — Settings → Secrets and variables → Actions → Secrets

| Secret | Description | How to obtain |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key | `terraform output github_actions_vault_access_key_id` |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key | `terraform output -raw github_actions_vault_secret_access_key` |
| `VAULT_DB_PASSWORD` | PostgreSQL password for Vault | `python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))"` |
| `GH_PAT` | GitHub Personal Access Token | GitHub → Settings → Developer settings → Tokens (classic) → scope: `repo` |

### Variables — Settings → Secrets and variables → Actions → Variables

| Variable | Value | Notes |
|---|---|---|
| `TF_PROJECT` | `sca` | Must match the `project` variable in terraform-template |
| `POSTGRESQL_PRIVATE_IP` | Private IP of PostgreSQL EC2 | `terraform output postgresql_infra_private_ip` — add after first `terraform apply` |

---

## CI/CD workflows

| Workflow | Trigger | What it does |
|---|---|---|
| `deploy.yml` | Push to `main` or manual | Terraform → Ansible → Vault setup → Validate |
| `validate.yml` | Pull request to `main` | Shellcheck, policy lint, docker-compose config, `.env.example` key check |
| `rotate.yml` | Weekly (Sunday 2am UTC) or manual | Rotates KV secrets and operator token via SSM |

### Running deploy manually with options

Go to **Actions → Deploy Vault → Run workflow**:

- `environment`: `dev` / `staging` / `prod`
- `skip_terraform`: skip if EC2 already exists
- `skip_ansible`: skip if Vault is already installed

---

## Secrets path structure

```
secret/
└── <project>/
    └── <env>/
        ├── events/
        │   ├── kafka          sasl_username, sasl_password, keystore_password, truststore_password
        │   └── rabbitmq       username, password, erlang_cookie
        ├── database/
        │   ├── mysql          root_password, debezium_username, debezium_password, app_username, app_password
        │   └── postgresql     root_password, app_username, app_password
        ├── cache/
        │   └── redis          password
        ├── gateway/
        │   └── kong           pg_password, admin_token
        ├── discovery/
        │   └── consul         gossip_key, master_token
        └── services/
            ├── audit-log      app_secret
            ├── ia             app_secret
            ├── notifications  app_secret
            └── api            app_secret, jwt_secret
```

---

## Adding a new service

1. Create `policies/<service>.hcl` with least-privilege paths.
2. Add the service to the `SERVICES` array in `scripts/setup-auth.sh`.
3. Add initial secrets in `scripts/setup-secrets.sh`.
4. Add the service path to `SERVICE_PATHS` in `scripts/validate-approles.sh`.
5. Run:

```bash
./scripts/setup-auth.sh
./scripts/setup-secrets.sh
./scripts/validate-approles.sh
```

6. Update this README — add the service to the consumers table above.

---

## Security notes

- **Root token**: revoked after initial setup. Regenerate only when necessary using unseal keys, then revoke again immediately.
- **Operator token**: used by scripts and CI/CD. TTL: 720h, renewable. Stored in `secrets/operator-token.txt` (gitignored).
- **AppRole tokens**: TTL 1h, max 4h. Services must renew before expiry.
- **Database credentials**: dynamically generated per request, auto-revoked after TTL. Services never hold permanent DB credentials.
- **`secrets/` directory**: gitignored. Never commit keys, tokens, or certificates.
- **TLS**: disabled locally (plaintext). Enable in production by configuring `tls_cert_file` and `tls_key_file` in `config/vault.hcl`.
- **Auto-unseal**: uses Shamir keys locally. Configure AWS KMS auto-unseal for production by uncommenting the `seal "awskms"` block in `config/vault.hcl`.

---

## Pending

- [ ] AWS KMS auto-unseal for production
- [ ] GitHub Actions OIDC authentication (replace static access keys)
- [ ] Vault Agent per service (secret injection without SDK)
- [ ] Consul integration for service discovery
- [ ] Connect remaining services: Kafka, Redis, Kong, RabbitMQ, microservices