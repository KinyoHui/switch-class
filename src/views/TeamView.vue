<script setup>
import { ref, computed, inject, onMounted } from 'vue'
import { listCourses, listGroups, submitTeam, myTeam, leaveTeam } from '../lib/api'
import { useIdentity } from '../composables/useIdentity'
import GroupCard from '../components/GroupCard.vue'
import IdentityFields from '../components/IdentityFields.vue'

const notify = inject('notify')
const { identity, complete } = useIdentity()

const courses = ref([])
const picked = ref([])          // [{ courseId, groupId }]，長度固定為選課數
const groupsBy = ref({})        // courseId → 組別清單
const note = ref('')
const rows = ref([])            // my_team 的回傳
const loading = ref(false)
const saving = ref(false)
const loaded = ref(false)

const NEED = 4                  // 與 team_course_count() 一致

const chosenCourseIds = computed(() => picked.value.map((p) => p.courseId).filter(Boolean))
const chosenGroupIds = computed(() => picked.value.map((p) => p.groupId).filter(Boolean))
const ready = computed(() => chosenGroupIds.value.length === NEED)

// 已被其他欄位選走的課程不再出現，避免同一門課選兩次
const availableFor = (i) => courses.value.filter(
  (c) => c.id === picked.value[i]?.courseId || !chosenCourseIds.value.includes(c.id)
)

onMounted(async () => {
  picked.value = Array.from({ length: NEED }, () => ({ courseId: null, groupId: null }))
  try { courses.value = await listCourses() } catch (e) { notify(e.message, 'error') }
})

async function pickCourse (i, courseId) {
  picked.value[i] = { courseId, groupId: null }
  if (!courseId || groupsBy.value[courseId]) return
  try {
    groupsBy.value = { ...groupsBy.value, [courseId]: await listGroups(courseId) }
  } catch (e) { notify(e.message, 'error') }
}

async function submit () {
  if (!complete()) return notify('請先填妥姓名、學號與 4~6 位查詢碼', 'error')
  if (!ready.value) return notify(`請完整選擇 ${NEED} 門課程的組別`, 'error')

  saving.value = true
  try {
    await submitTeam({
      name: identity.name,
      studentNo: identity.studentNo,
      phone: identity.phone,
      email: identity.email,
      queryCode: identity.queryCode,
      groupIds: chosenGroupIds.value,
      note: note.value
    })
    notify('已送出。下一輪編隊（每 10 分鐘）後可在下方看到隊友。')
    await load()
  } catch (e) {
    notify(e.message, 'error')
  } finally {
    saving.value = false
  }
}

async function load () {
  if (!complete()) return notify('請填妥姓名、學號與查詢碼', 'error')
  loading.value = true
  try {
    rows.value = await myTeam(identity)
    loaded.value = true
    // 把已提交的組合回填到選擇器，方便直接修改
    const open = rows.value.find((r) => r.status === 'open')
    if (open) {
      picked.value = open.courses.map((c) => ({ courseId: c.course_id, groupId: c.group_id }))
      note.value = open.note || ''
      for (const c of open.courses) {
        if (!groupsBy.value[c.course_id]) {
          groupsBy.value = { ...groupsBy.value, [c.course_id]: await listGroups(c.course_id) }
        }
      }
    }
  } catch (e) {
    notify(e.message, 'error')
  } finally {
    loading.value = false
  }
}

async function doLeave () {
  if (!confirm('撤銷組隊意向？你會離開目前的隊伍，名額讓給其他同學。')) return
  try {
    await leaveTeam(identity)
    notify('已撤銷組隊意向')
    rows.value = []
    loaded.value = false
  } catch (e) { notify(e.message, 'error') }
}

async function copy (text) {
  try {
    await navigator.clipboard.writeText(text)
    notify(`已複製：${text}`)
  } catch {
    notify('複製失敗，請手動選取', 'error')
  }
}

const current = computed(() => rows.value.find((r) => r.status === 'open') || null)
</script>

<template>
  <div class="space-y-5">
    <IdentityFields contact />

    <div class="card border-cyan-900/60 bg-cyan-950/20 text-sm leading-relaxed text-slate-300">
      填滿你這學期的 <span class="font-semibold text-cyan-300">{{ NEED }} 門課</span>，
      每門課選你所在的組別。{{ NEED }} 門課的<span class="text-cyan-300">課程、組別、上課時間與地點完全相同</span>的同學會編成一隊，
      一隊 {{ current?.team_size || 6 }} 人，超過就開新隊。同隊成員可以互相看到聯絡方式。
    </div>

    <!-- ------------------------------------------------------------ 選課 -->
    <section class="space-y-3">
      <h2 class="text-sm font-semibold text-slate-200">我的 {{ NEED }} 門課</h2>

      <div v-for="(p, i) in picked" :key="i" class="card">
        <div class="mb-2 flex items-center gap-2">
          <span class="chip bg-ink-800 text-slate-300">第 {{ i + 1 }} 門</span>
          <span v-if="p.groupId" class="chip bg-cyan-900/50 text-cyan-200">已選</span>
        </div>

        <select
          class="field"
          :value="p.courseId"
          @change="pickCourse(i, $event.target.value ? Number($event.target.value) : null)"
        >
          <option :value="''">— 請選擇課程 —</option>
          <option v-for="c in availableFor(i)" :key="c.id" :value="c.id">
            {{ c.code }} {{ c.name }}（{{ c.term }}）
          </option>
        </select>

        <div v-if="p.courseId && groupsBy[p.courseId]" class="mt-3 space-y-2">
          <p class="text-[11px] text-slate-500">選擇你目前所在的組別</p>
          <GroupCard
            v-for="g in groupsBy[p.courseId]" :key="g.group_id"
            :group="g" mode="radio" :selected="p.groupId === g.group_id"
            @toggle="picked[i] = { ...picked[i], groupId: g.group_id }"
          />
        </div>
      </div>

      <div class="card">
        <label class="label">備註（選填）</label>
        <textarea v-model="note" rows="2" class="field" placeholder="例如：可以約週末在圖書館討論"></textarea>
      </div>

      <div class="flex flex-wrap gap-2">
        <button class="btn-primary" :disabled="saving || !ready" @click="submit">
          {{ saving ? '送出中…' : current ? '更新我的課程組合' : '提交組隊意向' }}
        </button>
        <button class="btn-ghost" :disabled="loading" @click="load">
          {{ loading ? '查詢中…' : '查詢我的隊伍' }}
        </button>
        <button v-if="current" class="btn-danger" @click="doLeave">撤銷組隊</button>
      </div>
      <p v-if="!ready" class="text-xs text-slate-500">
        還需選擇 {{ NEED - chosenGroupIds.length }} 門課的組別才能提交。
      </p>
    </section>

    <!-- ------------------------------------------------------------ 隊伍 -->
    <section v-if="loaded">
      <h2 class="mb-2 text-sm font-semibold text-slate-200">我的隊伍</h2>

      <p v-if="!current" class="card text-sm text-slate-500">
        還沒有組隊意向，請在上方選滿 {{ NEED }} 門課後提交。
      </p>

      <template v-else>
        <!-- 尚未編隊 -->
        <div v-if="!current.team_id" class="card text-sm leading-relaxed text-slate-400">
          <p class="mb-1 text-amber-300">尚未編隊</p>
          <p v-if="current.waiting_same_combo > 1">
            目前有 {{ current.waiting_same_combo }} 位同學（含你）的課程組合完全相同，下一輪編隊就會成隊。
          </p>
          <p v-else>
            還沒有其他同學的 {{ NEED }} 門課與你完全相同。編隊每 10 分鐘跑一次，稍後再回來看看。
          </p>
        </div>

        <!-- 已編隊 -->
        <div v-else class="card border-cyan-900/70">
          <div class="mb-3 flex flex-wrap items-center gap-2">
            <span class="chip bg-cyan-900/50 text-cyan-200">第 {{ current.team_seq }} 隊</span>
            <span class="text-sm text-slate-300">
              {{ current.member_count }} / {{ current.team_size }} 人
            </span>
            <span v-if="current.member_count < current.team_size" class="text-xs text-slate-500">
              還有 {{ current.team_size - current.member_count }} 個名額
            </span>
          </div>

          <ul class="space-y-2">
            <li
              v-for="(m, i) in current.members" :key="i"
              class="rounded-lg border px-3 py-2"
              :class="m.is_me ? 'border-cyan-800 bg-cyan-950/30' : 'border-ink-700 bg-ink-900/50'"
            >
              <div class="flex flex-wrap items-center gap-2">
                <span class="font-medium" :class="m.is_me ? 'text-cyan-300' : 'text-slate-100'">
                  {{ m.is_me ? `${m.name}（你）` : m.name }}
                </span>
                <span class="chip">{{ m.student_no }}</span>
              </div>
              <div v-if="!m.is_me && (m.phone || m.email)" class="mt-2 flex flex-wrap gap-1.5">
                <button v-if="m.phone" class="btn-ghost px-2 py-1 text-xs" @click="copy(m.phone)">📱 {{ m.phone }}</button>
                <button v-if="m.email" class="btn-ghost px-2 py-1 text-xs" @click="copy(m.email)">✉ {{ m.email }}</button>
              </div>
              <p v-else-if="!m.is_me" class="mt-1 text-xs text-slate-500">此同學未留聯絡方式</p>
            </li>
          </ul>
        </div>

        <!-- 這一隊共同的課表 -->
        <div class="card mt-2">
          <h3 class="mb-2 text-sm font-semibold text-slate-200">
            {{ current.team_id ? '全隊共同的課程' : '你登記的課程組合' }}
          </h3>
          <div v-for="c in current.courses" :key="c.group_id" class="mb-2 last:mb-0">
            <div class="flex flex-wrap items-baseline gap-2">
              <span class="font-medium text-slate-100">{{ c.course_code }}</span>
              <span class="text-sm text-slate-400">{{ c.course_name }}</span>
              <span class="chip bg-cyan-900/50 text-cyan-200">{{ c.group_no }}</span>
            </div>
            <p class="mt-0.5 text-[12px] leading-snug text-slate-400">{{ c.time_label || '時間待定' }}</p>
          </div>
        </div>
      </template>
    </section>
  </div>
</template>
