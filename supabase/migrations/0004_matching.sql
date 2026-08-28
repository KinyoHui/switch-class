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

-- ------------------------------------------------------------ 4.2 三人環換
-- A 拿 B 的組、B 拿 C 的組、C 拿 A 的組
create or replace view v_triples as
  select a.id as a_id, b.id as b_id, c.id as c_id, a.course_id,
         b.hold_group_id as a_gets,
         c.hold_group_id as b_gets,
         a.hold_group_id as c_gets
  from swap_requests a
  join swap_requests b
    on b.course_id = a.course_id and b.status = 'open'
   and exists (select 1 from swap_targets t
               where t.request_id = a.id and t.group_id = b.hold_group_id)
  join swap_requests c
    on c.course_id = a.course_id and c.status = 'open'
   and exists (select 1 from swap_targets t
               where t.request_id = b.id and t.group_id = c.hold_group_id)
  where a.status = 'open'
    and exists (select 1 from swap_targets t
                where t.request_id = c.id and t.group_id = a.hold_group_id)
    and a.student_id <> b.student_id
    and b.student_id <> c.student_id
    and a.student_id <> c.student_id
    and a.id < b.id and a.id < c.id;   -- 固定最小 id 為環起點，避免旋轉重複

create or replace function match_triples() returns int
language plpgsql security definer set search_path = public as $$
declare v_new int;
begin
  insert into match_groups (course_id, size, signature)
  select course_id, 3, 'c:' || a_id || '-' || b_id || '-' || c_id from v_triples
  on conflict (signature) do nothing;
  get diagnostics v_new = row_count;

  with m as (
    select g.id as match_id, t.*
    from v_triples t
    join match_groups g
      on g.signature = 'c:' || t.a_id || '-' || t.b_id || '-' || t.c_id
  )
  insert into match_members (match_id, request_id, position, gets_group_id)
  select match_id, a_id, 1, a_gets from m
  union all
  select match_id, b_id, 2, b_gets from m
  union all
  select match_id, c_id, 3, c_gets from m
  on conflict (match_id, request_id) do nothing;

  return v_new;
end $$;

-- --------------------------------------------------------- 4.3 定時任務
create or replace function run_matching() returns int
language plpgsql security definer set search_path = public as $$
declare v_new int;
begin
  perform expire_stale_matches();          -- 1) 清理
  v_new := match_pairs();                  -- 2) 兩人互換
  v_new := v_new + match_triples();        -- 3) 三人環換
  return v_new;
end $$;

-- 排程（先在 Supabase 控制台 Database → Extensions 啟用 pg_cron）：
--   select cron.schedule('swap-matching', '*/10 * * * *',
--                        $$ select public.run_matching() $$);
