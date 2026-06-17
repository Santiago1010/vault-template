#!/usr/bin/env bash
# =============================================================================
# Vault Raft Snapshot — save to S3
# Usage: ./scripts/snapshot.sh
#        ENV=staging ./scripts/snapshot.sh
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/common.sh"

TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
SNAPSHOT_FILE="/tmp/vault-snapshot-${TIMESTAMP}.snap"
S3_BUCKET="tf-state-sca-2026-9xk2"
S3_PREFIX="vault-snapshots/${VAULT_PROJECT}/${VAULT_ENV}"
S3_KEY="${S3_PREFIX}/vault-snapshot-${TIMESTAMP}.snap"

info "Taking Raft snapshot..."
vaultcmd operator raft snapshot save "${SNAPSHOT_FILE}"
ok "Snapshot saved to ${SNAPSHOT_FILE}"

info "Uploading to s3://${S3_BUCKET}/${S3_KEY}..."
aws s3 cp "${SNAPSHOT_FILE}" "s3://${S3_BUCKET}/${S3_KEY}" \
  --region "${AWS_REGION}" \
  --sse aws:kms
ok "Snapshot uploaded."

info "Cleaning up local file..."
rm -f "${SNAPSHOT_FILE}"
ok "Local file removed."

info "Pruning snapshots older than 30 days..."
aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" \
  --region "${AWS_REGION}" \
  | awk '{print $4}' \
  | while read -r key; do
      DATE=$(echo "${key}" | grep -oP '\d{8}')
      CUTOFF=$(date -u -d "30 days ago" +"%Y%m%d")
      if [ "${DATE}" \< "${CUTOFF}" ]; then
        aws s3 rm "s3://${S3_BUCKET}/${S3_PREFIX}/${key}" \
          --region "${AWS_REGION}"
        ok "Deleted old snapshot: ${key}"
      fi
    done

echo ""
echo "========================================"
echo " Snapshot complete."
echo " Project: ${VAULT_PROJECT} | Env: ${VAULT_ENV}"
echo " S3: s3://${S3_BUCKET}/${S3_KEY}"
echo "========================================"
