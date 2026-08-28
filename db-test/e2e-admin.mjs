import { createClient } from '@supabase/supabase-js'

const URL = 'http://127.0.0.1:54321'
const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0'

const sb = createClient(URL, ANON)
let fail = 0
const ok = (c, m) => { console.log(`${c ? '✓' : '✗'} ${m}`); if (!c) fail++ }

console.log('--- 未登入 ---')
ok(!!(await sb.rpc('admin_overview')).error, 'anon 叫不動 admin_overview')

console.log('\n--- 登入 ---')
const { error: authErr } = await sb.auth.signInWithPassword({ email: 'admin@local.test', password: 'admin12345' })
ok(!authErr, `signInWithPassword${authErr ? ' → ' + authErr.message : ' 成功'}`)

const { data: adminRow } = await sb.from('admins').select('user_id').limit(1)
ok(adminRow?.length === 1, 'policy "read own admin" 讀得到自己那列（前端據此判定管理員）')

console.log('\n--- 總覽 ---')
const { data: ov, error: ovErr } = await sb.rpc('admin_overview')
ok(!ovErr && ov.length === 4, `admin_overview 回 ${ov?.length} 門課${ovErr ? ' ' + ovErr.message : ''}`)
for (const c of ov || []) console.log(`   ${c.course_code}  組別 ${c.group_count}  意向 ${c.open_requests}  候選組 ${c.pending_matches}`)

console.log('\n--- 課表匯入（模擬管理頁貼上解析後匯入）---')
const { parseTimetable } = await import('../src/lib/parseTimetable.js')
const text = `ENVR 8961SCF 環境影響評估（二○二六年秋季學期）  修讀期：一學期
序 組別  類別      日期及時間          地點          開始/結束日期
1  T01  FT 面授課  Fri 19:00 - 20:50  JCC / E0313   04/09/2026 - 27/11/2026
1  T02  FT 面授課  Sat 11:00 - 12:50  HKMU / C0G01  05/09/2026 - 19/09/2026
                                                    03/10/2026 - 28/11/2026`
const { course, warnings } = parseTimetable(text)
ok(warnings.length === 0, `解析無警告，${course.code} ${course.name} / ${course.groups.length} 組`)
const imp = await sb.rpc('admin_import_course', {
  p_code: course.code, p_name: course.name, p_term: course.term,
  p_duration: course.duration, p_groups: course.groups
})
ok(!imp.error && imp.data > 0, `匯入成功 course #${imp.data}${imp.error ? ' ' + imp.error.message : ''}`)

const { data: check } = await sb.from('v_group_detail').select('group_no, sessions').eq('course_id', imp.data).order('group_no')
ok(check?.length === 2, `新課程讀回 ${check?.length} 組`)
console.log(`   T02 節次日期：${JSON.stringify(check?.[1]?.sessions?.[0]?.date_ranges)}`)
ok(check?.[1]?.sessions?.[0]?.date_ranges?.length === 2, '兩段開課日期合併在同一列節次')

console.log('\n--- 維運 ---')
const rm = await sb.rpc('admin_run_matching')
ok(!rm.error, `admin_run_matching 可執行（新增 ${rm.data} 組）`)
const rq = await sb.rpc('admin_reset_query_code', { p_student_no: 'S2602' })
ok(!rq.error && rq.data === 1, '重設查詢碼成功')

console.log('\n--- 登出後失效 ---')
await sb.auth.signOut()
ok(!!(await sb.rpc('admin_overview')).error, '登出後 admin_overview 再度被擋')

console.log(fail ? `\n${fail} 項失敗` : '\n管理端全部通過')
process.exit(fail ? 1 : 0)
