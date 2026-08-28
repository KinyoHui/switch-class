import { chromium } from 'playwright'

const BASE = 'http://localhost:5188/'
const browser = await chromium.launch({ headless: true, channel: 'chrome' })
const page = await browser.newPage({ viewport: { width: 420, height: 900 } })
const errors = []
page.on('pageerror', e => errors.push(e.message))
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()) })

let fail = 0
const ok = (c, m) => { console.log(`${c ? '✓' : '✗'} ${m}`); if (!c) fail++ }
const has = async (t) => (await page.locator('body').innerText()).includes(t)

await page.goto(BASE, { waitUntil: 'networkidle' })

console.log('--- 提交頁 ---')
ok(await has('換組意向匹配'), 'App 掛載')
ok(!await has('尚未設定 Supabase 連線'), '已讀到 .env')

await page.waitForFunction(() => document.querySelectorAll('select option').length > 1)
const opts = await page.locator('select option').allInnerTexts()
ok(opts.length - 1 === 5, `課程下拉載入 ${opts.length - 1} 門課`)
opts.slice(1).forEach(o => console.log(`   ${o.trim()}`))

await page.locator('input').first().fill('陳大文')
await page.locator('input').nth(1).fill('S2601')
await page.locator('input').nth(2).fill('91234567')
await page.locator('input[type=email]').fill('tai@example.com')
await page.locator('input[maxlength="6"]').fill('2468')

const val8951 = await page.locator('select option', { hasText: '8951SCF' }).getAttribute('value')
await page.selectOption('select', val8951)
await page.waitForSelector('text=我目前的組別')
ok(true, '選課後載入組別卡')

const cards = page.locator('section').first().locator('.card')
ok(await cards.count() === 3, `持有組別區顯示 ${await cards.count()} 張卡`)
const t03 = cards.filter({ hasText: 'T03' })
const t03text = (await t03.innerText()).replace(/\s+/g, ' ')
console.log(`   T03 卡：${t03text}`)
ok(t03text.includes('週日 09:00 - 10:50'), '卡片帶星期與時間')
ok(t03text.includes('IOH / F0201'), '卡片帶校區/房號')
ok(t03text.includes('香港都會大學賽馬會健康護理學院'), '校區展開全稱與地址')
ok(t03text.includes('06/09/2026 - 11/10/2026、25/10/2026 - 29/11/2026'), '兩段開課日期合併成一行')

await t03.click()
await page.waitForSelector('text=我可接受的組別')
ok(true, '選定持有組別後出現目標區')
const targets = page.locator('section').nth(1).locator('.card')
ok(await targets.count() === 2, `可接受區排除已持有組別，剩 ${await targets.count()} 張`)

const t01 = targets.filter({ hasText: 'T01' })
const t01text = (await t01.innerText()).replace(/\s+/g, ' ')
console.log(`   T01 卡：${t01text}`)
ok(t01text.includes('改動：週日 → 週四'), '標出與現有組別的星期差異')
ok(t01text.includes('改動：IOH → JCC'), '標出校區差異')

await page.click('text=除目前組別外全選')
ok((await page.locator('text=第 1 志願').count()) === 1 && (await page.locator('text=第 2 志願').count()) === 1,
   '一鍵全選並自動編志願序')

const firstOrder = await targets.first().innerText()
await targets.nth(1).locator('button[title="提高志願序"]').click()
ok((await targets.first().innerText()) !== firstOrder || (await targets.nth(1).innerText()).includes('第 1 志願') === false,
   '▲ 可調整志願序')
console.log(`   調整後：${(await page.locator('section').nth(1).innerText()).match(/T0\d[\s\S]*?第 \d 志願/g)?.join(' / ') || ''}`)

console.log('\n--- 提交 ---')
await page.fill('textarea', '本地部署測試')
await page.locator('button.btn-primary', { hasText: /^提交$/ }).click()
await page.waitForTimeout(2500)
const notice = await page.locator('.fixed').innerText().catch(() => '(沒有提示框)')
console.log('   提示框：' + notice.replace(/\s+/g, ' '))
ok(notice.includes('已送出'), '提交成功，顯示送出提示')

console.log('\n--- 查詢頁 ---')
await page.click('nav button:has-text("我的匹配")')
await page.click('button:has-text("查詢我的意向與匹配")')
await page.waitForSelector('text=我的意向')
const q = (await page.locator('body').innerText()).replace(/\s+/g, ' ')
ok(q.includes('ENVR 8951SCF'), '列出我的意向')
ok(q.includes('第 1 志願') && q.includes('第 2 志願'), '志願序帶回顯示')
ok(q.includes('目前') && q.includes('IOH/F0201'), '意向顯示持有組別含時間地點')
console.log(`   ${q.match(/目前 T0\d（[^）]*）/)?.[0]}`)

console.log('\n--- 管理頁 ---')
await page.click('nav button:has-text("管理")')
await page.waitForSelector('text=管理員登入')
await page.fill('input[type=email]', 'admin@local.test')
await page.fill('input[type=password]', 'admin12345')
await page.click('button:has-text("登入")')
await page.waitForSelector('text=課程總覽', { timeout: 15000 })
ok(true, '管理員登入成功')
const rows = await page.locator('table tbody tr').count()
ok(rows === 5, `總覽表 ${rows} 列`)
console.log('   ' + (await page.locator('table').innerText()).replace(/\n/g, ' | '))

await page.click('text=填入範例')
await page.click('button:has-text("解析")')
await page.waitForSelector('text=解析結果')
const draft = await page.locator('textarea').nth(1).inputValue()
ok(draft.includes('"group_no": "T03"') && draft.includes('"weekday": 0'), '課表解析結果可預覽並編輯')

console.log('\n--- 手動撮合 → 回查詢頁看結果 ---')
await page.click('button:has-text("手動執行一輪撮合")')
await page.waitForSelector('text=撮合完成', { timeout: 15000 })
const runMsg = await page.locator('.fixed').innerText()
ok(runMsg.includes('撮合完成'), runMsg.replace(/\s+/g, ' ').replace(' ✕', ''))

await page.click('nav button:has-text("我的匹配")')
await page.click('button:has-text("查詢我的意向與匹配")')
await page.waitForSelector('text=兩人互換', { timeout: 15000 })
const matchCard = (await page.locator('.card', { hasText: '兩人互換' }).innerText()).replace(/\s+/g, ' ')
console.log('   ' + matchCard)
ok(matchCard.includes('黃小美'), '匹配卡顯示對方姓名')
ok(matchCard.includes('90002602'), '匹配卡顯示對方聯絡方式')
ok(matchCard.includes('IOH/F0201') && matchCard.includes('HKMU/C0G01'), '流向兩端都帶時間地點')

await page.screenshot({ path: '/tmp/switch-class-admin.png', fullPage: true })
await page.click('nav button:has-text("提交意向")')
await page.waitForTimeout(500)
await page.screenshot({ path: '/tmp/switch-class-submit.png', fullPage: true })

ok(errors.length === 0, errors.length ? `主控台錯誤：${errors.slice(0, 2).join(' | ')}` : '無 JS 執行錯誤')
console.log(fail ? `\n${fail} 項失敗` : '\n瀏覽器端全部通過')
await browser.close()
process.exit(fail ? 1 : 0)
