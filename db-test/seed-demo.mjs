/*
 * 造本地示範資料，涵蓋三種情境：
 *   A 兩人互換成功
 *   B 提交了但配不到
 *   C 配到後按「結束匹配」，之後不再參與撮合
 *
 * 全部走 submit_swap RPC（和前端同一條路徑）；撮合以 service_role 呼叫 run_matching，
 * 等同 pg_cron 每 10 分鐘做的事。可重複執行，開頭會先清空學生資料。
 */
import { createClient } from '@supabase/supabase-js'

const URL = process.env.SUPABASE_URL || 'http://127.0.0.1:54321'
const ANON = process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0'
const SERVICE = process.env.SUPABASE_SERVICE_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU'

const CODE = '1234'                       // 所有示範帳號共用同一組查詢碼，方便手動操作

const sb = createClient(URL, ANON)
const svc = createClient(URL, SERVICE)

let fail = 0
const ok = (c, m) => { console.log(`  ${c ? '✓' : '✗'} ${m}`); if (!c) fail++ }
const die = (msg, e) => { console.error(`✗ ${msg}: ${e?.message || e}`); process.exit(1) }

/* ---------------------------------------------------------------- 課程對照 */

const { data: courses, error: cErr } = await sb.from('courses').select('id, code, name')
if (cErr) die('讀不到課程，本地 Supabase 起來了嗎？', cErr)
const C = Object.fromEntries(courses.map(c => [c.code, c]))

const { data: allGroups } = await sb.from('v_group_detail').select('group_id, group_no, course_id')
const G = {}
for (const g of allGroups) {
  const code = courses.find(c => c.id === g.course_id).code
  ;(G[code] ||= {})[g.group_no] = g.group_id
}

/* ------------------------------------------------------- 清空舊的示範資料 */

const admin = createClient(URL, ANON)
const { error: authErr } = await admin.auth.signInWithPassword({
  email: process.env.ADMIN_EMAIL || 'admin@local.test',
  password: process.env.ADMIN_PASSWORD || 'admin12345'
})
if (authErr) die('管理員登入失敗，先跑 npm run db:setup-local', authErr)
const purge = await admin.rpc('admin_purge_students')
console.log(`清空舊資料：移除 ${purge.data ?? 0} 位學生\n`)

/* ------------------------------------------------------------------ 提交 */

const PEOPLE = []
let phoneSeq = 0

async function submit (name, no, course, hold, wants, note) {
  const phone = '9' + String(10000000 + (++phoneSeq) * 1111).slice(1)
  const { data, error } = await sb.rpc('submit_swap', {
    p_name: name, p_student_no: no, p_phone: phone, p_email: `${no.toLowerCase()}@example.com`,
    p_query_code: CODE,
    p_course_id: C[course].id,
    p_hold_group: G[course][hold],
    p_targets: wants.map(w => G[course][w]),
    p_note: note || null
  })
  if (error) die(`${name} 提交 ${course} 失敗`, error)
  PEOPLE.push({ name, no, course, hold, wants })
  return data
}

console.log('情境 A｜兩人互換 — ENVR 8501SCF')
await submit('陳大文', 'S2601', 'ENVR 8501SCF', 'T01', ['T02', 'T03'], '想改成週六')
await submit('黃小美', 'S2602', 'ENVR 8501SCF', 'T02', ['T01'])
ok(true, '陳大文 持 T01 想要 T02/T03；黃小美 持 T02 想要 T01')

console.log('\n情境 B｜配不到 — ENVR 8951SCF')
await submit('李文彥', 'S2606', 'ENVR 8951SCF', 'T01', ['T02'])
await submit('周雅婷', 'S2607', 'ENVR 8951SCF', 'T02', ['T03'], '週日早上不方便')
await submit('陳大文', 'S2601', 'ENVR 8951SCF', 'T01', ['T03'])
ok(true, '想要的組別沒人放出來（沒有人持有 T03），鏈斷在這裡')

console.log('\n情境 C｜配到後結束匹配 — ENVR 8941SCF')
await submit('蔡明軒', 'S2608', 'ENVR 8941SCF', 'T02', ['T03'])
await submit('許雅雯', 'S2609', 'ENVR 8941SCF', 'T03', ['T02'])
await submit('鄭子豪', 'S2610', 'ENVR 8941SCF', 'T03', ['T02'])
ok(true, '蔡明軒 一人對上兩位可能對家（許雅雯、鄭子豪）')

/* ------------------------------------------------------- 第一輪撮合 */

console.log('\n=== 第一輪撮合（等同 pg_cron）===')
const r1 = await svc.rpc('run_matching')
if (r1.error) die('撮合失敗', r1.error)
console.log(`  新增 ${r1.data} 個候選組`)

const matchesOf = async (no, name) => {
  const { data, error } = await sb.rpc('query_matches', { p_student_no: no, p_name: name, p_code: CODE })
  if (error) die(`${name} 查匹配失敗`, error)
  return data
}

const A1 = await matchesOf('S2601', '陳大文')
ok(A1.filter(m => m.course_name.includes('8501')).length === 1, 'A｜陳大文 在 8501 配到 1 組（兩人互換）')
ok(A1.filter(m => m.course_name.includes('8951')).length === 0, 'B｜陳大文 在 8951 沒有任何匹配')

ok((await matchesOf('S2606', '李文彥')).length === 0, 'B｜李文彥 沒有匹配')
ok((await matchesOf('S2607', '周雅婷')).length === 0, 'B｜周雅婷 沒有匹配')

const C1 = await matchesOf('S2608', '蔡明軒')
ok(C1.length === 2, `C｜蔡明軒 配到 ${C1.length} 個候選組（許雅雯、鄭子豪）`)
ok((await matchesOf('S2609', '許雅雯')).length === 1, 'C｜許雅雯 也看得到這組匹配')
ok((await matchesOf('S2610', '鄭子豪')).length === 1, 'C｜鄭子豪 也看得到這組匹配')

/* --------------------------------------------- 情境 C：按下「結束匹配」 */

console.log('\n=== 蔡明軒 按下「結束匹配」===')
const closed = await sb.rpc('close_course', {
  p_course_id: C['ENVR 8941SCF'].id, p_student_no: 'S2608', p_name: '蔡明軒', p_code: CODE
})
if (closed.error) die('結束匹配失敗', closed.error)
ok(closed.data === 1, '意向已關閉')
ok((await matchesOf('S2608', '蔡明軒')).length === 0, 'C｜蔡明軒 自己看不到匹配了')
ok((await matchesOf('S2609', '許雅雯')).length === 0, 'C｜許雅雯 那邊的候選組連帶作廢')
ok((await matchesOf('S2610', '鄭子豪')).length === 0, 'C｜鄭子豪 那邊也一併作廢')

console.log('\n=== 第二輪撮合：確認結束後不再被配對 ===')
const r2 = await svc.rpc('run_matching')
console.log(`  新增 ${r2.data} 個候選組`)
ok((await matchesOf('S2608', '蔡明軒')).length === 0, 'C｜重跑撮合，蔡明軒 仍然沒有匹配')
ok((await matchesOf('S2609', '許雅雯')).length === 0, 'C｜許雅雯 也配不到了（剩下的兩人同持 T03）')

const reqs = await sb.rpc('list_my_requests', { p_student_no: 'S2608', p_name: '蔡明軒', p_code: CODE })
ok(reqs.data[0].status === 'closed', `C｜蔡明軒 的意向狀態為 ${reqs.data[0].status}`)

// 其他情境不受影響
ok((await matchesOf('S2601', '陳大文')).length === 1, 'A｜陳大文 的匹配不受影響')

/* ---------------------------------------------------------------- 對照表 */

console.log('\n' + '─'.repeat(96))
console.log('示範帳號（查詢碼一律 ' + CODE + '）')
console.log('─'.repeat(96))
const EXPECT = {
  S2601: 'A 8501 配到 黃小美 ／ B 8951 配不到（同一人兩種結果）',
  S2602: 'A 配到 陳大文',
  S2606: 'B 配不到（想要的 T02 持有者想換 T03，鏈沒閉合）',
  S2607: 'B 配不到（沒有人持有 T03）',
  S2608: 'C 已結束匹配，狀態 closed，不再參與撮合',
  S2609: 'C 原本配到 蔡明軒，對方結束後候選組作廢，且配不到新的',
  S2610: 'C 同上'
}
console.log('姓名'.padEnd(8) + '學號'.padEnd(10) + '課程'.padEnd(16) + '持有→想要'.padEnd(20) + '預期')
for (const p of PEOPLE) {
  console.log(
    p.name.padEnd(8) + p.no.padEnd(10) + p.course.replace('ENVR ', '').padEnd(16) +
    `${p.hold} → ${p.wants.join('/')}`.padEnd(20) + (EXPECT[p.no] || '')
  )
}
console.log('─'.repeat(96))
console.log(fail ? `\n${fail} 項不符預期` : '\n全部符合預期')
process.exit(fail ? 1 : 0)
