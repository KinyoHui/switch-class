#!/usr/bin/env bash
# 一鍵部署：產金鑰 → 建置前端映像 → 起服務 → 套 migration。
# 重複執行是安全的：.env 已存在就不覆蓋，migration 全部冪等。
set -euo pipefail
cd "$(dirname "$0")"

PUBLIC_URL="${PUBLIC_URL:-${1:-}}"
[ -f .env ] || { [ -n "$PUBLIC_URL" ] || { echo "首次部署請給 PUBLIC_URL，例如：./deploy.sh http://101.33.199.34"; exit 1; }; }
[ -f .env ] || ./scripts/gen-secrets.sh "$PUBLIC_URL"

echo "==> 建置並啟動"
docker compose up -d --build

echo "==> 套用資料庫"
./scripts/apply-migrations.sh

echo
docker compose ps
echo
set -a; . ./.env; set +a
echo "前端： $PUBLIC_URL"
echo "管理員帳號尚未建立，執行： ./scripts/setup-admin.sh <email> <password>"
