-- =====================================================================
-- 0003 · 對外介面（RPC）
-- 全部 SECURITY DEFINER；前端只呼叫這些函式 + 直讀公開課程資料
-- =====================================================================

-- ------------------------------------------------- 身分校驗（學號＋姓名＋查詢碼）
create or replace function verify_student(
  p_student_no text, p_name text, p_code text
) returns bigint
language plpgsql stable security definer set search_path = public, extensions as $$
declare r students%rowtype;
begin
  select * into r from students where student_no = upper(trim(p_student_no));
  if r.id is null then
    raise exception '查無此學號，請先提交換組意向';
  end if;
  if lower(trim(r.name)) <> lower(coalesce(trim(p_name),'')) then
    raise exception '學號或姓名不正確';
  end if;
  if r.query_code_hash is not null
     and r.query_code_hash <> crypt(coalesce(p_code,''), r.query_code_hash) then
    raise exception '查詢碼不正確';
  end if;
  return r.id;
end $$;

-- 任何成員已離場的候選組，標記過期
create or replace function expire_stale_matches() returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  update match_groups g set status = 'expired'
  where g.status = 'pending'
    and exists (select 1 from match_members mm
                join swap_requests r on r.id = mm.request_id
                where mm.match_id = g.id and r.status <> 'open');
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ----------------------------------------------------------------- 5.1 提交
create or replace function submit_swap(
  p_name text, p_student_no text, p_phone text, p_email text,
  p_query_code text,
  p_course_id bigint, p_hold_group bigint, p_targets bigint[],
  p_note text default null
) returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare v_student bigint; v_req bigint; v_no text; v_existing students%rowtype;
begin
  v_no := upper(trim(coalesce(p_student_no,'')));

  if coalesce(trim(p_name),'') = '' or v_no = '' then
    raise exception '姓名與學號為必填';
  end if;
  if coalesce(p_query_code,'') !~ '^[0-9A-Za-z]{4,6}$' then
    raise exception '查詢碼需為 4~6 位英數字';
  end if;
  if array_length(p_targets, 1) is null then
    raise exception '請至少選擇一個心儀組別';
  end if;
  if (select course_id from course_groups where id = p_hold_group) is distinct from p_course_id then
    raise exception '目前組別不屬於所選課程';
  end if;

  -- 既有學號：必須通過姓名 + 查詢碼校驗，避免他人覆蓋
  select * into v_existing from students where student_no = v_no;
  if v_existing.id is not null then
    v_student := verify_student(v_no, p_name, p_query_code);
    update students set
      phone           = coalesce(nullif(trim(p_phone),''), phone),
      email           = coalesce(nullif(trim(p_email),''), email),
      query_code_hash = coalesce(query_code_hash, crypt(p_query_code, gen_salt('bf'))),
      updated_at      = now()
    where id = v_student;
  else
    insert into students (student_no, name, phone, email, query_code_hash)
    values (v_no, trim(p_name),
            nullif(trim(p_phone),''), nullif(trim(p_email),''),
            crypt(p_query_code, gen_salt('bf')))
    returning id into v_student;
  end if;

  -- 一課一意向：重複提交即為修改
  select id into v_req from swap_requests
  where student_id = v_student and course_id = p_course_id and status = 'open';

  if v_req is null then
    insert into swap_requests (student_id, course_id, hold_group_id, note)
    values (v_student, p_course_id, p_hold_group, nullif(trim(p_note),''))
    returning id into v_req;
  else
    update swap_requests
       set hold_group_id = p_hold_group, note = nullif(trim(p_note),'')
     where id = v_req;
    delete from swap_targets where request_id = v_req;
    -- 持有組別／目標可能已變更：直接刪掉舊候選組（而非標記過期），
    -- 否則 signature 的 unique 會擋住下一輪重新撮合出同一組合。
    delete from match_groups g
    where exists (select 1 from match_members mm
                  where mm.match_id = g.id and mm.request_id = v_req);
  end if;

  insert into swap_targets (request_id, group_id, priority)
  select v_req, u.g, u.ord
  from unnest(p_targets) with ordinality as u(g, ord)
  on conflict (request_id, group_id) do nothing;

  return v_req;
end $$;

-- ------------------------------------------------------------ 我的所有意向
create or replace function list_my_requests(
  p_student_no text, p_name text, p_code text
) returns table (
  request_id  bigint,
  course_id   bigint,
  course_code text,
  course_name text,
  term        text,
  duration    text,
  hold_group_id bigint,
  hold_label  text,
  status      text,
  note        text,
  created_at  timestamptz,
  targets     jsonb,
  match_count bigint
)
language plpgsql security definer set search_path = public as $$
declare v_student bigint;
begin
  v_student := verify_student(p_student_no, p_name, p_code);
  return query
    select r.id, r.course_id, c.code, c.name, c.term, c.duration,
           r.hold_group_id, group_label(r.hold_group_id),
           r.status::text, r.note, r.created_at,
           coalesce((
             select jsonb_agg(jsonb_build_object(
                      'group_id', t.group_id,
                      'group_no', g2.group_no,
                      'priority', t.priority,
                      'label',    group_label(t.group_id))
                    order by t.priority)
             from swap_targets t
             join course_groups g2 on g2.id = t.group_id
             where t.request_id = r.id), '[]'::jsonb),
           (select count(*) from match_members mm
            join match_groups mg on mg.id = mm.match_id
            where mm.request_id = r.id and mg.status = 'pending')
    from swap_requests r
    join courses c on c.id = r.course_id
    where r.student_id = v_student
      and r.status <> 'cancelled'
    order by (r.status = 'open') desc, r.created_at desc;
end $$;

-- ----------------------------------------------------------- 5.2 查詢匹配
create or replace function query_matches(
  p_student_no text, p_name text, p_code text
) returns table (
  match_id bigint, match_size int, matched_at timestamptz,
  course_id bigint, course_name text,
  my_request_id bigint, my_position int, my_hold text, my_gets text,
  peer_name text, peer_student_no text, peer_phone text, peer_email text,
  peer_hold text, peer_gets text, peer_position int
)
language plpgsql security definer set search_path = public as $$
declare v_student bigint;
begin
  v_student := verify_student(p_student_no, p_name, p_code);
  return query
    with mine as (
      select mm.match_id, mm.request_id, mm.gets_group_id, mm.position
      from match_members mm
      join swap_requests r on r.id = mm.request_id
      where r.student_id = v_student and r.status = 'open'
    )
    select g.id, g.size, g.created_at,
           g.course_id, c.code || ' ' || c.name,
           mine.request_id, mine.position,
           group_label(mr.hold_group_id), group_label(mine.gets_group_id),
           s.name, s.student_no, s.phone, s.email,
           group_label(pr.hold_group_id), group_label(pm.gets_group_id), pm.position
    from mine
    join match_groups  g  on g.id = mine.match_id and g.status = 'pending'
    join courses       c  on c.id = g.course_id
    join swap_requests mr on mr.id = mine.request_id
    join match_members pm on pm.match_id = g.id and pm.request_id <> mine.request_id
    join swap_requests pr on pr.id = pm.request_id and pr.status = 'open'
    join students      s  on s.id = pr.student_id
    left join swap_targets mt
           on mt.request_id = mine.request_id and mt.group_id = mine.gets_group_id
    -- 依「我自己的偏好序」排：第一志願的匹配排最前，其次才看新舊
    order by coalesce(mt.priority, 99), g.size, g.created_at desc, pm.position;
end $$;

-- --------------------------------------------------------- 5.3 結束匹配
create or replace function close_course(
  p_course_id bigint, p_student_no text, p_name text, p_code text
) returns int
language plpgsql security definer set search_path = public as $$
declare v_student bigint; v_n int;
begin
  v_student := verify_student(p_student_no, p_name, p_code);
  update swap_requests set status = 'closed', closed_at = now()
  where student_id = v_student and course_id = p_course_id and status = 'open';
  get diagnostics v_n = row_count;
  perform expire_stale_matches();
  return v_n;
end $$;

-- ------------------------------------------------------------------ 撤銷
create or replace function cancel_request(
  p_request_id bigint, p_student_no text, p_name text, p_code text
) returns int
language plpgsql security definer set search_path = public as $$
declare v_student bigint; v_n int;
begin
  v_student := verify_student(p_student_no, p_name, p_code);
  update swap_requests set status = 'cancelled', closed_at = now()
  where id = p_request_id and student_id = v_student and status = 'open';
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception '找不到可撤銷的意向';
  end if;
  perform expire_stale_matches();
  return v_n;
end $$;

-- --------------------------------------------------- 3.3.2 衝堂檢查（選配）
-- 只能比對學生在本系統登記過的其他課程，僅供參考
create or replace function check_conflicts(
  p_student_no text, p_name text, p_code text, p_group bigint
) returns table (course_code text, group_no text, detail text)
language plpgsql security definer set search_path = public as $$
declare v_student bigint; v_course bigint;
begin
  v_student := verify_student(p_student_no, p_name, p_code);
  select course_id into v_course from course_groups where id = p_group;
  return query
    with others as (
      select r.hold_group_id as gid
      from swap_requests r
      where r.student_id = v_student
        and r.status = 'open'
        and r.course_id is distinct from v_course
    )
    select c.code, g.group_no,
           wd(b.weekday) || ' ' || to_char(b.start_time,'HH24:MI') || '-' ||
           to_char(b.end_time,'HH24:MI')
    from group_sessions a
    join others o        on true
    join group_sessions b on b.group_id = o.gid
    join course_groups  g on g.id = o.gid
    join courses        c on c.id = g.course_id
    where a.group_id = p_group
      and a.weekday = b.weekday
      and a.start_time < b.end_time and b.start_time < a.end_time      -- 時段重疊
      and (a.start_date is null or b.start_date is null
           or (a.start_date <= b.end_date and b.start_date <= a.end_date))  -- 週期重疊
    group by c.code, g.group_no, b.weekday, b.start_time, b.end_time;
end $$;
