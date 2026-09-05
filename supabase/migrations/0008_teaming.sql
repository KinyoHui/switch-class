-- =====================================================================
-- 0008 · 課程組隊
--
-- 學生填滿 4 門課（每門課選一個組別），4 門完全相同者編為同一隊，6 人一隊，
-- 超過開新隊。同隊成員彼此看得到姓名、學號、手機與 Email。
--
-- 配對鍵為「4 個 group_id 的集合」：course_groups 一列已唯一決定課程編號與
-- 組別代號，其 group_sessions 決定上課時間與地點，因此 group_id 集合相同
-- ⇒ 課程編號、組別、上課地點、上課時間全部一致。
--
-- 與換組匹配不同，隊伍是「黏著」的：編入之後就固定，不會每輪重算，
-- 否則同學每 10 分鐘看到的隊友都在變。
-- =====================================================================

create or replace function team_size() returns int
language sql immutable set search_path = public as $$ select 6 $$;

create or replace function team_course_count() returns int
language sql immutable set search_path = public as $$ select 4 $$;

-- ------------------------------------------------------------ 3.7 組隊意向
create table if not exists team_requests (
  id         bigint generated always as identity primary key,
  student_id bigint not null references students(id) on delete cascade,
  signature  text not null,                    -- 'g:12-45-67-89'（group_id 排序後）
  status     swap_status not null default 'open',
  note       text,
  created_at timestamptz not null default now(),
  closed_at  timestamptz
);

-- 一位學生同時只有一筆有效組隊意向
create unique index if not exists uq_open_team_request
  on team_requests (student_id) where status = 'open';

create index if not exists idx_team_requests_sig
  on team_requests (signature) where status = 'open';

create table if not exists team_request_groups (
  request_id bigint not null references team_requests(id) on delete cascade,
  group_id   bigint not null references course_groups(id) on delete cascade,
  ord        int    not null default 1,
  primary key (request_id, group_id)
);

create index if not exists idx_team_request_groups_group
  on team_request_groups (group_id);

-- ---------------------------------------------------------------- 隊伍
create table if not exists teams (
  id         bigint generated always as identity primary key,
  signature  text not null,
  seq        int  not null,                    -- 同一組合的第幾隊，1 起算
  status     text not null default 'open',     -- open / closed
  created_at timestamptz not null default now(),
  unique (signature, seq)
);

create index if not exists idx_teams_sig on teams (signature) where status = 'open';

create table if not exists team_members (
  team_id    bigint not null references teams(id) on delete cascade,
  request_id bigint not null references team_requests(id) on delete cascade unique,
  joined_at  timestamptz not null default now(),
  primary key (team_id, request_id)
);

create index if not exists idx_team_members_request on team_members (request_id);

-- ------------------------------------------------------------ 意向的組別明細
-- 每筆意向一列，帶 4 門課的可讀標籤，供前端與隊伍卡片直接顯示
create or replace view v_team_request_detail as
select r.id as request_id,
       r.student_id,
       r.signature,
       r.status,
       jsonb_agg(
         jsonb_build_object(
           'group_id',    g.id,
           'group_no',    g.group_no,
           'course_id',   c.id,
           'course_code', c.code,
           'course_name', c.name,
           'term',        c.term,
           'label',       group_label(g.id),
           'time_label',  group_time_label(g.id)
         ) order by c.code
       ) as courses
from team_requests r
join team_request_groups tg on tg.request_id = r.id
join course_groups g on g.id = tg.group_id
join courses c on c.id = g.course_id
group by r.id, r.student_id, r.signature, r.status;

-- ------------------------------------------------------------------- 提交
create or replace function submit_team(
  p_name text, p_student_no text, p_phone text, p_email text,
  p_query_code text, p_groups bigint[], p_note text default null
) returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_student bigint; v_req bigint; v_no text; v_sig text;
  v_existing students%rowtype; v_courses int; v_valid int;
begin
  v_no := upper(trim(coalesce(p_student_no,'')));

  if coalesce(trim(p_name),'') = '' or v_no = '' then
    raise exception '姓名與學號為必填';
  end if;
  if coalesce(p_query_code,'') !~ '^[0-9A-Za-z]{4,6}$' then
    raise exception '查詢碼需為 4~6 位英數字';
  end if;

  -- 必須剛好 4 門、不重複、且分屬 4 門不同的課
  if array_length(p_groups, 1) is distinct from team_course_count() then
    raise exception '請完整選擇 % 門課程的組別', team_course_count();
  end if;
  select count(distinct g.id), count(distinct g.course_id)
    into v_valid, v_courses
  from course_groups g where g.id = any(p_groups) and g.is_active;

  if v_valid <> team_course_count() then
    raise exception '有組別不存在或已停用';
  end if;
  if v_courses <> team_course_count() then
    raise exception '同一門課只能選一個組別';
  end if;

  -- 身分：既有學號必須通過姓名 + 查詢碼校驗
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

  -- 正規化簽章：group_id 由小到大，確保「同樣 4 門課」得到同一把鍵
  select 'g:' || string_agg(x::text, '-' order by x) into v_sig
  from unnest(p_groups) as x;

  select id into v_req from team_requests
  where student_id = v_student and status = 'open';

  if v_req is null then
    insert into team_requests (student_id, signature, note)
    values (v_student, v_sig, nullif(trim(p_note),''))
    returning id into v_req;
  else
    -- 改了課程組合就得離開現在的隊伍，下一輪重新編隊
    if (select signature from team_requests where id = v_req) is distinct from v_sig then
      delete from team_members where request_id = v_req;
    end if;
    update team_requests
       set signature = v_sig, note = nullif(trim(p_note),'')
     where id = v_req;
    delete from team_request_groups where request_id = v_req;
  end if;

  insert into team_request_groups (request_id, group_id, ord)
  select v_req, u.g, u.ord
  from unnest(p_groups) with ordinality as u(g, ord)
  on conflict (request_id, group_id) do nothing;

  return v_req;
end $$;

-- --------------------------------------------------------------- 編隊
create or replace function run_teaming() returns int
language plpgsql security definer set search_path = public as $$
declare v_sig text; v_req bigint; v_team bigint; v_new int := 0;
begin
  -- 1) 已結束／撤銷的意向退出隊伍，空出名額
  delete from team_members tm
  using team_requests r
  where r.id = tm.request_id and r.status <> 'open';

  -- 2) 沒有成員的隊伍關閉，避免佔用 seq 之外還被當成有空位
  update teams t set status = 'closed'
  where t.status = 'open'
    and not exists (select 1 from team_members m where m.team_id = t.id);

  -- 3) 尚未編隊的意向，依提交先後編入
  for v_sig, v_req in
    select r.signature, r.id
    from team_requests r
    where r.status = 'open'
      and not exists (select 1 from team_members m where m.request_id = r.id)
    order by r.signature, r.created_at, r.id
  loop
    -- 先填舊隊的空位（含成員退出後空出來的），滿了才開新隊
    select t.id into v_team
    from teams t
    where t.signature = v_sig and t.status = 'open'
      and (select count(*) from team_members m where m.team_id = t.id) < team_size()
    order by t.seq
    limit 1;

    if v_team is null then
      -- 同組合只有自己一人時先不開隊，讓前端顯示「等待同課同學」
      if (select count(*) from team_requests r2
          where r2.signature = v_sig and r2.status = 'open') < 2 then
        continue;
      end if;
      insert into teams (signature, seq)
      values (v_sig, coalesce((select max(seq) from teams where signature = v_sig), 0) + 1)
      returning id into v_team;
      v_new := v_new + 1;
    end if;

    insert into team_members (team_id, request_id) values (v_team, v_req)
    on conflict do nothing;
    v_team := null;
  end loop;

  return v_new;
end $$;

-- ------------------------------------------------------------- 查詢我的隊伍
create or replace function my_team(
  p_student_no text, p_name text, p_code text
) returns table (
  request_id  bigint,
  status      text,
  note        text,
  created_at  timestamptz,
  courses     jsonb,
  team_id     bigint,
  team_seq    int,
  team_size   int,
  member_count bigint,
  waiting_same_combo bigint,
  members     jsonb
)
language plpgsql security definer set search_path = public as $$
declare v_student bigint;
begin
  v_student := verify_student(p_student_no, p_name, p_code);
  return query
    select d.request_id,
           r.status::text,
           r.note,
           r.created_at,
           d.courses,
           t.id,
           t.seq,
           team_size(),
           (select count(*) from team_members m2 where m2.team_id = t.id),
           -- 還沒編進任何隊伍、但課程組合相同的人數（含自己）
           (select count(*) from team_requests r3
             where r3.signature = r.signature and r3.status = 'open'
               and not exists (select 1 from team_members m3 where m3.request_id = r3.id)),
           coalesce((
             select jsonb_agg(jsonb_build_object(
                      'is_me',      s2.id = v_student,
                      'name',       s2.name,
                      'student_no', s2.student_no,
                      'phone',      s2.phone,
                      'email',      s2.email,
                      'joined_at',  m.joined_at)
                    order by m.joined_at, s2.student_no)
             from team_members m
             join team_requests r2 on r2.id = m.request_id and r2.status = 'open'
             join students s2 on s2.id = r2.student_id
             where m.team_id = t.id), '[]'::jsonb)
    from team_requests r
    join v_team_request_detail d on d.request_id = r.id
    left join team_members tm on tm.request_id = r.id
    left join teams t on t.id = tm.team_id and t.status = 'open'
    where r.student_id = v_student
      and r.status <> 'cancelled'
    order by (r.status = 'open') desc, r.created_at desc;
end $$;

-- ------------------------------------------------------------ 離隊／撤銷
create or replace function leave_team(
  p_student_no text, p_name text, p_code text
) returns int
language plpgsql security definer set search_path = public as $$
declare v_student bigint; v_n int;
begin
  v_student := verify_student(p_student_no, p_name, p_code);
  update team_requests set status = 'cancelled', closed_at = now()
  where student_id = v_student and status = 'open';
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception '找不到可撤銷的組隊意向';
  end if;
  -- 立刻退出隊伍並騰出名額，不必等下一輪
  perform run_teaming();
  return v_n;
end $$;

-- --------------------------------------------------------------- 定時任務
-- run_matching() 之外的第二條排程；兩者互不相干，分開跑比較好定位問題
create or replace function admin_run_teaming() returns int
language plpgsql security definer set search_path = public as $$
begin
  perform assert_admin();
  return run_teaming();
end $$;

-- 管理頁總覽：每種課程組合的隊伍與人數
create or replace function admin_team_overview()
returns table (
  signature text, courses jsonb, team_count bigint,
  member_count bigint, waiting bigint
)
language plpgsql security definer set search_path = public as $$
begin
  perform assert_admin();
  return query
    select r.signature,
           (select d.courses from v_team_request_detail d
             where d.request_id = min(r.id)),
           (select count(*) from teams t
             where t.signature = r.signature and t.status = 'open'),
           count(*) filter (where exists (
             select 1 from team_members m where m.request_id = r.id)),
           count(*) filter (where not exists (
             select 1 from team_members m where m.request_id = r.id))
    from team_requests r
    where r.status = 'open'
    group by r.signature
    order by count(*) desc, r.signature;
end $$;

-- ------------------------------------------------------- 安全（延續 0005）
alter table team_requests       enable row level security;
alter table team_request_groups enable row level security;
alter table teams               enable row level security;
alter table team_members        enable row level security;

-- 個資表：不建 policy，anon/authenticated 一律走 RPC
revoke all on table team_requests, team_request_groups, teams, team_members
  from anon, authenticated;
revoke all on table v_team_request_detail from anon, authenticated;

revoke execute on function
  submit_team(text,text,text,text,text,bigint[],text),
  my_team(text,text,text),
  leave_team(text,text,text),
  run_teaming(), team_size(), team_course_count(),
  admin_run_teaming(), admin_team_overview()
  from public, anon, authenticated;

grant execute on function
  submit_team(text,text,text,text,text,bigint[],text),
  my_team(text,text,text),
  leave_team(text,text,text),
  team_size(), team_course_count()
  to anon, authenticated;

grant execute on function
  admin_run_teaming(), admin_team_overview()
  to authenticated;

-- 排程（與 swap-matching 並行）：
--   select cron.schedule('team-matching', '*/10 * * * *',
--                        $$ select public.run_teaming() $$);
