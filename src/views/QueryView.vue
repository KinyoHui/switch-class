<script setup>
import { ref, computed, inject } from 'vue'
import { listMyRequests, queryMatches, closeCourse, cancelRequest } from '../lib/api'
import { useIdentity } from '../composables/useIdentity'
import IdentityFields from '../components/IdentityFields.vue'

const notify = inject('notify')
const editRequest = inject('editRequest')
const { identity, complete } = useIdentity()

const requests = ref([])
const matchRows = ref([])
const loading = ref(false)
const loaded = ref(false)

async function load () {
  if (!complete()) return notify('請填妥姓名、學號與查詢碼', 'error')
  loading.value = true
  try {
    ;[requests.value, matchRows.value] = await Promise.all([
      listMyRequests(identity), queryMatches(identity)
    ])
    loaded.value = true
  } catch (e) {
    notify(e.message, 'error')
  } finally {
    loading.value = false
  }
}

// query_matches 是「每位對家一列」，這裡收攏成一組一張卡，並依 position 排出環的順序
const matches = computed(() => {
  const byId = new Map()
  for (const r of matchRows.value) {
    if (!byId.has(r.match_id)) {
      byId.set(r.match_id, {
        id: r.match_id,
        size: r.match_size,
        at: r.matched_at,
        courseName: r.course_name,
        courseId: r.course_id,
        members: [{ me: true, position: r.my_position, hold: r.my_hold, gets: r.my_gets, name: '你' }]
      })
    }
    byId.get(r.match_id).members.push({
      me: false,
      position: r.peer_position,
      hold: r.peer_hold,
      gets: r.peer_gets,
      name: r.peer_name,
      studentNo: r.peer_student_no,
      phone: r.peer_phone,
      email: r.peer_email
    })
  }
  return [...byId.values()].map((m) => ({ ...m, members: m.members.sort((a, b) => a.position - b.position) }))
})

const openRequests = computed(() => requests.value.filter((r) => r.status === 'open'))

async function copy (text) {
  try {
    await navigator.clipboard.writeText(text)
    notify(`已複製：${text}`)
  } catch {
    notify('複製失敗，請手動選取', 'error')
  }
}

async function doClose (r) {
  if (!confirm(`確定結束「${r.course_code}」的匹配？意向會關閉，相關候選組一併作廢。`)) return
  try {
    await closeCourse(identity, r.course_id)
    notify('已結束此課程的匹配')
    await load()
  } catch (e) { notify(e.message, 'error') }
}

async function doCancel (r) {
  if (!confirm(`撤銷「${r.course_code}」的換組意向？`)) return
  try {
    await cancelRequest(identity, r.request_id)
    notify('已撤銷')
    await load()
  } catch (e) { notify(e.message, 'error') }
}

const STATUS = { open: '進行中', closed: '已結束', cancelled: '已撤銷' }
</script>

<template>
  <div class="space-y-5">
    <IdentityFields />

    <button class="btn-primary w-full" :disabled="loading" @click="load">
      {{ loading ? '查詢中…' : '查詢我的意向與匹配' }}
    </button>

    <template v-if="loaded">
      <!-- ---------------------------------------------------------- 我的意向 -->
      <section>
        <h2 class="mb-2 text-sm font-semibold text-slate-200">我的意向</h2>
        <p v-if="!requests.length" class="card text-sm text-slate-500">還沒有任何意向，請先到「提交意向」登記。</p>

        <div v-for="r in requests" :key="r.request_id" class="card mb-2">
          <div class="flex flex-wrap items-start justify-between gap-2">
            <div class="min-w-0">
              <div class="flex items-center gap-2">
                <span class="font-medium text-slate-100">{{ r.course_code }}</span>
                <span class="truncate text-sm text-slate-400">{{ r.course_name }}</span>
                <span class="chip" :class="r.status === 'open' ? 'text-cyan-300' : ''">{{ STATUS[r.status] }}</span>
              </div>
              <p class="mt-1 text-xs text-slate-500">{{ r.term }}<span v-if="r.duration"> · 修讀期 {{ r.duration }}</span></p>
            </div>
            <div v-if="r.status === 'open'" class="flex shrink-0 gap-1.5">
              <button class="btn-ghost px-2 py-1 text-xs" @click="editRequest(r.course_id)">修改</button>
              <button class="btn-ghost px-2 py-1 text-xs" @click="doClose(r)">結束匹配</button>
              <button class="btn-danger px-2 py-1 text-xs" @click="doCancel(r)">撤銷</button>
            </div>
          </div>

          <dl class="mt-3 space-y-1.5 text-sm">
            <div class="flex gap-2">
              <dt class="w-16 shrink-0 text-xs text-slate-500">目前</dt>
              <dd class="text-slate-200">{{ r.hold_label }}</dd>
            </div>
            <div class="flex gap-2">
              <dt class="w-16 shrink-0 text-xs text-slate-500">可接受</dt>
              <dd class="space-y-0.5">
                <div v-for="t in r.targets" :key="t.group_id" class="text-slate-300">
                  <span class="chip mr-1">第 {{ t.priority }} 志願</span>{{ t.label }}
                </div>
              </dd>
            </div>
            <div v-if="r.note" class="flex gap-2">
              <dt class="w-16 shrink-0 text-xs text-slate-500">備註</dt>
              <dd class="text-slate-400">{{ r.note }}</dd>
            </div>
          </dl>

          <p v-if="r.status === 'open'" class="mt-2 text-xs" :class="r.match_count ? 'text-cyan-400' : 'text-slate-500'">
            {{ r.match_count ? `目前有 ${r.match_count} 個候選組合` : '尚未配對到，下一輪撮合會再試' }}
          </p>
        </div>
      </section>

      <!-- ---------------------------------------------------------- 匹配結果 -->
      <section>
        <h2 class="mb-2 text-sm font-semibold text-slate-200">匹配結果</h2>
        <p v-if="!matches.length" class="card text-sm text-slate-500">
          {{ openRequests.length ? '目前還沒有配對成功的組合。撮合每 10 分鐘跑一次，稍後再回來看看。' : '沒有進行中的意向。' }}
        </p>

        <div v-for="m in matches" :key="m.id" class="card mb-2 border-cyan-900/70">
          <div class="mb-3 flex flex-wrap items-center gap-2">
            <span class="chip bg-cyan-900/50 text-cyan-200">兩人互換</span>
            <span class="text-sm text-slate-300">{{ m.courseName }}</span>
          </div>

          <ol class="space-y-2">
            <li
              v-for="(p, i) in m.members" :key="i"
              class="rounded-lg border px-3 py-2"
              :class="p.me ? 'border-cyan-800 bg-cyan-950/30' : 'border-ink-700 bg-ink-900/50'"
            >
              <div class="flex flex-wrap items-center gap-2">
                <span class="font-medium" :class="p.me ? 'text-cyan-300' : 'text-slate-100'">{{ p.name }}</span>
                <span v-if="!p.me" class="chip">{{ p.studentNo }}</span>
              </div>
              <p class="mt-1 text-sm leading-relaxed text-slate-300">
                <span class="text-slate-500">目前</span> {{ p.hold }}
                <span class="mx-1 text-cyan-400">→</span>
                <span class="text-slate-500">換到</span> {{ p.gets }}
              </p>
              <div v-if="!p.me && (p.phone || p.email)" class="mt-2 flex flex-wrap gap-1.5">
                <button v-if="p.phone" class="btn-ghost px-2 py-1 text-xs" @click="copy(p.phone)">📱 {{ p.phone }}</button>
                <button v-if="p.email" class="btn-ghost px-2 py-1 text-xs" @click="copy(p.email)">✉ {{ p.email }}</button>
              </div>
              <p v-else-if="!p.me" class="mt-1 text-xs text-slate-500">對方未留聯絡方式</p>
            </li>
          </ol>

          <p class="mt-3 text-xs leading-relaxed text-slate-500">
            這是候選組合，不是成交。聯繫確認後請到 MyHKMU 完成換組，完成後回到上方按「結束匹配」。
          </p>
        </div>
      </section>
    </template>
  </div>
</template>
