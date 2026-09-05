import { chromium } from 'playwright'
const BASE = process.env.APP_URL || 'http://localhost:5173/'
const browser = await chromium.launch({ headless: true, channel: 'chrome' })
let fail = 0
const ok = (c, m) => { console.log(`  ${c ? '✓' : '✗'} ${m}`); if (!c) fail++ }

async function openQuery(no, name) {
  const page = await browser.newPage({ viewport: { width: 430, height: 1000 } })
  await page.goto(BASE, { waitUntil: 'networkidle' })
  await page.click('nav button:has-text("我的匹配")')
  await page.locator('input').first().fill(name)
  await page.locator('input').nth(1).fill(no)
  await page.locator('input[maxlength="6"]').fill('1234')
  await page.click('button:has-text("查詢我的意向與匹配")')
  await page.waitForSelector('text=匹配結果', { timeout: 15000 })
  const t = (await page.locator('body').innerText()).replace(/[ \t]+/g, ' ')
  return { page, t }
}

console.log('A｜陳大文 S2601 — 一筆配到、一筆配不到')
{
  const { page, t } = await openQuery('S2601', '陳大文')
  ok(t.includes('兩人互換') && t.includes('黃小美'), '8501 顯示兩人互換卡，含對方姓名')
  ok((t.match(/ENVR 8501SCF/g) || []).length >= 2, '意向區與匹配區都出現 8501')
  ok(t.includes('尚未配對到，下一輪撮合會再試'), '8951 那筆標示尚未配對到')
  await page.screenshot({ path: '/tmp/demo-A.png', fullPage: true }); await page.close()
}

console.log('B｜李文彥 S2606 — 配不到')
{
  const { page, t } = await openQuery('S2606', '李文彥')
  ok(t.includes('進行中'), '意向仍為進行中')
  ok(t.includes('尚未配對到，下一輪撮合會再試'), '意向卡標示尚未配對到')
  ok(t.includes('目前還沒有配對成功的組合'), '匹配結果區顯示空狀態文案')
  await page.screenshot({ path: '/tmp/demo-B.png', fullPage: true }); await page.close()
}

console.log('C｜蔡明軒 S2608 — 已結束匹配')
{
  const { page, t } = await openQuery('S2608', '蔡明軒')
  ok(t.includes('已結束'), '意向狀態顯示「已結束」')
  const btns = await page.locator('button').allInnerTexts()
  ok(!btns.some(b => ['修改', '撤銷', '結束匹配'].includes(b.trim())),
     `已結束的意向不再提供修改／撤銷／結束按鈕（頁面按鈕：${btns.map(b => b.trim()).join('、')}）`)
  ok(t.includes('沒有進行中的意向'), '匹配結果區顯示「沒有進行中的意向」')
  await page.screenshot({ path: '/tmp/demo-C.png', fullPage: true }); await page.close()
}

console.log('C｜許雅雯 S2609 — 對家結束後，候選組消失')
{
  const { page, t } = await openQuery('S2609', '許雅雯')
  ok(t.includes('進行中'), '自己的意向還在，狀態進行中')
  ok(t.includes('尚未配對到'), '原本的匹配已作廢，回到未配對狀態')
  await page.close()
}

console.log(fail ? `\n${fail} 項不符` : '\n畫面全部符合預期')
await browser.close()
process.exit(fail ? 1 : 0)
