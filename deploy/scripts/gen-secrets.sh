#!/usr/bin/env bash
# 產生 .env：資料庫密碼、JWT secret，以及用該 secret 簽出的 anon / service_role 金鑰。
# 純 openssl 實作 HS256，伺服器上不需要 node。
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] && { echo ".env 已存在，不覆蓋。要重產請先自行備份刪除。"; exit 0; }

PUBLIC_URL="${1:?用法: gen-secrets.sh <PUBLIC_URL>  例如 http://101.33.199.34}"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
jwt() {  # $1 = role
  local secret="$2" now exp header payload input sig
  now=$(date +%s); exp=$((now + 3600*24*365*10))
  header='{"alg":"HS256","typ":"JWT"}'
  payload="{\"role\":\"$1\",\"iss\":\"supabase\",\"iat\":$now,\"exp\":$exp}"
  input="$(printf '%s' "$header" | b64url).$(printf '%s' "$payload" | b64url)"
  sig=$(printf '%s' "$input" | openssl dgst -sha256 -hmac "$secret" -binary | b64url)
  printf '%s.%s' "$input" "$sig"
}

POSTGRES_PASSWORD=$(openssl rand -hex 24)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(jwt anon "$JWT_SECRET")
SERVICE_KEY=$(jwt service_role "$JWT_SECRET")

umask 077
cat > .env <<EOF
# 由 scripts/gen-secrets.sh 產生 — 內含機密，不要提交到版控
PUBLIC_URL=$PUBLIC_URL
HTTP_PORT=80
NPM_REGISTRY=https://registry.npmmirror.com

POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_KEY=$SERVICE_KEY
EOF

echo "已產生 .env（權限 $(stat -c %a .env)）"
echo "PUBLIC_URL = $PUBLIC_URL"
