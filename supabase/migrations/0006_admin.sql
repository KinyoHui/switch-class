-- =====================================================================
-- 0006 · 管理員 RPC（管理頁專用，全部先檢查 is_admin()）
-- =====================================================================

create or replace function assert_admin() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then
    raise exception '需要管理員權限';
  end if;
end $$;

-- 課表批次匯入：一次寫入一門課的所有組別與節次
-- p_groups 形如
-- [{"group_no":"T03","capacity":null,"sessions":[
--    {"seq":1,"kind":"FT 導修課","weekday":0,"start_time":"11:00","end_time":"11:50",
--     "campus_code":"IOH","room":"F0201","start_date":"2026-09-06","end_date":"2026-10-11"}]}]
create or replace function import_course_internal(
  p_code text, p_name text, p_term text, p_duration text, p_groups jsonb
) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_course bigint; v_group bigint; g jsonb; s jsonb;
begin
  if coalesce(trim(p_code),'') = '' or coalesce(trim(p_term),'') = '' then
    raise exception '課程代碼與學期為必填';
  end if;

  insert into courses (code, name, term, duration)
  values (trim(p_code), trim(coalesce(p_name, p_code)), trim(p_term), nullif(trim(p_duration),''))
  on conflict (code, term) do update
    set name = excluded.name,
        duration = coalesce(excluded.duration, courses.duration),
        is_active = true
  returning id into v_course;

  for g in select * from jsonb_array_elements(coalesce(p_groups, '[]'::jsonb))
  loop
    insert into course_groups (course_id, group_no, capacity)
    values (v_course, upper(trim(g->>'group_no')), nullif(g->>'capacity','')::int)
    on conflict (course_id, group_no) do update
      set capacity = coalesce(excluded.capacity, course_groups.capacity),
          is_active = true
    returning id into v_group;

    -- 節次整組覆蓋，匯入即為最新版課表
    delete from group_sessions where group_id = v_group;

    for s in select * from jsonb_array_elements(coalesce(g->'sessions', '[]'::jsonb))
    loop
      -- 課表出現未登錄的校區代碼時先補一筆，避免外鍵擋下整批匯入
      if nullif(trim(s->>'campus_code'),'') is not null then
        insert into campuses (code, name)
        values (upper(trim(s->>'campus_code')), upper(trim(s->>'campus_code')))
        on conflict (code) do nothing;
      end if;

      insert into group_sessions
        (group_id, seq, kind, weekday, start_time, end_time,
         campus_code, room, start_date, end_date, remark)
      values (
        v_group,
        coalesce(nullif(s->>'seq','')::int, 1),
        nullif(trim(s->>'kind'),''),
        (s->>'weekday')::smallint,
        (s->>'start_time')::time,
        (s->>'end_time')::time,
        nullif(upper(trim(s->>'campus_code')),''),
        nullif(trim(s->>'room'),''),
        nullif(s->>'start_date','')::date,
        nullif(s->>'end_date','')::date,
        nullif(trim(s->>'remark'),'')
      );
    end loop;
  end loop;

  return v_course;
end $$;

create or replace function admin_import_course(
  p_code text, p_name text, p_term text, p_duration text, p_groups jsonb
) returns bigint
language plpgsql security definer set search_path = public as $$
begin
  perform assert_admin();
  return import_course_internal(p_code, p_name, p_term, p_duration, p_groups);
end $$;

-- 管理頁總覽：每門課的意向數、待處理候選組數
create or replace function admin_overview()
returns table (
  course_id bigint, course_code text, course_name text, term text,
  group_count bigint, open_requests bigint, pending_matches bigint, student_count bigint
)
language plpgsql security definer set search_path = public as $$
begin
  perform assert_admin();
  return query
    select c.id, c.code, c.name, c.term,
           (select count(*) from course_groups g where g.course_id = c.id and g.is_active),
           (select count(*) from swap_requests r where r.course_id = c.id and r.status = 'open'),
           (select count(*) from match_groups m where m.course_id = c.id and m.status = 'pending'),
           (select count(distinct r.student_id) from swap_requests r
             where r.course_id = c.id and r.status = 'open')
    from courses c
    where c.is_active
    order by c.term desc, c.code;
end $$;

-- 學生忘記查詢碼時清空，下次提交會重新設定
create or replace function admin_reset_query_code(p_student_no text) returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  perform assert_admin();
  update students set query_code_hash = null, updated_at = now()
  where student_no = upper(trim(p_student_no));
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- 手動觸發一輪撮合（pg_cron 之外的補救手段）
create or replace function admin_run_matching() returns int
language plpgsql security definer set search_path = public as $$
begin
  perform assert_admin();
  return run_matching();
end $$;

-- 學期結束清資料（設計文件第六節）
create or replace function admin_purge_students() returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  perform assert_admin();
  delete from students;               -- 級聯清掉意向、目標與匹配
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- is_admin() 要留給 authenticated：RLS policy 內的呼叫是以呼叫者身分求值的
revoke execute on function
  assert_admin(),
  import_course_internal(text,text,text,text,jsonb),
  admin_import_course(text,text,text,text,jsonb),
  admin_overview(), admin_reset_query_code(text),
  admin_run_matching(), admin_purge_students()
  from public, anon, authenticated;

grant execute on function
  admin_import_course(text,text,text,text,jsonb),
  admin_overview(), admin_reset_query_code(text),
  admin_run_matching(), admin_purge_students()
  to authenticated;
