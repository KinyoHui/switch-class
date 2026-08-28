<script setup>
import { ref, provide, computed } from 'vue'
import { configured } from './lib/supabase'
import AppNotice from './components/AppNotice.vue'
import SubmitView from './views/SubmitView.vue'
import QueryView from './views/QueryView.vue'
import AdminView from './views/AdminView.vue'

const TABS = [
  { key: 'submit', label: '提交意向' },
  { key: 'query', label: '我的匹配' },
  { key: 'admin', label: '管理' }
]

const tab = ref('submit')
const notice = ref(null)
let timer = null

function notify (text, type = 'info') {
  notice.value = { text, type }
  clearTimeout(timer)
  timer = setTimeout(() => { notice.value = null }, type === 'error' ? 7000 : 4000)
}
provide('notify', notify)

// 查詢頁按「修改」→ 帶著課程跳回提交頁
const editTarget = ref(null)
provide('editRequest', (courseId) => { editTarget.value = courseId; tab.value = 'submit' })

const view = computed(() => ({ submit: SubmitView, query: QueryView, admin: AdminView }[tab.value]))
</script>

<template>
  <AppNotice :notice="notice" @close="notice = null" />

  <div class="mx-auto max-w-3xl px-4 pb-16 pt-6">
    <header class="mb-5">
      <h1 class="text-xl font-semibold tracking-tight text-slate-100">換組意向匹配</h1>
      <p class="mt-1 text-sm text-slate-500">同一門課、不同組別之間互換。系統只做配對，換組仍需雙方到 MyHKMU 辦理。</p>
    </header>

    <div v-if="!configured" class="card mb-5 border-amber-800 bg-amber-950/40 text-sm text-amber-200">
      尚未設定 Supabase 連線。請複製 <code class="text-amber-300">.env.example</code> 為
      <code class="text-amber-300">.env</code> 並填入專案 URL 與 anon key。
    </div>

    <nav class="mb-5 flex gap-1 rounded-lg border border-ink-700 bg-ink-900/60 p-1">
      <button
        v-for="t in TABS" :key="t.key"
        class="flex-1 rounded-md px-3 py-1.5 text-sm transition"
        :class="tab === t.key ? 'bg-cyan-600 font-medium text-white' : 'text-slate-400 hover:text-slate-200'"
        @click="tab = t.key"
      >{{ t.label }}</button>
    </nav>

    <component :is="view" :edit-course-id="editTarget" @consumed-edit="editTarget = null" />

    <footer class="mt-10 border-t border-ink-800 pt-4 text-[11px] leading-relaxed text-slate-600">
      本站僅蒐集姓名、學號與聯絡方式，用途限於換組配對；聯絡方式只在配對成立後對同組成員顯示，學期結束後清除。<br />
      撮合每 10 分鐘統一執行一次，不是先到先得。衝堂提示僅涵蓋你在本站登記過的課程，僅供參考。
    </footer>
  </div>
</template>
