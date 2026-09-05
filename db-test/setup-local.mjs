/*
 * 本地環境的一次性設定，`supabase db reset` 之後重跑即可。
 *   1. 啟用 pg_cron 並掛上每 10 分鐘的撮合排程
 *   2. 建立管理員帳號並寫入 admins 表
 * 走 GoTrue 的 admin API 而不是直接 insert auth.users，才不會被 GoTrue 版本差異咬到。
 */
import { execFileSync } from 'node:child_process'

const API = process.env.SUPABASE_URL || 'http://127.0.0.1:54321'
const SERVICE = process.env.SUPABASE_SERVICE_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU'
const CONTAINER = process.env.SUPABASE_DB_CONTAINER || 'supabase_db_switch-class'
const EMAIL = process.env.ADMIN_EMAIL || 'admin@local.test'
const PASSWORD = process.env.ADMIN_PASSWORD || 'admin12345'

const psql = (sql) =>
  execFileSync('docker', ['exec', '-i', CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres', '-At', '-c', sql],
    { encoding: 'utf8' }).trim()

console.log('1) pg_cron')
psql('create extension if not exists pg_cron;')
psql(`select cron.schedule('swap-matching', '*/10 * * * *', $$ select public.run_matching() $$);`)
psql(`select cron.schedule('team-matching', '*/10 * * * *', $$ select public.run_teaming() $$);`)
console.log('   ' + psql(`select jobname || '  ' || schedule || '  active=' || active from cron.job`))

console.log('2) 管理員帳號')
const res = await fetch(`${API}/auth/v1/admin/users`, {
  method: 'POST',
  headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: EMAIL, password: PASSWORD, email_confirm: true })
})
const body = await res.json()
if (!res.ok && !JSON.stringify(body).includes('already been registered')) {
  console.error('   建立失敗：', body); process.exit(1)
}
psql(`insert into admins (user_id, email)
      select id, email from auth.users where email = '${EMAIL}'
      on conflict (user_id) do nothing;`)
console.log('   ' + psql(`select email || '  →  ' || user_id from admins`))
console.log(`\n完成。管理頁登入：${EMAIL} / ${PASSWORD}`)
