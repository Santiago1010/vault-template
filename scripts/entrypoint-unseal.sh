#!/usr/bin/env sh
# =============================================================================
# Entrypoint — Auto-unseal on container start
# =============================================================================

set -e

KEYS_FILE="/secrets/unseal-keys.json"
VAULT_ADDR="http://vault-template:8200"

echo "[INFO] Waiting for Vault to be ready..."

# 503 = sealed but running — that's fine, we just need the server up
until wget -qO- "${VAULT_ADDR}/v1/sys/health" > /dev/null 2>&1 \
  || wget -qSO- "${VAULT_ADDR}/v1/sys/health" 2>&1 | grep -q "HTTP/"; do
  echo "[INFO] Not ready yet, retrying..."
  sleep 2
done

echo "[INFO] Vault is up. Checking seal status..."

RESPONSE=$(wget -qO- "${VAULT_ADDR}/v1/sys/health" 2>/dev/null || \
           wget --server-response -qO- "${VAULT_ADDR}/v1/sys/health" 2>/dev/null || \
           echo '{"sealed":true}')

SEALED=$(echo "${RESPONSE}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('sealed', True))
except:
    print(True)
" 2>/dev/null || echo "True")

if [ "${SEALED}" = "False" ]; then
  echo "[INFO] Vault already unsealed."
  exit 0
fi

echo "[INFO] Unsealing Vault..."

python3 - << PYEOF
import json, urllib.request, urllib.error

with open('${KEYS_FILE}') as f:
    keys = json.load(f)['unseal_keys_b64'][:3]

vault_addr = '${VAULT_ADDR}'

for i, key in enumerate(keys):
    data = json.dumps({'key': key}).encode()
    req = urllib.request.Request(
        f'{vault_addr}/v1/sys/unseal',
        data=data,
        headers={'Content-Type': 'application/json'},
        method='PUT'
    )
    try:
        resp = urllib.request.urlopen(req)
        result = json.loads(resp.read())
        print(f'[OK]   Key {i+1}/3 applied — sealed: {result.get("sealed", "?")}')
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f'[ERROR] Key {i+1} failed: {e.code} {body}')
        raise

print('[OK]   Vault unsealed.')
PYEOF
