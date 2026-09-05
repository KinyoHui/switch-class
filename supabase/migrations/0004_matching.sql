-- =====================================================================
-- 0004 · 匹配引擎（設計文件第四節）
-- 候選而非成交：同一筆意向可同時出現在多個候選組
-- =====================================================================

-- ------------------------------------------------------------ 4.1 兩人互換
-- A 接受 B 的組，且 B 接受 A 的組
create or replace function match_pairs() returns int
language plpgsql security definer set search_path = public as $$
declare v_new int;
begin
  with pairs as (
    select a.id as a_id, b.id as b_id, a.course_id,
           b.hold_group_id as a_gets, a.hold_group_id as b_gets
    from swap_requests a
    join swap_requests b
      on b.course_id = a.course_id
     and b.status = 'open'
     and b.student_id <> a.student_id
     and a.id < b.id                              -- 方向去重
    where a.status = 'open'
      and exists (select 1 from swap_targets t
                  where t.request_id = a.id and t.group_id = b.hold_group_id)
      and exists (select 1 from swap_targets t
                  where t.request_id = b.id and t.group_id = a.hold_group_id)
  )
  insert into match_groups (course_id, size, signature)
  select course_id, 2, 'p:' || a_id || '-' || b_id from pairs
  on conflict (signature) do nothing;
  get diagnostics v_new = row_count;

  with pairs as (
    select a.id as a_id, b.id as b_id,
           b.hold_group_id as a_gets, a.hold_group_id as b_gets
    from swap_requests a
    join swap_requests b
      on b.course_id = a.course_id
     and b.status = 'open'
     and b.student_id <> a.student_id
     and a.id < b.id
    where a.status = 'open'
      and exists (select 1 from swap_targets t
                  where t.request_id = a.id and t.group_id = b.hold_group_id)
      and exists (select 1 from swap_targets t
                  where t.request_id = b.id and t.group_id = a.hold_group_id)
  ),
  m as (
    select g.id as match_id, p.*
    from pairs p
    join match_groups g on g.signature = 'p:' || p.a_id || '-' || p.b_id
  )
  insert into match_members (match_id, request_id, position, gets_group_id)
  select match_id, a_id, 1, a_gets from m
  union all
  select match_id, b_id, 2, b_gets from m
  on conflict (match_id, request_id) do nothing;

  return v_new;
end $$;

-- --------------------------------------------------------- 4.2 定時任務
create or replace function run_matching() returns int
language plpgsql security definer set search_path = public as $$
declare v_new int;
begin
  perform expire_stale_matches();          -- 1) 清理
  v_new := match_pairs();                  -- 2) 兩人互換
  return v_new;
end $$;

-- 排程（先在 Supabase 控制台 Database → Extensions 啟用 pg_cron）：
--   select cron.schedule('swap-matching', '*/10 * * * *',
--                        $$ select public.run_matching() $$);
