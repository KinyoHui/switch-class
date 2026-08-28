<script setup>
import { useIdentity } from '../composables/useIdentity'

defineProps({ contact: { type: Boolean, default: false } })
const { identity, clear } = useIdentity()
</script>

<template>
  <div class="card">
    <div class="mb-3 flex items-center justify-between">
      <h2 class="text-sm font-semibold text-slate-200">身分</h2>
      <button class="text-xs text-slate-500 hover:text-rose-300" @click="clear">清除本機資料</button>
    </div>

    <div class="grid gap-3 sm:grid-cols-2">
      <div>
        <label class="label">姓名 <span class="text-rose-400">*</span></label>
        <input v-model="identity.name" class="field" placeholder="與學校記錄一致" autocomplete="name" />
      </div>
      <div>
        <label class="label">學號 <span class="text-rose-400">*</span></label>
        <input v-model="identity.studentNo" class="field" placeholder="例：12345678" autocomplete="username" />
      </div>
      <div v-if="contact">
        <label class="label">手機號（選填）</label>
        <input v-model="identity.phone" class="field" placeholder="配對成功後才會給對方" inputmode="tel" />
      </div>
      <div v-if="contact">
        <label class="label">Email（選填）</label>
        <input v-model="identity.email" class="field" type="email" placeholder="配對成功後才會給對方" />
      </div>
      <div>
        <label class="label">查詢碼 <span class="text-rose-400">*</span></label>
        <input v-model="identity.queryCode" class="field" maxlength="6" placeholder="4~6 位英數字，自己設定" />
        <p class="mt-1 text-[11px] text-slate-500">
          首次提交時設定，之後查詢與修改都要用它。忘記請找管理員重設。
        </p>
      </div>
      <div class="flex items-end">
        <label class="flex items-center gap-2 text-xs text-slate-400">
          <input v-model="identity.remember" type="checkbox" class="accent-cyan-500" />
          在此裝置記住我（共用電腦請勿勾選）
        </label>
      </div>
    </div>
  </div>
</template>
