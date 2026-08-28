/*
 * 把 MyHKMU 課表貼上的純文字解析成 admin_import_course 需要的結構。
 * 解析結果一定要讓管理員過目再匯入——課表格式會變，正則只負責省力，不負責保證。
 *
 * 認得的樣子：
 *   ENVR 8951SCF 中國特色的可持續發展（二○二六年秋季學期）  修讀期：一學期
 *   1  T03  FT 導修課  Sun 11:00 - 11:50  IOH / F0201   06/09/2026 - 11/10/2026
 *                                                       25/10/2026 - 29/11/2026
 *   2       FT 面授課  Sun 09:00 - 10:50  IOH / F0201   06/09/2026 - 11/10/2026
 */

const WEEKDAY = {
  sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6,
  '日': 0, '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6
}

const CN_DIGIT = { '〇': 0, '○': 0, '零': 0, '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9 }

const RE = {
  course: /^([A-Z]{3,5}\s?\d{3,4}[A-Z]{0,4})\s+(.+?)$/,
  term: /[（(]([^）)]*(?:學期|学期)[^）)]*)[）)]/,
  duration: /修讀期\s*[:：]\s*(\S+)/,
  group: /\b(T\d{1,3})\b/,
  seq: /^\s*(\d{1,2})\b/,
  time: /(\d{1,2}:\d{2})\s*[-–~]\s*(\d{1,2}:\d{2})/,
  weekday: /\b(Sun|Mon|Tue|Wed|Thu|Fri|Sat)\w*\b|(?:星期|週|周)([日一二三四五六])/i,
  place: /\b([A-Z]{2,5})\s*\/\s*([A-Za-z0-9._-]+)/,
  kind: /((?:FT|PT)?\s*[一-龥]{1,6}課)/,
  dates: /(\d{1,2}\/\d{1,2}\/\d{4})\s*[-–~]\s*(\d{1,2}\/\d{1,2}\/\d{4})/
}

const pad = (t) => t.replace(/^(\d):/, '0$1:')

const toISO = (d) => {
  const [dd, mm, yyyy] = d.split('/')
  return `${yyyy}-${mm.padStart(2, '0')}-${dd.padStart(2, '0')}`
}

// 二○二六年秋季學期 → 2026-秋
function normalizeTerm (raw) {
  if (!raw) return ''
  let year = (raw.match(/\d{4}/) || [])[0]
  if (!year) {
    const cn = raw.match(/[〇○零一二三四五六七八九]{4}/)
    if (cn) year = [...cn[0]].map((c) => CN_DIGIT[c]).join('')
  }
  const season = (raw.match(/[春夏秋冬]/) || [])[0]
  if (year && season) return `${year}-${season}`
  return raw.trim()
}

function weekdayOf (line) {
  const m = line.match(RE.weekday)
  if (!m) return null
  const key = (m[1] || m[2] || '').toLowerCase().slice(0, 3)
  return key in WEEKDAY ? WEEKDAY[key] : (m[2] in WEEKDAY ? WEEKDAY[m[2]] : null)
}

export function parseTimetable (text) {
  const lines = String(text || '').split(/\r?\n/)
  const warnings = []
  const course = { code: '', name: '', term: '', duration: '', groups: [] }

  const groups = new Map()          // group_no -> { group_no, sessions[] }
  let currentGroup = null
  let lastSession = null
  let seq = 0

  for (const raw of lines) {
    const line = raw.replace(/ /g, ' ').trimEnd()
    if (!line.trim()) continue
    if (/^\s*序\s|組別|日期及時間/.test(line) && !RE.time.test(line)) continue   // 表頭

    // 只有日期的續行 → 沿用上一節次，換一段開課日期
    const onlyDates = line.trim().match(new RegExp(`^${RE.dates.source}$`))
    if (onlyDates && lastSession) {
      groups.get(lastSession.group).sessions.push({
        ...lastSession.session,
        start_date: toISO(onlyDates[1]),
        end_date: toISO(onlyDates[2])
      })
      continue
    }

    const time = line.match(RE.time)
    const wd = weekdayOf(line)

    // 課程標題列：沒有時間、有課程代碼
    if (!time && !course.code) {
      const m = line.match(RE.course)
      if (m) {
        course.code = m[1].replace(/\s+/g, ' ').trim()
        course.name = m[2].replace(RE.term, '').replace(RE.duration, '').trim()
        course.term = normalizeTerm((line.match(RE.term) || [])[1])
        course.duration = (line.match(RE.duration) || [])[1] || ''
        continue
      }
    }
    if (!time) {
      if (!course.term) course.term = normalizeTerm((line.match(RE.term) || [])[1]) || course.term
      if (!course.duration) course.duration = (line.match(RE.duration) || [])[1] || ''
      continue
    }

    const g = line.match(RE.group)
    if (g) currentGroup = g[1].toUpperCase()
    if (!currentGroup) { warnings.push(`略過（找不到所屬組別）：${line.trim()}`); continue }
    if (wd === null) { warnings.push(`略過（讀不出星期）：${line.trim()}`); continue }

    if (!groups.has(currentGroup)) { groups.set(currentGroup, { group_no: currentGroup, sessions: [] }); seq = 0 }

    const place = line.match(RE.place)
    const dates = line.match(RE.dates)
    // 課程代碼不是課別，先把它從行首拿掉再抓「…課」
    const kind = line.replace(RE.course, '').match(RE.kind)
    seq = Number((line.match(RE.seq) || [])[1]) || seq + 1

    const session = {
      seq,
      kind: kind ? kind[1].replace(/\s+/g, ' ').trim() : null,
      weekday: wd,
      start_time: pad(time[1]),
      end_time: pad(time[2]),
      campus_code: place ? place[1].toUpperCase() : null,
      room: place ? place[2] : null,
      start_date: dates ? toISO(dates[1]) : null,
      end_date: dates ? toISO(dates[2]) : null
    }
    if (!dates) warnings.push(`沒有開課日期：${currentGroup} ${session.kind || ''} ${session.start_time}`)

    groups.get(currentGroup).sessions.push(session)
    lastSession = { group: currentGroup, session }
  }

  course.groups = [...groups.values()].sort((a, b) => a.group_no.localeCompare(b.group_no))

  if (!course.code) warnings.push('讀不出課程代碼，請手動填寫')
  if (!course.term) warnings.push('讀不出學期，請手動填寫')
  if (!course.groups.length) warnings.push('沒有解析到任何組別')

  return { course, warnings }
}
