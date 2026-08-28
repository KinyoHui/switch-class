import { reactive, watch } from 'vue'

const KEY = 'switch-class:identity'

const blank = { name: '', studentNo: '', phone: '', email: '', queryCode: '', remember: true }

function load () {
  try {
    const saved = JSON.parse(localStorage.getItem(KEY) || '{}')
    return { ...blank, ...saved }
  } catch {
    return { ...blank }
  }
}

// 全 app 共用一份：提交頁填過，查詢頁就不用再打一次
const identity = reactive(load())

watch(identity, (v) => {
  try {
    if (!v.remember) return localStorage.removeItem(KEY)
    localStorage.setItem(KEY, JSON.stringify(v))
  } catch { /* 無痕模式等情況下略過 */ }
}, { deep: true })

export function useIdentity () {
  const complete = () =>
    Boolean(identity.name.trim() && identity.studentNo.trim() && /^[0-9A-Za-z]{4,6}$/.test(identity.queryCode))

  const clear = () => {
    Object.assign(identity, blank)
    try { localStorage.removeItem(KEY) } catch { /* ignore */ }
  }

  return { identity, complete, clear }
}
