<script setup>
import { computed } from 'vue'
import { campusTitle, sessionPlace, dateRanges, diffAgainst } from '../lib/format'

const props = defineProps({
  group:     { type: Object, required: true },
  mode:      { type: String, default: 'radio' },   // radio | check | plain
  selected:  { type: Boolean, default: false },
  order:     { type: Number, default: 0 },         // >0 時顯示志願序
  compareTo: { type: Object, default: null },      // 目前組別，用來標差異
  conflicts: { type: Array, default: () => [] }
})
defineEmits(['toggle', 'up', 'down'])

const diffs = computed(() => diffAgainst(props.group, props.compareTo))
</script>

<template>
  <div
    class="card cursor-pointer transition"
    :class="selected ? 'border-cyan-500 bg-cyan-950/25' : 'hover:border-ink-700/80 hover:bg-ink-800/40'"
    @click="$emit('toggle', group)"
  >
    <div class="flex items-start gap-3">
      <div class="mt-0.5 shrink-0">
        <span
          v-if="mode !== 'plain'"
          class="flex h-4 w-4 items-center justify-center border-2"
          :class="[
            mode === 'radio' ? 'rounded-full' : 'rounded',
            selected ? 'border-cyan-400 bg-cyan-500' : 'border-slate-600'
          ]"
        >
          <span v-if="selected && mode === 'radio'" class="h-1.5 w-1.5 rounded-full bg-ink-950"></span>
          <svg v-else-if="selected" viewBox="0 0 12 12" class="h-3 w-3 stroke-ink-950" stroke-width="2.2" fill="none">
            <path d="M2 6.5 4.8 9 10 3.2" stroke-linecap="round" stroke-linejoin="round" />
          </svg>
        </span>
      </div>

      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-2">
          <span class="font-semibold text-cyan-300">{{ group.group_no }}</span>
          <span v-if="order > 0" class="chip bg-cyan-900/50 text-cyan-200">第 {{ order }} 志願</span>
          <span v-if="group.capacity" class="chip">名額 {{ group.capacity }}</span>
        </div>

        <p v-if="!group.sessions.length" class="mt-1.5 text-sm text-slate-500">此組尚未登錄上課時間</p>

        <div v-for="(s, i) in group.sessions" :key="i" class="mt-1.5 text-sm leading-snug">
          <div class="flex flex-wrap items-baseline gap-x-2">
            <span class="text-slate-400">{{ s.kind || '課堂' }}</span>
            <span class="font-medium text-slate-100">{{ s.weekday_zh }} {{ s.time }}</span>
            <span class="text-slate-300" :title="campusTitle(s)">{{ sessionPlace(s) }}</span>
          </div>
          <div v-if="s.campus_name" class="text-[11px] text-slate-500">{{ campusTitle(s) }}</div>
          <div v-if="dateRanges(s)" class="text-[11px] text-slate-500">{{ dateRanges(s) }}</div>
        </div>

        <div v-if="diffs.length" class="mt-2 flex flex-wrap gap-1.5">
          <span v-for="d in diffs" :key="d" class="chip bg-amber-950/50 text-amber-300">改動：{{ d }}</span>
        </div>

        <div v-if="conflicts.length" class="mt-2 rounded-md bg-rose-950/40 px-2 py-1.5 text-[12px] text-rose-300">
          <span v-for="(c, i) in conflicts" :key="i" class="block">
            ⚠ 可能與 {{ c.course_code }} {{ c.group_no }} 衝堂（{{ c.detail }}）
          </span>
          <span class="mt-0.5 block text-rose-400/70">僅供參考，請自行核對完整課表</span>
        </div>
      </div>

      <div v-if="order > 0" class="flex shrink-0 flex-col gap-1" @click.stop>
        <button class="rounded border border-ink-700 px-1.5 text-xs text-slate-400 hover:text-cyan-300"
                title="提高志願序" @click="$emit('up', group)">▲</button>
        <button class="rounded border border-ink-700 px-1.5 text-xs text-slate-400 hover:text-cyan-300"
                title="降低志願序" @click="$emit('down', group)">▼</button>
      </div>
    </div>
  </div>
</template>
