-- =====================================================================
-- 0005 · 安全與隱私（設計文件第六節）
-- 本系統存真實姓名、學號、手機號：anon 一律不得直接碰個資表
-- =====================================================================

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins a where a.user_id = auth.uid())
$$;

alter table courses        enable row level security;
alter table course_groups  enable row level security;
alter table group_sessions enable row level security;
alter table campuses       enable row level security;
alter table students       enable row level security;
alter table swap_requests  enable row level security;
alter table swap_targets   enable row level security;
alter table match_groups   enable row level security;
alter table match_members  enable row level security;
alter table admins         enable row level security;

-- ------------------------------------------------------ 課程資料：公開讀
drop policy if exists "read courses"  on courses;
drop policy if exists "read groups"   on course_groups;
drop policy if exists "read sessions" on group_sessions;
drop policy if exists "read campuses" on campuses;

create policy "read courses"  on courses        for select to anon, authenticated using (is_active);
create policy "read groups"   on course_groups  for select to anon, authenticated using (is_active);
create policy "read sessions" on group_sessions for select to anon, authenticated using (true);
create policy "read campuses" on campuses       for select to anon, authenticated using (true);

-- ------------------------------------------------------ 課程資料：管理員寫
drop policy if exists "admin courses"  on courses;
drop policy if exists "admin groups"   on course_groups;
drop policy if exists "admin sessions" on group_sessions;
drop policy if exists "admin campuses" on campuses;
drop policy if exists "read own admin" on admins;

create policy "admin courses"  on courses        for all to authenticated using (is_admin()) with check (is_admin());
create policy "admin groups"   on course_groups  for all to authenticated using (is_admin()) with check (is_admin());
create policy "admin sessions" on group_sessions for all to authenticated using (is_admin()) with check (is_admin());
create policy "admin campuses" on campuses       for all to authenticated using (is_admin()) with check (is_admin());
create policy "read own admin" on admins         for select to authenticated using (user_id = auth.uid());

-- ------------------- 個資表：不建任何 policy → 直接存取一律失敗 -------------------
revoke all on table students, swap_requests, swap_targets,
                   match_groups, match_members
  from anon, authenticated;

-- Supabase 預設有給 public schema 的表授權，但不依賴預設，顯式寫出來
grant select on table courses, course_groups, group_sessions, campuses,
                      v_group_detail, v_group_session_merged
  to anon, authenticated;

-- 管理頁的寫入：授權給 authenticated，實際放行與否由上面的 is_admin() policy 決定
grant insert, update, delete on table courses, course_groups, group_sessions, campuses
  to authenticated;
grant select on table admins to authenticated;

-- ------------------------------------------------------------- 函式授權
revoke execute on function
  submit_swap(text,text,text,text,text,bigint,bigint,bigint[],text),
  list_my_requests(text,text,text),
  query_matches(text,text,text),
  close_course(bigint,text,text,text),
  cancel_request(bigint,text,text,text),
  check_conflicts(text,text,text,bigint),
  verify_student(text,text,text),
  expire_stale_matches(),
  match_pairs(), run_matching()
  from public, anon, authenticated;

grant execute on function
  submit_swap(text,text,text,text,text,bigint,bigint,bigint[],text),
  list_my_requests(text,text,text),
  query_matches(text,text,text),
  close_course(bigint,text,text,text),
  cancel_request(bigint,text,text,text),
  check_conflicts(text,text,text,bigint)
  to anon, authenticated;
