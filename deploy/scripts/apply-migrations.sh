#!/usr/bin/env bash
# 套用 app/supabase/migrations 底下的所有 SQL，並設定 PostgREST / GoTrue 所需的角色密碼。
# 可重複執行：migration 本身都是 if not exists / create or replace。
#
# 角色分工（supabase/postgres 映像裡 postgres 並非 superuser）：
#   supabase_admin  真正的 superuser — 改保留角色的密碼、建 pg_cron
#   postgres        migration 的執行者 — 表與函式的擁有者必須是它，
#                   SECURITY DEFINER 繞過 RLS 才成立（與線上 Supabase 一致）
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

dc() { docker compose "$@"; }
as_admin() { dc exec -T db psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres "$@"; }
as_pg()    { dc exec -T db psql -v ON_ERROR_STOP=1 -U postgres       -d postgres "$@"; }

echo "→ 等待資料庫就緒"
until dc exec -T db pg_isready -U postgres -d postgres >/dev/null 2>&1; do sleep 2; done

echo "→ 設定服務角色密碼（authenticator / supabase_auth_admin 是保留角色，需 superuser）"
as_admin -q -c "alter role authenticator       with login password '${POSTGRES_PASSWORD}';"
as_admin -q -c "alter role supabase_auth_admin with login password '${POSTGRES_PASSWORD}';"

echo "→ 套用 migration"
for f in app/supabase/migrations/*.sql; do
  printf '   %s ... ' "$(basename "$f")"
  as_pg -q < "$f"
  echo "ok"
done

echo "→ 啟用 pg_cron 排程（每 10 分鐘撮合一次）"
as_admin -q -c "create extension if not exists pg_cron;"
as_admin -q -c "select cron.schedule('swap-matching', '*/10 * * * *', \$\$ select public.run_matching() \$\$);" >/dev/null
as_admin -t -c "select '   ' || jobname || '  ' || schedule || '  active=' || active from cron.job;"

echo "→ 重啟 PostgREST / GoTrue"
dc up -d --force-recreate rest auth >/dev/null 2>&1
echo "完成"
