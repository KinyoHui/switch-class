# 換組意向匹配系統

同一門課程在不同組別（T01 / T02 / T03…）之間互換的意向登記與自動撮合，
外加依完整課表尋找課程組合相同的同學組隊。
實作依據 [`course-swap-design.md`](./course-swap-design.md)。

Vue 3 + Vite + Tailwind v4 + PWA，後端全部落在 Supabase（Postgres + RLS + RPC + pg_cron），無自建伺服器。

---

## 快速開始

```bash
npm install
cp .env.example .env      # 填入 Supabase URL 與 anon key
npm run dev
```

| 指令 | 用途 |
|---|---|
| `npm run dev` | 開發伺服器 |
| `npm run build` | 產出 `dist/`，靜態託管即可 |
| `npm run test:db` | 用 PGlite 在本機跑一遍 migrations 與撮合情境，不需要 Docker 也不需要連線 |

---

## 本地完整部署（Docker）

`supabase start` 會在 Docker 裡跑起 Postgres + PostgREST + GoTrue，和線上環境同構，
並自動套用 `supabase/migrations/` 的全部內容。

```bash
npm run db:start          # 首次會拉映像，約需數分鐘
npm run db:setup-local    # 啟用 pg_cron 排程 + 建立管理員帳號
npm run dev
```

`db:start` 結束時會印出 `API_URL` 與 `ANON_KEY`，填進 `.env`：

```
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_KEY=<印出來的 ANON_KEY>
```

管理頁預設帳號 `admin@local.test` / `admin12345`（可用 `ADMIN_EMAIL`、`ADMIN_PASSWORD` 環境變數覆寫）。

| 指令 | 用途 |
|---|---|
| `npm run db:reset` | 重建資料庫並重跑所有 migration；跑完要再執行一次 `db:setup-local` |
| `npm run db:stop` | 停掉本地 Supabase |
| `npm run test:local` | 對本地 Supabase 跑學生端與管理端的端到端測試（走 supabase-js） |
| `npm run test:ui` | 用 Playwright 驅動系統 Chrome，實際點過三個頁面 |
| `npm run seed:demo` | 灌入四種情境的示範資料（會先清空既有學生），並逐項驗證 |
| `npm run verify:demo` | 用瀏覽器確認四種情境在查詢頁上真的長對樣子 |

`test:ui` 需要先 `npm run build && npm run preview`（預設 port 5188），並依賴系統已安裝的 Chrome。
三個測試有前後相依：`test:local` 會建立測試學生與一門測試課程，`test:ui` 接著用它們驗證匹配往返。

### 示範資料

`npm run seed:demo` 會造出三種情境，查詢碼一律 `1234`：

| 情境 | 課程 | 帳號 | 預期 |
|---|---|---|---|
| A 兩人互換成功 | ENVR 8501SCF | 陳大文 S2601（T01→T02/T03）、黃小美 S2602（T02→T01） | 雙方各看到一張「兩人互換」卡，含對方聯絡方式 |
| B 提交了配不到 | ENVR 8951SCF | 李文彥 S2606、周雅婷 S2607、陳大文 S2601 | 意向顯示「尚未配對到，下一輪撮合會再試」，匹配結果區為空 |
| C 結束匹配後不再撮合 | ENVR 8941SCF | 蔡明軒 S2608（已按結束）、許雅雯 S2609、鄭子豪 S2610 | 蔡明軒 狀態 `已結束`、無操作按鈕；兩位對家的候選組連帶作廢且重跑撮合也配不到 |

陳大文 S2601 同時橫跨 A 與 B：8501 那筆配到了，8951 那筆沒有——用來確認狀態是按課程各自獨立的。

---

## 課程資料

`0007_seed.sql` 是 2026 秋季學期的實際課表，四門 ENVR 課各 T01/T02/T03，共 12 個組別：

| 課程 | T01 | T02 | T03 |
|---|---|---|---|
| ENVR 8501SCF 生態保護與修復 | 週一 19:00-20:50 JCC/E0313 | 週六 13:00-14:50 HKMU/C0G01 | 週六 16:00-17:50 HKMU/C0G01 |
| ENVR 8931SCF 當代中國的環境政策與戰略 | 週二 19:00-20:50 JCC/E0313 | 週六 09:00-10:50 HKMU/C0G01 | 週六 19:00-20:50 HKMU/C0G01 |
| ENVR 8941SCF 中國環境保護的管理與實踐 | 週三 19:00-20:50 JCC/E0313 | 週日 13:00-14:50 HKMU/C0G01 | 週日 16:00-17:50 HKMU/C0G01 |
| ENVR 8951SCF 中國特色的可持續發展 | 週四 19:00-20:50 JCC/E0313 | 週日 09:00-10:50 HKMU/C0G01 | 週日 09:00-10:50 IOH/F0201 |

全部為 FT 面授課。要換學期或改課表，用管理頁的批次匯入覆蓋即可，不必動 migration。

---

## 課程組隊

換組匹配之外的第二個功能，走 `課程組隊` 分頁。

學生填滿自己的 **4 門課**（每門課選所在組別），4 門**完全相同**的同學編成一隊，
**一隊 6 人，滿了自動開新隊**。同隊成員彼此看得到姓名、學號、手機與 Email。

**配對鍵是「4 個 `group_id` 的集合」。** 這一點值得說明：需求要的是課程編號、組別、
上課地點、上課時間四項全部一致，而 `course_groups` 一列已唯一決定課程編號與組別代號，
它的 `group_sessions` 決定時間與地點——所以 group_id 集合相同，四項就必然全部一致，
不需要再逐項比對。實作上把 4 個 id 排序後串成 `g:12-45-67-89` 當 signature，
選課順序不影響結果。

幾個設計決定：

- **隊伍是黏著的，不像換組匹配那樣每輪重算。** 編進去就固定，`run_teaming()`
  只處理還沒編隊的人。有人離隊時空位留給下一個新人，不會把後面隊伍的人搬上來——
  否則同學每 10 分鐘打開頁面看到的隊友都在變。
- **同組合只有一人時不開隊**，前端顯示「還沒有其他同學的 4 門課與你完全相同」，
  並告知目前有幾人在等同一個組合。
- **改選課程組合會立刻脫離原隊**，下一輪重新編隊——組合變了就不再屬於原本那群人。
- 一位學生同時只有一筆有效組隊意向（`uq_open_team_request`），重複提交即為修改。

相關物件都在 `supabase/migrations/0008_teaming.sql`：
`team_requests` / `team_request_groups` / `teams` / `team_members` 四張表，
RPC 是 `submit_team` / `my_team` / `leave_team`，編隊由 `run_teaming()` 執行，
pg_cron 排程 `team-matching` 每 10 分鐘跑一次。

---

## 與設計文件的差異

實作時對文件中「待確認」的項目做了選擇，全部可回退：

- **查詢碼（第十節第 4 點）已實作，且為必填。** 只靠學號＋姓名保護個資太弱——同學之間往往兩者都知道。提交時自設 4~6 位英數字，以 `pgcrypto` 的 `crypt()` 存 hash；查詢、修改、撤銷都要驗。忘記時由管理員在管理頁重設。
- **三人環換（第 2 點）已移除，只做兩人互換。** 曾經實作過，但三次方的候選組膨脹讓它在實際人數下不可用（見下方規模一節），且環越長越難促成——三個人裡有一個反悔，整環就散了。`match_groups.size` 保留欄位，要加回來時 schema 不用動。
- **跨課程互換（第 1 點）未實作**，維持同課程換組。要放寬時改 `match_pairs()` 的 `b.course_id = a.course_id` 條件即可，表結構不用動。
- **志願序用 ▲▼ 按鈕而非拖曳。** 原生 HTML5 拖放在手機上不能用，而這個站的主要流量就是手機。排序結果一樣寫進 `swap_targets.priority`。
- **課表匯入只做文字解析，沒有接 OCR。** `src/lib/parseTimetable.js` 認得文件第一節那種課表格式；解析結果會以 JSON 呈現給管理員核對、可直接修改後再匯入，不是解析完就寫庫。

### 對文件 SQL 的兩處修正

- **`submit_swap` 修改意向時，舊候選組要「刪除」而不是標記 `expired`。** `match_groups.signature` 有 unique 約束，若只標記過期，下一輪撮合出同一組合會被 unique 擋下，該學生就再也配不到那個人了。
- **公開課程表需要顯式 `grant select` 給 `anon`。** Supabase 專案的預設權限剛好會給，但不該依賴這個預設；`npm run test:db` 在乾淨的 Postgres 上就抓到了這個洞。
- **用到 `crypt()` 的函式，`search_path` 必須同時掛 `public` 與 `extensions`。** Supabase 把 pgcrypto 裝在 `extensions` schema，而 `SECURITY DEFINER` 函式鎖死 `search_path = public` 會導致 `crypt()` 找不到——這個只有在真的部署到 Supabase 上才會炸，PGlite 測不出來。

---

## 專案結構

```
supabase/migrations/   資料庫全部內容，依序執行即可（0008 是課程組隊）
db-test/               PGlite 驗證腳本（npm run test:db）
src/
  lib/supabase.js      Supabase client
  lib/api.js           RPC 封裝，前端只透過這層碰後端
  lib/format.js        時間地點顯示、目標組別與現有組別的差異
  lib/parseTimetable.js  課表文字 → 匯入結構
  composables/useIdentity.js  姓名／學號／查詢碼，跨頁共用並存 localStorage
  components/GroupCard.vue    組別卡：提交頁兩區與匹配結果共用同一種呈現
  views/SubmitView.vue        提交意向
  views/QueryView.vue         我的意向 + 匹配結果
  views/AdminView.vue         登入 / 總覽 / 課表匯入 / 維運
```

---

## 自架部署（Docker Compose）

`deploy/` 底下是一套自架的部署設定，不依賴 Supabase 雲端。四個服務：

| 服務 | 映像 | 角色 |
|---|---|---|
| `web` | nginx:stable-alpine | 靜態前端 + `/rest/v1`、`/auth/v1` 反向代理 |
| `rest` | supabase/postgrest | PostgREST |
| `auth` | supabase/gotrue | 管理頁登入 |
| `db` | supabase/postgres | 內含 pg_cron、pgcrypto、`anon`/`authenticated` 角色與 `auth` schema |

**刻意不用 Kong**——nginx 同時擔任靜態伺服器與 API 閘道，在小機器上省下約 200MB 記憶體與一整份 Kong 設定。

```bash
# 伺服器上
cd /docker/compose/switch-class
./deploy.sh http://<你的位址>            # 產金鑰 → 建置 → 起服務 → 套 migration
./scripts/setup-admin.sh <email> <密碼>  # 建立管理員帳號
```

`deploy.sh` 可重複執行：`.env` 已存在就不覆蓋，migration 全部冪等。

### 幾個踩過的坑

- **大陸機房連不上 Docker Hub**，但 `public.ecr.aws` 可達，Supabase 全套映像都在那；nginx 與 node 也用
  `public.ecr.aws/nginx/nginx`、`public.ecr.aws/docker/library/node`。Docker CE 本身則走清華鏡像安裝。
- **npm 官方 registry 慢到會逾時**（實測 >20s），Dockerfile 建置階段預設用 `registry.npmmirror.com`（4s）。
- **`supabase/postgres` 映像裡 `postgres` 不是 superuser。** `authenticator` 與 `supabase_auth_admin`
  是保留角色，要用 `supabase_admin` 才改得動密碼；而 migration 必須以 `postgres` 執行，
  表與函式的擁有者是它，`SECURITY DEFINER` 繞過 RLS 才成立。這兩件事分開處理，見
  `scripts/apply-migrations.sh`。
- **該映像不會自動用 `POSTGRES_PASSWORD` 設服務角色密碼**，得自己 `alter role`，否則 PostgREST 與
  GoTrue 會一直 restart。

實測資源占用：四個容器合計約 585MB，在 2 核 1.9G 的機器上還剩 1.4G。

---

## 撮合的規模上限（實測）

`run_matching()` 每輪是**全表重算**，不是增量：把所有 `status='open'` 的意向重新推導一次兩人互換，
靠 `match_groups.signature` 的 unique 做冪等去重。掃描範圍被 `b.course_id = a.course_id` 限制在同一門課內，
所以成本是「每門課各自 O(n²)」，不是全域笛卡兒積。

移除三人環換前，同一組資料的實測（4 門課、每課 3 個組別、隨機持有與意願）：

| 每課人數 | open 意向總數 | 候選組（含三人環） | 耗時 |
|---|---|---|---|
| 50 | 200 | 13,204 | 0.6 秒 |
| 150 | 600 | 339,721 | 18 秒 |
| 400 | 1,600 | 7,006,175 | 5 分 25 秒 |

膨脹幾乎全來自三人環：組別只有 3 個而人數上百時，任意三人都能構成合法環，
單一學生的 `query_matches` 會回上百列，人根本挑不動。**現在只做兩人互換，這個問題不存在了**——
候選組數量與「實際互補的配對數」同階，每課數百人也是秒級。

## 組隊的規模

`run_teaming()` 是 O(n) 的：按 signature 分群後依序填隊，沒有兩兩比對。
signature 是 4 個 `group_id` 排序後的字串，用 B-tree 索引直接分群，人數再多都是線性。

---

## 需要知道的幾件事

- **撮合是候選，不是成交。** 系統不鎖定任何人，同一筆意向可同時出現在多個候選組。雙方自行到 MyHKMU 辦理，完成後回來按「結束匹配」。
- **撮合與編隊各每 10 分鐘批次執行**，不是先到先得——這點寫在頁尾，可以省掉爭議。
- **衝堂提示只涵蓋學生在本站登記過的課程**，蓋不到他其他沒掛單的課，介面上已標「僅供參考」。
- **撮合每輪全表重算**，但只做兩人互換，成本是每門課 O(n²)，數百人也是秒級（見上一節）。
- **免費層的 Supabase 閒置 7 天會暫停，pg_cron 隨之停擺。** 換組高峰期建議升 Pro，或用 GitHub Actions 定時打一次 RPC 兼作保活。
- **隊伍是黏著的，不會每輪重算。** 編進去就固定，`run_teaming()` 只處理還沒編隊的人。
  有人離隊時空位留給下一個新人，不會把後面隊伍的人搬上來——否則同學每 10 分鐘看到的隊友都在變。
- 學期結束在管理頁按「清除學生資料」，會一併清掉隊伍（`teams` 沒有指向 `students` 的外鍵，級聯帶不走）。
