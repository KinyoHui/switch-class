-- =====================================================================
-- 0001 · 基礎資料表
-- 對應設計文件第三節「資料模型」
-- =====================================================================

-- Supabase 已把 pgcrypto 裝在 extensions schema；純 Postgres 則在此建到 public。
-- 用到 crypt()/gen_salt() 的函式 search_path 會同時掛上 public 與 extensions。
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- 3.1 校區
create table if not exists campuses (
  code    text primary key,        -- IOH
  name    text not null,           -- 香港都會大學賽馬會健康護理學院
  address text                     -- 九龍何文田常盛街1號
);

insert into campuses (code, name, address) values
 ('HKMU','香港都會大學','九龍何文田牧愛街30號'),
 ('MUPC','香港都會大學電腦實驗室',null),
 ('JCC', '香港都會大學賽馬會校園','九龍何文田忠孝街81號'),
 ('JCPC','香港都會大學賽馬會校園電腦實驗室',null),
 ('IOH', '香港都會大學賽馬會健康護理學院','九龍何文田常盛街1號'),
 ('HPLC','何文田廣場學習中心','九龍何文田佛光街80號何文田廣場地下11號舖'),
 ('MCC', '香港都會大學荔景校園','新界葵涌荔景山道201至203號'),
 ('MUT', '都大中心','香港九龍紅磡紅鸞道18號')
on conflict (code) do update
  set name = excluded.name, address = excluded.address;

-- ------------------------------------------------------- 3.2 課程與組別
create table if not exists courses (
  id         bigint generated always as identity primary key,
  code       text not null,              -- ENVR 8951SCF
  name       text not null,              -- 中國特色的可持續發展
  term       text not null,              -- 2026-秋
  duration   text,                       -- 修讀期：一學期 / 兩學期
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  unique (code, term)
);

create table if not exists course_groups (
  id        bigint generated always as identity primary key,
  course_id bigint not null references courses(id) on delete cascade,
  group_no  text   not null,             -- T01 / T02 / T03
  capacity  int,
  is_active boolean not null default true,
  unique (course_id, group_no)
);

create index if not exists idx_course_groups_course
  on course_groups (course_id) where is_active;

-- ------------------------------------------------------------- 3.3 節次
create table if not exists group_sessions (
  id          bigint generated always as identity primary key,
  group_id    bigint not null references course_groups(id) on delete cascade,
  seq         int    not null default 1,     -- 課表中的序號
  kind        text,                          -- FT 導修課 / FT 面授課
  weekday     smallint not null,             -- 0=Sun … 6=Sat
  start_time  time not null,
  end_time    time not null,
  campus_code text references campuses(code),
  room        text,
  start_date  date,
  end_date    date,
  remark      text,
  constraint group_sessions_weekday_chk check (weekday between 0 and 6),
  constraint group_sessions_time_chk    check (end_time > start_time)
);

create index if not exists idx_group_sessions_group on group_sessions (group_id);

-- ------------------------------------------------------------- 3.4 學生
create table if not exists students (
  id              bigint generated always as identity primary key,
  student_no      text not null unique,
  name            text not null,
  phone           text,
  email           text,
  -- 查詢碼（設計文件第六節建議項）：4~6 位，以 pgcrypto crypt() 存 hash
  query_code_hash text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- ------------------------------------------------------- 3.5 換組意向
do $$ begin
  create type swap_status as enum ('open', 'closed', 'cancelled');
exception when duplicate_object then null;
end $$;

create table if not exists swap_requests (
  id            bigint generated always as identity primary key,
  student_id    bigint not null references students(id) on delete cascade,
  course_id     bigint not null references courses(id) on delete cascade,
  hold_group_id bigint not null references course_groups(id) on delete cascade,
  status        swap_status not null default 'open',
  note          text,
  created_at    timestamptz not null default now(),
  closed_at     timestamptz
);

-- 同一學生同一門課只能有一筆有效意向
create unique index if not exists uq_open_request
  on swap_requests (student_id, course_id) where status = 'open';

create index if not exists idx_swap_requests_course
  on swap_requests (course_id) where status = 'open';
create index if not exists idx_swap_requests_hold
  on swap_requests (hold_group_id) where status = 'open';

create table if not exists swap_targets (
  request_id bigint not null references swap_requests(id) on delete cascade,
  group_id   bigint not null references course_groups(id) on delete cascade,
  priority   int    not null default 1,        -- 1 = 最想要
  primary key (request_id, group_id)
);

create index if not exists idx_swap_targets_group on swap_targets (group_id);

-- 目標組別必須與持有組別同課、且不相同
create or replace function check_target_group() returns trigger
language plpgsql set search_path = public as $$
declare v_course bigint; v_hold bigint;
begin
  select course_id, hold_group_id into v_course, v_hold
  from swap_requests where id = new.request_id;

  if new.group_id = v_hold then
    raise exception '目標組別不能與目前組別相同';
  end if;
  if (select course_id from course_groups where id = new.group_id) is distinct from v_course then
    raise exception '目標組別必須屬於同一門課程';
  end if;
  return new;
end $$;

drop trigger if exists trg_check_target on swap_targets;
create trigger trg_check_target
before insert or update on swap_targets
for each row execute function check_target_group();

-- ------------------------------------------------------- 3.6 匹配結果
create table if not exists match_groups (
  id         bigint generated always as identity primary key,
  course_id  bigint not null references courses(id) on delete cascade,
  size       int  not null,                    -- 2 = 互換，3 = 環換
  signature  text not null unique,             -- 冪等去重鍵
  status     text not null default 'pending',  -- pending / expired
  created_at timestamptz not null default now()
);

create table if not exists match_members (
  match_id      bigint not null references match_groups(id) on delete cascade,
  request_id    bigint not null references swap_requests(id) on delete cascade,
  position      int    not null,               -- 環中順序
  gets_group_id bigint not null references course_groups(id) on delete cascade,
  primary key (match_id, request_id)
);

create index if not exists idx_match_members_request on match_members (request_id);
create index if not exists idx_match_groups_pending
  on match_groups (course_id) where status = 'pending';

-- --------------------------------------------------------- 管理員名單
-- 管理頁走 Supabase Auth；此表決定哪個帳號有管理權限
create table if not exists admins (
  user_id    uuid primary key,
  email      text,
  created_at timestamptz not null default now()
);
