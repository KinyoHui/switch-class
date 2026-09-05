import { boot } from './setup.mjs'
const db = await boot()
process.on("unhandledRejection", e => { console.error("\n未捕捉錯誤：" + e.message); process.exit(1) })
const q = async (s, p) => (await db.query(s, p)).rows
let fail = 0
const ok = (c, m) => { console.log(`${c ? '✓' : '✗'} ${m}`); if (!c) fail++ }
const err = async (fn, m) => { try { await fn(); ok(false, `${m}（應該報錯卻沒有）`) } catch (e) { ok(true, `${m} → ${e.message}`) } }

const [{ id: course }] = await q(`select id from courses where code='ENVR 8951SCF'`)
const G = Object.fromEntries((await q(`select group_no,id from course_groups where course_id=$1`, [course])).map(r => [r.group_no, r.id]))

console.log('\n--- 顯示標籤 ---')
const [{ l }] = await q(`select group_time_label($1) l`, [G.T03])
ok(/FT 面授課 週日 09:00-10:50 · IOH\/F0201/.test(l), `T03 標籤：${l}`)
const [{ sessions }] = await q(`select sessions from v_group_detail where group_id=$1`, [G.T03])
ok(sessions.length === 1, `T03 兩段日期已合併為 ${sessions.length} 列節次`)
ok(sessions[0].date_ranges.length === 2, `每列帶 ${sessions[0].date_ranges.length} 段開課日期`)
ok((await q(`select count(*)::int c from courses`))[0].c === 4, '四門 ENVR 課程都已錄入')
ok((await q(`select count(*)::int c from course_groups`))[0].c === 12, '共 12 個組別')

console.log('\n--- 提交 ---')
const sub = (name, no, hold, targets) =>
  q(`select submit_swap($1,$2,'91230000',null,'1234',$3,$4,$5,null) id`, [name, no, course, hold, targets])
const [{ id: rA }] = await sub('陳小明', 's001', G.T03, [G.T01, G.T02])
const [{ id: rB }] = await sub('李大文', 's002', G.T01, [G.T03])
ok(rA && rB, `建立兩筆意向 #${rA} #${rB}`)

await err(() => sub('陳小明', 's001', G.T03, [G.T03]), '目標＝持有組別被擋下')
await err(() => sub('陳小明', 's001', G.T03, []), '未選目標被擋下')
await err(() => sub('陳小明', 's001', G.T03, [G.T01]).then(() => sub('冒名者', 's001', G.T01, [G.T02])), '姓名不符被擋下')
await err(() => q(`select submit_swap('陳小明','s001',null,null,'99',$1,$2,$3,null)`, [course, G.T03, [G.T01]]), '查詢碼格式被擋下')
await err(() => q(`select submit_swap('王五','s009',null,null,'1234',$1,$2,$3,null)`, [course, G.T03, [G.T01]])
  .then(() => q(`select list_my_requests('s009','王五','9999')`)), '查詢碼錯誤被擋下')

// submit_swap 會把學號正規化為大寫，直查資料表時要用 'S001'
const [{ c }] = await q(`select count(*)::int c from swap_requests where student_id=(select id from students where student_no='S001')`)
ok(c === 1, `同一學生同一門課只有 ${c} 筆意向（重複提交＝修改）`)

console.log('\n--- 兩人互換 ---')
await sub('陳小明', 's001', G.T03, [G.T01, G.T02])
ok((await q(`select run_matching() n`))[0].n >= 1, '撮合產生新候選組')
let m = await q(`select * from query_matches('s001','陳小明','1234')`)
ok(m.length === 1, `A 查到 ${m.length} 筆匹配`)
ok(m[0].peer_student_no === 'S002' && m[0].peer_phone === '91230000', '匹配後可見對方聯絡方式')
ok(/^T03（/.test(m[0].my_hold) && /^T01（/.test(m[0].my_gets), `流向：${m[0].my_hold} → ${m[0].my_gets}`)
ok(m[0].my_gets.includes('週四 19:00-20:50'), '換到的組別標籤帶時間地點')

const before = (await q(`select count(*)::int c from match_groups`))[0].c
await q(`select run_matching()`)
ok((await q(`select count(*)::int c from match_groups`))[0].c === before, `重跑撮合不重複寫入（維持 ${before} 組）`)

console.log('\n--- 結束匹配 / 撤銷 ---')
await q(`select close_course($1,'s001','陳小明','1234')`, [course])
await q(`select close_course($1,'s002','李大文','1234')`, [course])
await q(`select close_course($1,'s009','王五','1234')`, [course])  // 前面格式測試留下的意向
// 建立新的一對來測試結束匹配功能
await sub('甲', 'c001', G.T01, [G.T02])
await sub('乙', 'c002', G.T02, [G.T01])
await q(`select run_matching()`)
ok((await q(`select * from query_matches('c001','甲','1234')`)).length === 1, '甲乙配對成功')
await q(`select close_course($1,'c001','甲','1234')`, [course])
ok((await q(`select * from query_matches('c002','乙','1234')`)).length === 0, '成員結束後，候選組對其他人也失效')
ok((await q(`select status from match_groups where size=2 and signature like 'p:%' order by id desc limit 1`))[0].status === 'expired', '候選組標記 expired')
const my = await q(`select * from list_my_requests('c002','乙','1234')`)
ok(my.length === 1 && my[0].targets.length === 1 && my[0].hold_label.includes('週日 09:00-10:50'), `我的意向：${my[0].hold_label}`)
await q(`select cancel_request($1,'c002','乙','1234')`, [my[0].request_id])
ok((await q(`select status from swap_requests where id=$1`, [my[0].request_id]))[0].status === 'cancelled', '撤銷成功')

console.log('\n--- 衝堂檢查 ---')
// 丁 已持有 8941 T02（週日 13:00-14:50），再看 8951 的各組會不會撞
const c41 = (await q(`select id from courses where code='ENVR 8941SCF'`))[0].id
const G41 = Object.fromEntries((await q(`select group_no,id from course_groups where course_id=$1`, [c41])).map(r => [r.group_no, r.id]))
await q(`select submit_swap('丁','d001',null,null,'1234',$1,$2,$3,null)`, [c41, G41.T02, [G41.T01]])
ok((await q(`select * from check_conflicts('d001','丁','1234',$1)`, [G.T02])).length === 0,
   '8951 T02（週日 09:00）與丁持有的 8941 T02（週日 13:00）不衝堂')
// 造一門真的會撞的課，確認函式抓得到
await q(`select import_course_internal('TEST 0001','衝堂測試課','2026-秋',null,$1::jsonb)`, [JSON.stringify([
  { group_no: 'T01', sessions: [{ seq: 1, kind: 'FT 面授課', weekday: 0, start_time: '09:30', end_time: '11:00', campus_code: 'JCC', room: 'A101', start_date: '2026-09-06', end_date: '2026-11-29' }] },
  { group_no: 'T02', sessions: [{ seq: 1, kind: 'FT 面授課', weekday: 5, start_time: '09:30', end_time: '11:00', campus_code: 'JCC', room: 'A101', start_date: '2026-09-04', end_date: '2026-11-27' }] }
])])
const cT = (await q(`select id from courses where code='TEST 0001'`))[0].id
const GT = Object.fromEntries((await q(`select group_no,id from course_groups where course_id=$1`, [cT])).map(r => [r.group_no, r.id]))
await q(`select submit_swap('戊','e001',null,null,'1234',$1,$2,$3,null)`, [cT, GT.T01, [GT.T02]])
const conf = await q(`select * from check_conflicts('e001','戊','1234',$1)`, [G.T02])
ok(conf.length === 1 && conf[0].course_code === 'TEST 0001',
   `抓到衝堂：${conf[0]?.course_code} ${conf[0]?.group_no}（${conf[0]?.detail}）`)


console.log('\n=========== 課程組隊 ===========')
{
  // 只用 4 門 ENVR 課；前面衝堂測試建的 TEST 0001 不算在內
  const courses = await q(`select id, code from courses where code like 'ENVR%' order by code`)
  const G = {}
  for (const c of courses) {
    G[c.code] = Object.fromEntries(
      (await q(`select group_no, id from course_groups where course_id=$1`, [c.id])).map(r => [r.group_no, r.id]))
  }
  const codes = courses.map(c => c.code)
  console.log('\n課程：', codes.join(', '))

  // 組合 X：四門課都選 T01；組合 Y：都選 T02
  const X = codes.map(c => G[c].T01)
  const Y = codes.map(c => G[c].T02)
  const Z = [G[codes[0]].T01, G[codes[1]].T01, G[codes[2]].T01, G[codes[3]].T02]  // 只差一門

  const sub = (name, no, groups) =>
    q(`select submit_team($1,$2,$3,$4,'1234',$5,null) id`, [name, no, '9' + no.slice(-7), `${no}@x.com`, groups])

  console.log('\n--- 輸入驗證 ---')
  await err(() => sub('少一門', 'e01', X.slice(0, 3)), '只填 3 門被擋下')
  await err(() => sub('多一門', 'e02', [...X, G[codes[0]].T02]), '填 5 門被擋下')
  await err(() => sub('同課兩組', 'e03', [G[codes[0]].T01, G[codes[0]].T02, G[codes[1]].T01, G[codes[2]].T01]),
    '同一門課選兩個組別被擋下')
  await err(() => sub('不存在', 'e04', [999999, ...X.slice(1)]), '不存在的組別被擋下')
  await err(() => q(`select submit_team('碼太短','e05',null,null,'99',$1,null)`, [X]), '查詢碼格式被擋下')

  console.log('\n--- 簽章正規化 ---')
  await sub('甲', 'a01', X)
  await sub('乙', 'a02', [...X].reverse())          // 同樣 4 門，順序相反
  const sigs = await q(`select distinct signature from team_requests`)
  ok(sigs.length === 1, `選課順序不影響簽章（共 ${sigs.length} 種簽章）`)

  console.log('\n--- 6 人一隊，第 7 人開新隊 ---')
  for (let i = 3; i <= 8; i++) await sub(`X${i}`, `a0${i}`, X)   // 共 8 人選組合 X
  await sub('異組合', 'b01', Y)
  await sub('差一門', 'c01', Z)
  const n = await q(`select run_teaming() n`)
  console.log(`  run_teaming 新建 ${n[0].n} 支隊伍`)

  const teamsX = await q(`select t.id, t.seq, (select count(*)::int from team_members m where m.team_id=t.id) c
                          from teams t where t.signature=(select signature from team_requests where id=1) order by t.seq`)
  ok(teamsX.length === 2, `組合 X 的 8 人分成 ${teamsX.length} 支隊伍`)
  ok(teamsX[0].c === 6, `第 1 隊滿編 ${teamsX[0].c} 人`)
  ok(teamsX[1].c === 2, `第 2 隊 ${teamsX[1].c} 人`)

  const solo = await q(`select * from my_team('b01','異組合','1234')`)
  ok(solo[0].team_id === null, '只有一人的組合不開隊')
  ok(Number(solo[0].waiting_same_combo) === 1, `顯示等待中人數 ${solo[0].waiting_same_combo}`)
  const zsolo = await q(`select * from my_team('c01','差一門','1234')`)
  ok(zsolo[0].team_id === null, '只差一門課就不同組合，不會被編進 X 隊')

  console.log('\n--- 隊員資訊可見 ---')
  const mine = await q(`select * from my_team('a01','甲','1234')`)
  ok(mine[0].members.length === 6, `甲 看到 ${mine[0].members.length} 位隊員（含自己）`)
  ok(mine[0].members.filter(m => m.is_me).length === 1, '自己那筆標記 is_me')
  const peer = mine[0].members.find(m => !m.is_me)
  ok(peer.phone && peer.email && peer.student_no, `隊友聯絡方式可見：${peer.name} ${peer.phone} ${peer.email}`)
  ok(mine[0].courses.length === 4, `帶出 ${mine[0].courses.length} 門課的組別標籤`)
  ok(/T01（.*週.*）/.test(mine[0].courses[0].label), `課程標籤含時間：${mine[0].courses[0].label}`)
  ok(mine[0].team_size === 6 && mine[0].team_seq === 1, `隊伍 #${mine[0].team_seq}，上限 ${mine[0].team_size}`)

  console.log('\n--- 離隊騰出名額 ---')
  await q(`select leave_team('a01','甲','1234')`)
  const sigX = (await q(`select signature from team_requests where id=2`))[0].signature
  const cnt = async (seq) => (await q(
    `select (select count(*)::int from team_members m where m.team_id=t.id) c
     from teams t where t.seq=$1 and t.status='open' and t.signature=$2`, [seq, sigX]))[0].c
  ok(await cnt(1) === 5, `甲 離隊後第 1 隊剩 ${await cnt(1)} 人（不搬動第 2 隊既有隊員）`)
  ok(await cnt(2) === 2, `第 2 隊維持 ${await cnt(2)} 人，隊友不會被靜默調動`)
  await sub('遞補', 'a09', X)
  await q(`select run_teaming()`)
  ok(await cnt(1) === 6, `新人優先填補第 1 隊的空缺，補回 ${await cnt(1)} 人`)
  ok(await cnt(2) === 2, '第 2 隊不受影響')
  const gone = await q(`select * from my_team('a01','甲','1234')`)
  ok(gone.length === 0, '甲 的意向已撤銷，查不到')

  console.log('\n--- 改選課程組合會離開原隊 ---')
  await sub('乙', 'a02', Y)                      // 乙 從 X 改到 Y
  const yi = await q(`select * from my_team('a02','乙','1234')`)
  ok(yi[0].team_id === null, '乙 改組合後立刻脫離原隊，等待重新編隊')
  await q(`select run_teaming()`)
  const yi2 = await q(`select * from my_team('a02','乙','1234')`)
  ok(yi2[0].team_id !== null && yi2[0].members.length === 2, `乙 與 異組合 編成新隊（${yi2[0].members.length} 人）`)

  console.log('\n--- 冪等 ---')
  const before = (await q(`select count(*)::int c from teams`))[0].c
  await q(`select run_teaming()`); await q(`select run_teaming()`)
  ok((await q(`select count(*)::int c from teams`))[0].c === before, `重跑 run_teaming 不重複建隊（維持 ${before} 支）`)

  console.log('\n--- 組隊 RLS ---')
  await db.exec(`set role anon`)
  await err(() => q(`select * from team_requests`), 'anon 讀不到 team_requests')
  await err(() => q(`select * from teams`), 'anon 讀不到 teams')
  await err(() => q(`select * from team_members`), 'anon 讀不到 team_members')
  await err(() => q(`select run_teaming()`), 'anon 不能執行 run_teaming')
  await err(() => q(`select admin_team_overview()`), 'anon 不能看管理總覽')
  ok((await q(`select submit_team('新人','z99',null,null,'1234',$1,null) id`, [Y]))[0].id > 0, 'anon 可以透過 RPC 提交')
}

console.log('\n--- RLS ---')
await db.exec(`set role anon`)
await err(() => q(`select * from students`), 'anon 讀不到 students')
await err(() => q(`select * from swap_requests`), 'anon 讀不到 swap_requests')
await err(() => q(`select run_matching()`), 'anon 不能執行 run_matching')
await err(() => q(`select admin_overview()`), 'anon 不能執行 admin_overview')
ok((await q(`select * from v_group_detail`)).length > 0, 'anon 讀得到公開課程組別')
ok((await q(`select * from campuses`)).length === 8, 'anon 讀得到校區表')
await db.exec(`reset role`)

console.log(fail ? `\n${fail} 項失敗` : '\n全部通過')
process.exit(fail ? 1 : 0)
