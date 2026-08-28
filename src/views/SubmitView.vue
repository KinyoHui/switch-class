<script setup>
import { ref, computed, watch, inject, onMounted } from 'vue'
import { listCourses, listGroups, submitSwap, checkConflicts } from '../lib/api'
import { useIdentity } from '../composables/useIdentity'
import GroupCard from '../components/GroupCard.vue'
import IdentityFields from '../components/IdentityFields.vue'

const props = defineProps({ editCourseId: { type: Number, default: null } })
const emit = defineEmits(['consumedEdit'])

const notify = inject('notify')
const { identity, complete } = useIdentity()

const courses = ref([])
const courseId = ref(null)
const groups = ref([])
const holdId = ref(null)
const targetIds = ref([])          // 順序即志願序
const conflicts = ref({})
const note = ref('')
const loading = ref(false)
const saving = ref(false)

const holdGroup = computed(() => groups.value.find((g) => g.group_id === holdId.value) || null)
const candidates = computed(() => groups.value.filter((g) => g.group_id !== holdId.value))
const soleGroup = computed(() => courseId.value && !loading.value && groups.value.length < 2)
const orderOf = (g) => targetIds.value.indexOf(g.group_id) + 1

onMounted(async () => {
  try { courses.value = await listCourses() } catch (e) { notify(e.message, 'error') }
})

watch(() => props.editCourseId, (id) => {
  if (id) { courseId.value = id; emit('consumedEdit') }
}, { immediate: true })

watch(courseId, async (id) => {
  groups.value = []; holdId.value = null; targetIds.value = []; conflicts.value = {}
  if (!id) return
  loading.value = true
  try { groups.value = await listGroups(id) } catch (e) { notify(e.message, 'error') }
  finally { loading.value = false }
})

// 換了持有組別，原本選中的它要退出目標清單
watch(holdId, (id) => {
  targetIds.value = targetIds.value.filter((t) => t !== id)
  runConflictCheck()
})

// 衝堂提示是加分項：學生尚未登記過任何課程時 RPC 會失敗，靜默略過即可
async function runConflictCheck () {
  conflicts.value = {}
  if (!complete() || !candidates.value.length) return
  for (const g of candidates.value) {
    try {
      const rows = await checkConflicts(identity, g.group_id)
      if (rows?.length) conflicts.value = { ...conflicts.value, [g.group_id]: rows }
    } catch { return }
  }
}

function toggleTarget (g) {
  const i = targetIds.value.indexOf(g.group_id)
  if (i >= 0) targetIds.value.splice(i, 1)
  else targetIds.value.push(g.group_id)
}

function move (g, delta) {
  const i = targetIds.value.indexOf(g.group_id)
  const j = i + delta
  if (i < 0 || j < 0 || j >= targetIds.value.length) return
  const [x] = targetIds.value.splice(i, 1)
  targetIds.value.splice(j, 0, x)
}

const selectAll = () => { targetIds.value = candidates.value.map((g) => g.group_id) }

async function submit (next = false) {
  if (!complete()) return notify('請先填妥姓名、學號與 4~6 位查詢碼', 'error')
  if (!courseId.value || !holdId.value) return notify('請選擇課程與你目前的組別', 'error')
  if (!targetIds.value.length) return notify('請至少選一個可接受的組別', 'error')

  saving.value = true
  try {
    await submitSwap({
      name: identity.name,
      studentNo: identity.studentNo,
      phone: identity.phone,
      email: identity.email,
      queryCode: identity.queryCode,
      courseId: courseId.value,
      holdGroupId: holdId.value,
      targetGroupIds: targetIds.value,
      note: note.value
    })
    notify('已送出。下一輪撮合（每 10 分鐘）後可到「我的匹配」查看結果。')
    note.value = ''
    if (next) courseId.value = null
  } catch (e) {
    notify(e.message, 'error')
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="space-y-5">
    <IdentityFields contact />

    <div class="card">
      <label class="label">課程</label>
      <select v-model="courseId" class="field">
        <option :value="null">— 請選擇課程 —</option>
        <option v-for="c in courses" :key="c.id" :value="c.id">
          {{ c.code }} {{ c.name }}（{{ c.term }}）
        </option>
      </select>
      <p v-if="soleGroup" class="mt-2 text-sm text-amber-300">
        此課程僅開設一個組別，無法換組。
      </p>
    </div>

    <template v-if="courseId && groups.length > 1">
      <section>
        <h2 class="mb-2 text-sm font-semibold text-slate-200">我目前的組別<span class="ml-1 text-xs font-normal text-slate-500">單選</span></h2>
        <div class="space-y-2">
          <GroupCard
            v-for="g in groups" :key="g.group_id"
            :group="g" mode="radio" :selected="holdId === g.group_id"
            @toggle="holdId = g.group_id"
          />
        </div>
      </section>

      <section v-if="holdId">
        <div class="mb-2 flex flex-wrap items-center justify-between gap-2">
          <h2 class="text-sm font-semibold text-slate-200">
            我可接受的組別<span class="ml-1 text-xs font-normal text-slate-500">多選，選愈多成交機率愈高</span>
          </h2>
          <button class="text-xs text-cyan-400 hover:text-cyan-300" @click="selectAll">除目前組別外全選</button>
        </div>
        <p class="mb-2 text-[11px] text-slate-500">用 ▲▼ 調整志願序，第一志願排最前；不排序就維持預設順序。</p>

        <div class="space-y-2">
          <GroupCard
            v-for="g in candidates" :key="g.group_id"
            :group="g" mode="check"
            :selected="targetIds.includes(g.group_id)"
            :order="orderOf(g)"
            :compare-to="holdGroup"
            :conflicts="conflicts[g.group_id] || []"
            @toggle="toggleTarget"
            @up="move($event, -1)"
            @down="move($event, 1)"
          />
        </div>
      </section>

      <div class="card">
        <label class="label">備註（選填）</label>
        <textarea v-model="note" rows="2" class="field" placeholder="例如：只想避開週日早上"></textarea>
      </div>

      <div class="flex flex-wrap gap-2">
        <button class="btn-primary" :disabled="saving" @click="submit(false)">
          {{ saving ? '送出中…' : '提交' }}
        </button>
        <button class="btn-ghost" :disabled="saving" @click="submit(true)">提交並換下一門課</button>
      </div>
    </template>
  </div>
</template>
