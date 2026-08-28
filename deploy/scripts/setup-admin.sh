#!/usr/bin/env bash
# 建立管理頁的管理員帳號：透過 GoTrue admin API 建使用者，再寫進 admins 表。
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

EMAIL="${1:?用法: setup-admin.sh <email> <password>}"
PASSWORD="${2:?用法: setup-admin.sh <email> <password>}"
BASE="http://127.0.0.1:${HTTP_PORT:-80}"

echo "→ 建立 GoTrue 使用者 $EMAIL"
RESP=$(curl -s -X POST "$BASE/auth/v1/admin/users" \
  -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"email_confirm\":true}")
case "$RESP" in
  *'"id"'*)                       echo "   已建立" ;;
  *already*registered*|*exists*)  echo "   已存在，沿用" ;;
  *) echo "   失敗：$RESP"; exit 1 ;;
esac

echo "→ 寫入 admins 表"
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U postgres -d postgres -q -c \
  "insert into admins (user_id, email) select id, email from auth.users where email='$EMAIL' on conflict (user_id) do nothing;"
docker compose exec -T db psql -U postgres -d postgres -At -c \
  "select '   ' || email || '  ->  ' || user_id from admins;"
echo "完成，管理頁登入：$EMAIL"
