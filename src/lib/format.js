export const WEEKDAYS = ['週日', '週一', '週二', '週三', '週四', '週五', '週六']

export const campusTitle = (s) =>
  [s.campus, s.campus_name, s.campus_addr].filter(Boolean).join(' – ')

export const sessionPlace = (s) => `${s.campus || '?'} / ${s.room || '?'}`

// 06/09/2026 - 11/10/2026、25/10/2026 - 29/11/2026
export const dateRanges = (s) => (s.date_ranges || []).join('、')

// 目標組別與目前組別的差異，讓使用者一眼看出換過去有什麼變化
export function diffAgainst (target, hold) {
  if (!hold || !target || target.group_id === hold.group_id) return []
  const out = []
  const days = (g) => [...new Set(g.sessions.map((s) => s.weekday))].sort()
  const campuses = (g) => [...new Set(g.sessions.map((s) => s.campus).filter(Boolean))].sort()
  const label = (ds) => ds.map((d) => WEEKDAYS[d]).join('、')

  const [hd, td] = [days(hold), days(target)]
  if (hd.join() !== td.join()) out.push(`${label(hd) || '—'} → ${label(td) || '—'}`)

  const [hc, tc] = [campuses(hold), campuses(target)]
  if (hc.join() !== tc.join()) out.push(`${hc.join('、') || '—'} → ${tc.join('、') || '—'}`)

  const earliest = (g) => g.sessions.map((s) => s.start_time).sort()[0]
  if (earliest(hold) && earliest(target) && earliest(hold) !== earliest(target)) {
    out.push(`最早 ${earliest(hold)} → ${earliest(target)}`)
  }
  return out
}
