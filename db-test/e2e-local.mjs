import { createClient } from '@supabase/supabase-js'

const URL = 'http://127.0.0.1:54321'
const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0'
const SERVICE = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU'

const sb = createClient(URL, ANON)
const admin = createClient(URL, SERVICE)
let fail = 0
const ok = (c, m) => { console.log(`${c ? '✓' : '✗'} ${m}`); if (!c) fail++ }

const { data: courses } = await sb.from('courses').select('id, code').eq('code', 'ENVR 8951SCF')
const courseId = courses[0].id
const { data: groups } = await sb.from('v_group_detail').select('group_id, group_no').eq('course_id', courseId)
const G = Object.fromEntries(groups.map(g => [g.group_no, g.group_id]))
ok(Object.keys(G).length === 3, `ENVR 8951SCF 取到 ${Object.keys(G).length} 個組別`)

const submit = (name, no, hold, targets) => sb.rpc('submit_swap', {
  p_name: name, p_student_no: no, p_phone: '9000' + no.slice(-4), p_email: null,
  p_query_code: '2468', p_course_id: courseId, p_hold_group: hold,
  p_targets: targets, p_note: null
})

console.log('\n--- 提交（走 supabase-js RPC）---')
const r1 = await submit('陳大文', 'S2601', G.T03, [G.T02, G.T01])
ok(!r1.error && r1.data > 0, `陳大文 持 T03 想要 T02/T01 → request #${r1.data}${r1.error ? ' ' + r1.error.message : ''}`)
const r2 = await submit('黃小美', 'S2602', G.T02, [G.T03])
ok(!r2.error && r2.data > 0, `黃小美 持 T02 想要 T03 → request #${r2.data}${r2.error ? ' ' + r2.error.message : ''}`)

console.log('\n--- 查詢碼保護 ---')
const bad = await sb.rpc('list_my_requests', { p_student_no: 'S2601', p_name: '陳大文', p_code: '0000' })
ok(bad.error?.message.includes('查詢碼不正確'), `錯誤查詢碼被擋：${bad.error?.message}`)
const denied = await sb.rpc('run_matching')
ok(!!denied.error, `anon 叫不動 run_matching：${denied.error?.message}`)

console.log('\n--- 撮合（模擬 pg_cron，以 service_role 執行）---')
const run = await admin.rpc('run_matching')
ok(!run.error && run.data >= 1, `run_matching 新增 ${run.data} 個候選組`)

console.log('\n--- 查匹配 ---')
const { data: m, error: mErr } = await sb.rpc('query_matches', { p_student_no: 'S2601', p_name: '陳大文', p_code: '2468' })
ok(!mErr && m.length === 1, `陳大文 查到 ${m?.length} 筆匹配${mErr ? ' ' + mErr.message : ''}`)
if (m?.length) {
  const x = m[0]
  console.log(`   ${x.course_name}｜${x.match_size} 人`)
  console.log(`   你   ${x.my_hold}\n     → ${x.my_gets}`)
  console.log(`   對方 ${x.peer_name}（${x.peer_student_no}）${x.peer_phone}`)
  console.log(`        ${x.peer_hold}\n     → ${x.peer_gets}`)
  ok(x.peer_student_no === 'S2602' && x.peer_phone === '90002602', '拿到對方聯絡方式')
  ok(x.my_gets.includes('HKMU/C0G01') && x.my_hold.includes('IOH/F0201'), '兩邊標籤都帶時間與地點')
}

console.log('\n--- 我的意向 ---')
const { data: reqs } = await sb.rpc('list_my_requests', { p_student_no: 'S2601', p_name: '陳大文', p_code: '2468' })
ok(reqs.length === 1 && reqs[0].match_count === 1, `1 筆意向，候選組 ${reqs[0].match_count} 個，志願序 ${reqs[0].targets.map(t => t.group_no).join(' > ')}`)

console.log('\n--- 結束匹配 ---')
const c = await sb.rpc('close_course', { p_course_id: courseId, p_student_no: 'S2601', p_name: '陳大文', p_code: '2468' })
ok(!c.error && c.data === 1, '陳大文 結束此課程匹配')
const after = await sb.rpc('query_matches', { p_student_no: 'S2602', p_name: '黃小美', p_code: '2468' })
ok(after.data.length === 0, '黃小美 那邊的候選組同時失效')

console.log(fail ? `\n${fail} 項失敗` : '\n端到端全部通過')
process.exit(fail ? 1 : 0)
