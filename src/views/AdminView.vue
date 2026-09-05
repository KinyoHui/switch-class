<script setup>
import { ref, onMounted, inject } from 'vue'
import {
  signIn, signOut, currentAdmin, adminOverview, adminImportCourse,
  adminRunMatching, adminPurgeStudents, adminResetQueryCode,
  adminTeamOverview, adminRunTeaming
} from '../lib/api'
import { parseTimetable } from '../lib/parseTimetable'

const notify = inject('notify')

const user = ref(null)
const email = ref('')
const password = ref('')
const busy = ref(false)

const overview = ref([])
const teamOverview = ref([])
const raw = ref('')
const draft = ref('')          // 解析結果，匯入前可直接改
const warnings = ref([])
const resetNo = ref('')

onMounted(refresh)

async function refresh () {
  try {
    user.value = await currentAdmin()
    if (user.value) {
      ;[overview.value, teamOverview.value] =
        await Promise.all([adminOverview(), adminTeamOverview()])
    }
  } catch (e) { notify(e.message, 'error') }
}

async function login () {
  busy.value = true
  try {
    await signIn(email.value, password.value)
    await refresh()
    if (!user.value) notify('此帳號不在 admins 名單中', 'error')
    password.value = ''
  } catch (e) { notify(e.message, 'error') } finally { busy.value = false }
}

async function logout () {
  await signOut()
  user.value = null
  overview.value = []
  teamOverview.value = []
}

function parse () {
  const { course, warnings: w } = parseTimetable(raw.value)
  draft.value = JSON.stringify(course, null, 2)
  warnings.value = w
  notify(w.length ? `解析完成，有 ${w.length} 項需確認` : '解析完成，請核對後匯入')
}

async function doImport () {
  let course
  try { course = JSON.parse(draft.value) } catch { return notify('JSON 格式有誤', 'error') }
  busy.value = true
  try {
    await adminImportCourse(course)
    notify(`已匯入 ${course.code}（節次為整組覆蓋）`)
    overview.value = await adminOverview()
  } catch (e) { notify(e.message, 'error') } finally { busy.value = false }
}

async function run (fn, ok, confirmText) {
  if (confirmText && !confirm(confirmText)) return
  busy.value = true
  try {
    const n = await fn()
    notify(ok(n))
    ;[overview.value, teamOverview.value] =
      await Promise.all([adminOverview(), adminTeamOverview()])
  } catch (e) { notify(e.message, 'error') } finally { busy.value = false }
}

const SAMPLE = `ENVR 8951SCF 中國特色的可持續發展（二○二六年秋季學期）  修讀期：一學期
序 組別  類別      日期及時間          地點          開始/結束日期
1  T03  FT 導修課  Sun 11:00 - 11:50  IOH / F0201   06/09/2026 - 11/10/2026
                                                    25/10/2026 - 29/11/2026
2       FT 面授課  Sun 09:00 - 10:50  IOH / F0201   06/09/2026 - 11/10/2026
                                                    25/10/2026 - 29/11/2026`
</script>

<template>
  <!-- --------------------------------------------------------------- 登入 -->
  <div v-if="!user" class="card space-y-3">
    <h2 class="text-sm font-semibold text-slate-200">管理員登入</h2>
    <p class="text-xs text-slate-500">
      走 Supabase Auth。建立帳號後，把該使用者的 user_id 寫進 <code class="text-cyan-400">admins</code> 表才會生效。
    </p>
    <input v-model="email" class="field" type="email" placeholder="Email" autocomplete="username" />
    <input v-model="password" class="field" type="password" placeholder="密碼" autocomplete="current-password"
           @keyup.enter="login" />
    <button class="btn-primary w-full" :disabled="busy" @click="login">登入</button>
  </div>

  <div v-else class="space-y-5">
    <div class="flex items-center justify-between text-sm">
      <span class="text-slate-400">{{ user.email }}</span>
      <button class="btn-ghost px-2 py-1 text-xs" @click="logout">登出</button>
    </div>

    <!-- ------------------------------------------------------------ 總覽 -->
    <section class="card">
      <h2 class="mb-3 text-sm font-semibold text-slate-200">課程總覽</h2>
      <div class="-mx-4 overflow-x-auto px-4">
        <table class="w-full min-w-[30rem] text-sm">
          <thead class="text-left text-xs text-slate-500">
            <tr class="border-b border-ink-700">
              <th class="py-1.5 pr-3 font-medium">課程</th>
              <th class="py-1.5 pr-3 font-medium">組別</th>
              <th class="py-1.5 pr-3 font-medium">意向</th>
              <th class="py-1.5 pr-3 font-medium">學生</th>
              <th class="py-1.5 font-medium">候選組</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="c in overview" :key="c.course_id" class="border-b border-ink-800/70">
              <td class="py-1.5 pr-3">
                <span class="text-slate-200">{{ c.course_code }}</span>
                <span class="ml-1 text-xs text-slate-500">{{ c.term }}</span>
              </td>
              <td class="py-1.5 pr-3 text-slate-400">{{ c.group_count }}</td>
              <td class="py-1.5 pr-3 text-slate-400">{{ c.open_requests }}</td>
              <td class="py-1.5 pr-3 text-slate-400">{{ c.student_count }}</td>
              <td class="py-1.5 text-cyan-300">{{ c.pending_matches }}</td>
            </tr>
            <tr v-if="!overview.length"><td colspan="5" class="py-3 text-slate-500">尚無課程</td></tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- -------------------------------------------------------- 組隊總覽 -->
    <section class="card">
      <h2 class="mb-2 text-sm font-semibold text-slate-200">課程組隊</h2>
      <p class="mb-3 text-xs text-slate-500">
        依「4 門課完全相同」分群。一隊 6 人，滿了自動開新隊；等待中＝組合尚無第二人或名額待補。
      </p>
      <div class="space-y-2">
        <div v-for="t in teamOverview" :key="t.signature" class="rounded-lg border border-ink-700 bg-ink-900/50 p-3">
          <div class="mb-2 flex flex-wrap items-center gap-2 text-xs">
            <span class="chip bg-cyan-900/50 text-cyan-200">{{ t.team_count }} 支隊伍</span>
            <span class="text-slate-400">已編隊 {{ t.member_count }} 人</span>
            <span v-if="t.waiting > 0" class="text-amber-300">等待中 {{ t.waiting }} 人</span>
          </div>
          <div class="flex flex-wrap gap-1.5">
            <span v-for="c in t.courses" :key="c.group_id" class="chip">
              {{ c.course_code }} <span class="ml-1 text-cyan-300">{{ c.group_no }}</span>
            </span>
          </div>
        </div>
        <p v-if="!teamOverview.length" class="text-sm text-slate-500">尚無組隊意向</p>
      </div>
    </section>

    <!-- -------------------------------------------------------- 課表匯入 -->
    <section class="card space-y-3">
      <div class="flex items-center justify-between">
        <h2 class="text-sm font-semibold text-slate-200">課表批次匯入</h2>
        <button class="text-xs text-cyan-400 hover:text-cyan-300" @click="raw = SAMPLE">填入範例</button>
      </div>
      <p class="text-xs text-slate-500">貼上 MyHKMU 課表文字 → 解析 → 核對 JSON → 匯入。同一課程重複匯入為覆蓋，節次整組取代。</p>

      <textarea v-model="raw" rows="7" class="field font-mono text-xs" placeholder="貼上課表文字…"></textarea>
      <button class="btn-ghost" @click="parse">解析</button>

      <ul v-if="warnings.length" class="space-y-0.5 rounded-md bg-amber-950/40 px-3 py-2 text-xs text-amber-300">
        <li v-for="(w, i) in warnings" :key="i">⚠ {{ w }}</li>
      </ul>

      <template v-if="draft">
        <label class="label">解析結果（可直接修改）</label>
        <textarea v-model="draft" rows="12" class="field font-mono text-xs"></textarea>
        <button class="btn-primary" :disabled="busy" @click="doImport">匯入</button>
      </template>
    </section>

    <!-- ------------------------------------------------------------ 維運 -->
    <section class="card space-y-3">
      <h2 class="text-sm font-semibold text-slate-200">維運</h2>

      <div class="flex flex-wrap gap-2">
        <button class="btn-ghost" :disabled="busy"
                @click="run(adminRunMatching, (n) => `撮合完成，新增 ${n} 個候選組`)">
          手動執行一輪撮合
        </button>
        <button class="btn-ghost" :disabled="busy"
                @click="run(adminRunTeaming, (n) => `編隊完成，新建 ${n} 支隊伍`)">
          手動執行一輪編隊
        </button>
        <button class="btn-danger" :disabled="busy"
                @click="run(adminPurgeStudents, (n) => `已清除 ${n} 位學生的資料`,
                           '確定清除所有學生資料？意向與匹配會一併刪除，無法復原。')">
          學期結束清除學生資料
        </button>
      </div>

      <div class="flex flex-wrap items-end gap-2">
        <div class="min-w-0 flex-1">
          <label class="label">重設查詢碼（學生忘記時）</label>
          <input v-model="resetNo" class="field" placeholder="學號" />
        </div>
        <button class="btn-ghost" :disabled="busy || !resetNo"
                @click="run(() => adminResetQueryCode(resetNo), (n) => n ? '已清除，該生下次提交會重設查詢碼' : '查無此學號')">
          重設
        </button>
      </div>

      <p class="text-xs leading-relaxed text-slate-500">
        pg_cron 排程請在 Supabase SQL Editor 執行：<br />
        <code class="text-cyan-400">select cron.schedule('swap-matching', '*/10 * * * *', $$ select public.run_matching() $$);</code><br />
        <code class="text-cyan-400">select cron.schedule('team-matching', '*/10 * * * *', $$ select public.run_teaming() $$);</code>
      </p>
    </section>
  </div>
</template>
