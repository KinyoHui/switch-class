import { supabase, configured } from './supabase'

// Supabase 的 RPC 錯誤物件把訊息藏在幾個不同欄位，統一成一句可直接顯示的話
function unwrap ({ data, error }) {
  if (error) throw new Error(error.message || error.hint || error.details || '操作失敗')
  return data
}

function assertReady () {
  if (!configured) throw new Error('尚未設定 Supabase 連線（.env）')
}

const rpc = async (fn, args) => {
  assertReady()
  return unwrap(await supabase.rpc(fn, args))
}

/* ------------------------------------------------------------ 公開課程資料 */

export async function listCourses () {
  assertReady()
  return unwrap(
    await supabase.from('courses')
      .select('id, code, name, term, duration')
      .eq('is_active', true)
      .order('term', { ascending: false })
      .order('code')
  )
}

export async function listGroups (courseId) {
  assertReady()
  return unwrap(
    await supabase.from('v_group_detail')
      .select('*')
      .eq('course_id', courseId)
      .order('group_no')
  )
}

/* ------------------------------------------------------------------- 學生端 */

export const submitSwap = (p) => rpc('submit_swap', {
  p_name: p.name,
  p_student_no: p.studentNo,
  p_phone: p.phone || null,
  p_email: p.email || null,
  p_query_code: p.queryCode,
  p_course_id: p.courseId,
  p_hold_group: p.holdGroupId,
  p_targets: p.targetGroupIds,
  p_note: p.note || null
})

const identity = (id) => ({
  p_student_no: id.studentNo, p_name: id.name, p_code: id.queryCode
})

export const listMyRequests = (id) => rpc('list_my_requests', identity(id))
export const queryMatches   = (id) => rpc('query_matches', identity(id))

export const closeCourse = (id, courseId) =>
  rpc('close_course', { ...identity(id), p_course_id: courseId })

export const cancelRequest = (id, requestId) =>
  rpc('cancel_request', { ...identity(id), p_request_id: requestId })

export const checkConflicts = (id, groupId) =>
  rpc('check_conflicts', { ...identity(id), p_group: groupId })

/* ------------------------------------------------------------------- 管理端 */

export const adminOverview       = () => rpc('admin_overview')
export const adminRunMatching    = () => rpc('admin_run_matching')
export const adminPurgeStudents  = () => rpc('admin_purge_students')
export const adminResetQueryCode = (studentNo) =>
  rpc('admin_reset_query_code', { p_student_no: studentNo })

export const adminImportCourse = (c) => rpc('admin_import_course', {
  p_code: c.code, p_name: c.name, p_term: c.term,
  p_duration: c.duration || null, p_groups: c.groups
})

export async function signIn (email, password) {
  assertReady()
  return unwrap(await supabase.auth.signInWithPassword({ email, password }))
}

export async function signOut () {
  assertReady()
  await supabase.auth.signOut()
}

export async function currentAdmin () {
  if (!configured) return null
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return null
  // policy "read own admin" 只放行自己那一列，查得到就是管理員
  const { data } = await supabase.from('admins').select('user_id').limit(1)
  return data?.length ? session.user : null
}
