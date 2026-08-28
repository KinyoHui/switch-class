# 換組意向匹配系統 — 技術方案

適用場景：同一門課程在不同組別（T01 / T02 / T03…）之間互換。
技術棧沿用 aion2：Vue 3 + Vite + Tailwind + Supabase + PWA，純靜態部署，無自建後端。

---

## 一、從實際課表得到的三個結論

以 HKMU 課表為例：

```
ENVR 8951SCF 中國特色的可持續發展（二○二六年秋季學期）  修讀期：一學期
序 組別  類別      日期及時間          地點          開始/結束日期
1  T03  FT 導修課  Sun 11:00 - 11:50  IOH / F0201   06/09/2026 - 11/10/2026
                                                    25/10/2026 - 29/11/2026
2       FT 面授課  Sun 09:00 - 10:50  IOH / F0201   06/09/2026 - 11/10/2026
                                                    25/10/2026 - 29/11/2026
```

1. **交換單位是組別**，不是課程。學生持有 T03，想換到 T01 或 T02。
2. **一個組別包含多節課**，各有自己的類別、星期時段、地點、開課日期區間。所以「組別 → 節次」必須拆成兩層，不能塞在同一行。
3. **地點是「校區代碼 / 房號」**（IOH / F0201），校區代碼是全校共用的枚舉（HKMU、MUPC、JCC、JCPC、IOH、HPLC、MCC、MUT），值得單獨建表，顯示時能展開成全稱與地址。

由此帶來一條原本拿不到的約束：**同一學生、同一門課，最多只能有一筆有效意向**——你手上就一個組別，不可能同時持有兩個。這條唯一索引能擋掉一整類髒資料。

---

## 二、總體架構

```
┌─────────────────────────────┐
│  瀏覽器（Vue 3 SPA / PWA）  │
│  提交頁 / 查詢頁 / 管理頁   │
└──────────────┬──────────────┘
               │ supabase-js（anon key）
               │ 只呼叫 RPC + 讀公開課程表
┌──────────────▼──────────────┐
│        Supabase             │
│  Postgres  +  RLS           │
│  RPC（SECURITY DEFINER）    │
│  pg_cron  每 10 分鐘匹配    │
└─────────────────────────────┘
```

與 aion2 的關鍵差異：aion2 用 anon key 直接對表 CRUD。本系統存姓名、學號、手機號，屬個資，**必須**改成 RPC + RLS，詳見第六節。

---

## 三、資料模型

### 3.1 校區

```sql
create table campuses (
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
 ('MUT', '都大中心','香港九龍紅磡紅鸞道18號');
```

### 3.2 課程與組別

```sql
create table courses (
  id         bigint generated always as identity primary key,
  code       text not null,              -- ENVR 8951SCF
  name       text not null,              -- 中國特色的可持續發展
  term       text not null,              -- 2026-秋
  duration   text,                       -- 修讀期：一學期 / 兩學期
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  unique (code, term)
);

create table course_groups (
  id        bigint generated always as identity primary key,
  course_id bigint not null references courses(id) on delete cascade,
  group_no  text   not null,             -- T01 / T02 / T03
  capacity  int,
  is_active boolean not null default true,
  unique (course_id, group_no)
);

create index on course_groups (course_id) where is_active;
```

### 3.3 節次（地點與時間的真正落點）

課表中一行若有兩段開課日期，就拆成兩筆；前端顯示時再按「類別 + 時段 + 地點」合併呈現。這樣查詢和衝堂判斷都最單純。

```sql
create table group_sessions (
  id          bigint generated always as identity primary key,
  group_id    bigint not null references course_groups(id) on delete cascade,
  seq         int    not null default 1,     -- 課表中的序號
  kind        text,                          -- FT 導修課 / FT 面授課
  weekday     smallint not null,             -- 0=Sun … 6=Sat
  start_time  time not null,                 -- 11:00
  end_time    time not null,                 -- 11:50
  campus_code text references campuses(code),-- IOH
  room        text,                          -- F0201
  start_date  date,                          -- 2026-09-06
  end_date    date,                          -- 2026-10-11
  remark      text
);

create index on group_sessions (group_id);
```

上例的 T03 會展開成 4 筆：導修課 × 2 段日期、面授課 × 2 段日期。

方便前端一次取用的視圖：

```sql
create view v_group_detail as
select g.id            as group_id,
       g.course_id,
       g.group_no,
       c.code          as course_code,
       c.name          as course_name,
       c.term,
       jsonb_agg(
         jsonb_build_object(
           'kind', s.kind,
           'weekday', s.weekday,
           'time', to_char(s.start_time,'HH24:MI') || ' - ' || to_char(s.end_time,'HH24:MI'),
           'campus', s.campus_code,
           'campus_name', cp.name,
           'room', s.room,
           'date_range', to_char(s.start_date,'DD/MM/YYYY') || ' - ' || to_char(s.end_date,'DD/MM/YYYY'),
           'remark', s.remark
         ) order by s.seq, s.start_date
       ) as sessions
from course_groups g
join courses c   on c.id = g.course_id
left join group_sessions s on s.group_id = g.id
left join campuses cp on cp.code = s.campus_code
where g.is_active
group by g.id, g.course_id, g.group_no, c.code, c.name, c.term;
```

### 3.3.1 時間標籤（給前端與匹配結果共用）

學生在選「可接受的組別」時，必須看得到該組的上課時間——MyHKMU 只顯示自己那一組的課表，其他組的時間他無從得知。所以任何出現組別代號的地方，一律附時間與地點。

```sql
create or replace function wd(n smallint) returns text
language sql immutable as $$
  select (array['週日','週一','週二','週三','週四','週五','週六'])[n + 1]
$$;

-- 回傳如：面授課 週六 09:00-11:30 · IOH/F0201 ｜ 導修課 週六 11:40-12:30 · IOH/F0201
create or replace function group_time_label(p_group bigint) returns text
language sql stable as $$
  select string_agg(x.txt, ' ｜ ' order by x.ord, x.wk, x.st)
  from (
    select min(s.seq) as ord, s.weekday as wk, s.start_time as st,
           coalesce(s.kind, '') || ' ' || wd(s.weekday) || ' ' ||
           to_char(s.start_time, 'HH24:MI') || '-' || to_char(s.end_time, 'HH24:MI') ||
           ' · ' || coalesce(s.campus_code, '') || '/' || coalesce(s.room, '') as txt
    from group_sessions s
    where s.group_id = p_group
    group by s.kind, s.weekday, s.start_time, s.end_time, s.campus_code, s.room
  ) x
$$;
```

`group by` 順帶把同一時段的兩段開課日期合併成一行——這正是 3.3 提到的「顯示時再合併」。

### 3.3.2 衝堂檢查（選配，但很值錢）

學生換組最怕換到跟別的課撞的時段。時間欄位是結構化的，判斷成本幾乎為零：

```sql
create or replace function check_conflicts(
  p_student_no text, p_name text, p_group bigint
) returns table (course_code text, group_no text, detail text)
language sql security definer set search_path = public as $$
  with me as (
    select id from students where student_no = trim(p_student_no) and name = trim(p_name)
  ),
  others as (                       -- 該生在本系統登記過的其他課程持有組別
    select r.hold_group_id as gid, r.course_id
    from swap_requests r
    where r.student_id = (select id from me)
      and r.status = 'open'
      and r.course_id <> (select course_id from course_groups where id = p_group)
  )
  select c.code, g.group_no,
         wd(b.weekday) || ' ' || to_char(b.start_time,'HH24:MI') || '-' ||
         to_char(b.end_time,'HH24:MI')
  from group_sessions a
  join others o on true
  join group_sessions b on b.group_id = o.gid
  join course_groups  g on g.id = o.gid
  join courses        c on c.id = g.course_id
  where a.group_id = p_group
    and a.weekday = b.weekday
    and a.start_time < b.end_time and b.start_time < a.end_time   -- 時段重疊
    and a.start_date <= b.end_date and b.start_date <= a.end_date -- 週期重疊
  group by c.code, g.group_no, b.weekday, b.start_time, b.end_time;
$$;
```

限制：只能比對學生在本系統登記過的課程，蓋不到他其他沒掛單的課。所以文案要寫「僅供參考，請自行核對完整課表」，不能給出保證。

### 3.4 學生

```sql
create table students (
  id         bigint generated always as identity primary key,
  student_no text not null unique,
  name       text not null,
  phone      text,
  email      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

同一學號重複提交 → upsert，更新姓名與聯絡方式。

### 3.5 換組意向（核心）

一筆意向 = 一門課的「我持有 X 組，可接受 Y / Z 組」。可接受的組別放在關聯表，支援多選與優先序。

```sql
create type swap_status as enum ('open', 'closed', 'cancelled');

create table swap_requests (
  id            bigint generated always as identity primary key,
  student_id    bigint not null references students(id) on delete cascade,
  course_id     bigint not null references courses(id),
  hold_group_id bigint not null references course_groups(id),
  status        swap_status not null default 'open',
  note          text,
  created_at    timestamptz not null default now(),
  closed_at     timestamptz
);

-- 同一學生同一門課只能有一筆有效意向
create unique index uq_open_request
  on swap_requests (student_id, course_id) where status = 'open';

create index on swap_requests (course_id) where status = 'open';
create index on swap_requests (hold_group_id) where status = 'open';

create table swap_targets (
  request_id bigint not null references swap_requests(id) on delete cascade,
  group_id   bigint not null references course_groups(id),
  priority   int    not null default 1,        -- 1 = 最想要
  primary key (request_id, group_id)
);

create index on swap_targets (group_id);
```

用觸發器保證目標組別與持有組別同課、且不相同：

```sql
create or replace function check_target_group() returns trigger
language plpgsql as $$
declare v_course bigint; v_hold bigint;
begin
  select course_id, hold_group_id into v_course, v_hold
  from swap_requests where id = new.request_id;

  if new.group_id = v_hold then
    raise exception '目標組別不能與目前組別相同';
  end if;
  if (select course_id from course_groups where id = new.group_id) <> v_course then
    raise exception '目標組別必須屬於同一門課程';
  end if;
  return new;
end $$;

create trigger trg_check_target
before insert or update on swap_targets
for each row execute function check_target_group();
```

### 3.6 匹配結果

用 group + members 結構，兩人互換與三人環換共用一套表，日後擴到四人環不必改結構。

```sql
create table match_groups (
  id         bigint generated always as identity primary key,
  course_id  bigint not null references courses(id),
  size       int  not null,                    -- 2 = 互換，3 = 環換
  signature  text not null unique,             -- 成員 request_id 排序拼接，冪等去重
  status     text not null default 'pending',  -- pending / expired
  created_at timestamptz not null default now()
);

create table match_members (
  match_id      bigint not null references match_groups(id) on delete cascade,
  request_id    bigint not null references swap_requests(id) on delete cascade,
  position      int    not null,               -- 環中順序
  gets_group_id bigint not null references course_groups(id),  -- 這次換到哪一組
  primary key (match_id, request_id)
);

create index on match_members (request_id);
```

`signature` 的 unique 是冪等性關鍵——cron 每 10 分鐘重跑，同一組匹配不會重複寫入。

---

## 四、匹配演算法

### 4.1 兩人互換

同課程內，A 接受 B 的組，且 B 接受 A 的組。

```sql
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
),
g as (
  insert into match_groups (course_id, size, signature)
  select course_id, 2, a_id || '-' || b_id from pairs
  on conflict (signature) do nothing
  returning id, signature
)
insert into match_members (match_id, request_id, position, gets_group_id)
select g.id, p.a_id, 1, p.a_gets from g join pairs p
       on g.signature = p.a_id || '-' || p.b_id
union all
select g.id, p.b_id, 2, p.b_gets from g join pairs p
       on g.signature = p.a_id || '-' || p.b_id;
```

### 4.2 三人環換

A 拿 B 的組、B 拿 C 的組、C 拿 A 的組。三個組別的課程通常只有 T01/T02/T03 幾個，環換命中率相當可觀，建議一開始就上。

```sql
with tri as (
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
    and a.id < b.id and a.id < c.id             -- 固定最小 id 為環起點，避免旋轉重複
)
-- 之後的 insert 與 4.1 同構，寫三筆 match_members
```

### 4.3 定時任務

```sql
create or replace function run_matching() returns int
language plpgsql security definer set search_path = public as $$
declare v_new int;
begin
  -- 1) 清理：任何成員已關閉的候選組，標記過期
  update match_groups g set status = 'expired'
  where g.status = 'pending'
    and exists (select 1 from match_members mm
                join swap_requests r on r.id = mm.request_id
                where mm.match_id = g.id and r.status <> 'open');

  -- 2) 執行 4.1 兩人互換
  -- 3) 執行 4.2 三人環換

  select count(*) into v_new
  from match_groups where created_at > now() - interval '1 minute';
  return v_new;
end $$;
```

排程（Supabase 控制台 Database → Extensions 先啟用 `pg_cron`）：

```sql
select cron.schedule('swap-matching', '*/10 * * * *',
                     $$ select public.run_matching() $$);
```

**為什麼批次而非即時**：每 10 分鐘統一撮合比「插入即匹配」公平，避免早提交幾秒就搶到唯一對家。這點寫進頁面說明，可以省掉很多爭議。想要即時感的話，前端用 Supabase Realtime 訂閱 `match_members` 即可在匹配產生時彈出提示。

### 4.4 匹配是候選，不是成交

系統不鎖定任何人。同一筆意向可同時出現在多個候選組（正是「查詢結果可以是多個」的來源）。使用者拿到對方聯絡方式後自行到 MyHKMU 完成換組，成功後回來按「結束匹配」，該課程意向關閉、相關候選組連帶作廢。

---

## 五、對外介面（RPC）

前端只呼叫這幾個函式，加上直讀 `courses` 與 `v_group_detail`。全部 `SECURITY DEFINER`。

| 函式 | 用途 |
|---|---|
| `submit_swap(name, student_no, phone, email, course_id, hold_group_id, target_group_ids[], note)` | upsert 學生 + 建立／覆蓋該課程的意向 |
| `list_my_requests(student_no, name)` | 我的所有意向與狀態 |
| `query_matches(student_no, name)` | 查匹配結果（可多筆），含對方聯絡方式 |
| `close_course(course_id, student_no, name)` | **結束匹配**：關閉該課程意向，不再參與撮合 |
| `cancel_request(request_id, student_no, name)` | 撤銷 |

### 5.1 提交

因為有「一課一意向」的唯一索引，重複提交同一門課視為修改，直接覆蓋目標組別。

```sql
create or replace function submit_swap(
  p_name text, p_student_no text, p_phone text, p_email text,
  p_course_id bigint, p_hold_group bigint, p_targets bigint[],
  p_note text default null
) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_student bigint; v_req bigint;
begin
  if coalesce(trim(p_name),'') = '' or coalesce(trim(p_student_no),'') = '' then
    raise exception '姓名與學號為必填';
  end if;
  if array_length(p_targets, 1) is null then
    raise exception '請至少選擇一個心儀組別';
  end if;

  insert into students (student_no, name, phone, email)
  values (trim(p_student_no), trim(p_name),
          nullif(trim(p_phone),''), nullif(trim(p_email),''))
  on conflict (student_no) do update
    set name  = excluded.name,
        phone = coalesce(excluded.phone, students.phone),
        email = coalesce(excluded.email, students.email),
        updated_at = now()
  returning id into v_student;

  select id into v_req from swap_requests
  where student_id = v_student and course_id = p_course_id and status = 'open';

  if v_req is null then
    insert into swap_requests (student_id, course_id, hold_group_id, note)
    values (v_student, p_course_id, p_hold_group, p_note)
    returning id into v_req;
  else
    update swap_requests set hold_group_id = p_hold_group, note = p_note
    where id = v_req;
    delete from swap_targets where request_id = v_req;
  end if;

  insert into swap_targets (request_id, group_id, priority)
  select v_req, g, ord from unnest(p_targets) with ordinality as u(g, ord);

  return v_req;
end $$;
```

### 5.2 查詢匹配

```sql
-- 匹配結果同樣要帶時間，否則使用者看到「T01」還是不知道換過去是幾點
create or replace function group_label(p_id bigint) returns text
language sql stable as $$
  select g.group_no || '（' || coalesce(group_time_label(g.id), '時間待定') || '）'
  from course_groups g where g.id = p_id
$$;

create or replace function query_matches(p_student_no text, p_name text)
returns table (
  match_id bigint, match_size int, matched_at timestamptz,
  course_name text,
  my_hold text, my_gets text,
  peer_name text, peer_student_no text, peer_phone text, peer_email text,
  peer_hold text, peer_gets text, peer_position int
)
language sql security definer set search_path = public as $$
  with me as (
    select id from students
    where student_no = trim(p_student_no) and name = trim(p_name)
  ),
  mine as (
    select mm.match_id, mm.request_id, mm.gets_group_id
    from match_members mm
    join swap_requests r on r.id = mm.request_id
    where r.student_id = (select id from me) and r.status = 'open'
  )
  select g.id, g.size, g.created_at,
         c.code || ' ' || c.name,
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
  -- 依「我自己的偏好序」排：第一志願的匹配排最前，其次才看新舊
  left join swap_targets mt
         on mt.request_id = mine.request_id and mt.group_id = mine.gets_group_id
  order by coalesce(mt.priority, 99), g.size, g.created_at desc, pm.position;
$$;
```

### 5.3 結束匹配

```sql
create or replace function close_course(p_course_id bigint, p_student_no text, p_name text)
returns int
language plpgsql security definer set search_path = public as $$
declare v_student bigint; v_n int;
begin
  select id into v_student from students
  where student_no = trim(p_student_no) and name = trim(p_name);
  if v_student is null then raise exception '學號或姓名不正確'; end if;

  update swap_requests set status = 'closed', closed_at = now()
  where student_id = v_student and course_id = p_course_id and status = 'open';
  get diagnostics v_n = row_count;

  update match_groups g set status = 'expired'
  where g.status = 'pending'
    and exists (select 1 from match_members mm
                join swap_requests r on r.id = mm.request_id
                where mm.match_id = g.id and r.status <> 'open');
  return v_n;
end $$;
```

---

## 六、安全與隱私

aion2 是 anon key 直連表。本系統存的是真實姓名、學號、手機號，照搬等於任何人都能把全校聯絡方式拉走。

```sql
alter table courses        enable row level security;
alter table course_groups  enable row level security;
alter table group_sessions enable row level security;
alter table campuses       enable row level security;
alter table students       enable row level security;
alter table swap_requests  enable row level security;
alter table swap_targets   enable row level security;
alter table match_groups   enable row level security;
alter table match_members  enable row level security;

-- 課程資料公開讀
create policy "read courses"  on courses        for select to anon using (is_active);
create policy "read groups"   on course_groups  for select to anon using (is_active);
create policy "read sessions" on group_sessions for select to anon using (true);
create policy "read campuses" on campuses       for select to anon using (true);

-- 其餘表不建 anon policy → 完全無法直接存取
revoke all on students, swap_requests, swap_targets, match_groups, match_members from anon;

grant execute on function submit_swap, list_my_requests, query_matches,
                          cancel_request, close_course to anon;
revoke execute on function run_matching from anon, authenticated;
```

`SECURITY DEFINER` 函式以擁有者身分執行、繞過 RLS，所以 RPC 仍能正常讀寫。個資只能透過受控函式按規則吐出。

**身分校驗**：RPC 要求學號 + 姓名同時匹配才回資料。這比只給學號強，但同學之間容易同時知道兩者。建議加一個 **4~6 位查詢碼**，首次提交時自設，用 `pgcrypto` 的 `crypt()` 存 hash，查詢時驗證。改動很小，效果明顯。

**其他**：
- 聯絡方式只在匹配成立後、且只對同組成員可見；列表頁一律不顯示他人聯絡方式。
- 前端可掛 Cloudflare Turnstile 防灌水。
- 頁面底部聲明：資料僅用於換組配對，學期結束後清除。
- 學期結束執行 `delete from students;`（級聯清掉意向與匹配）。

---

## 七、前端頁面

沿用 aion2 的深色 + cyan 風格，`App.vue` 改成三個 Tab。

### 7.1 提交頁

```
姓名 *          [__________]
學號 *          [__________]
手機號          [__________]   ← 選填
Email           [__________]   ← 選填
───────────────────────────────────────
課程            [ ENVR 8951SCF 中國特色的可持續發展 ▾ ]

我目前的組別（單選）
  ┌───────────────────────────────────────────────┐
  │ ○ T01    面授課  週六 09:00-11:30  JCC / A0305 │
  │          導修課  週六 11:40-12:30  JCC / A0305 │
  │          06/09/2026-11/10/2026、25/10-29/11    │
  ├───────────────────────────────────────────────┤
  │ ● T03    面授課  週日 09:00-10:50  IOH / F0201 │
  │          導修課  週日 11:00-11:50  IOH / F0201 │
  │          06/09/2026-11/10/2026、25/10-29/11    │
  └───────────────────────────────────────────────┘

我可接受的組別（多選，可拖曳排優先序）— 卡片格式與上方完全相同
  ┌───────────────────────────────────────────────┐
  │ ☑ T01    面授課  週六 09:00-11:30  JCC / A0305 │  ← 時間必須完整顯示
  │          導修課  週六 11:40-12:30  JCC / A0305 │
  │          改動：週日 → 週六 ，IOH → JCC          │  ← 與現有組別的差異
  ├───────────────────────────────────────────────┤
  │ ☑ T02    面授課  週二 14:00-16:30  MCC / B0104 │
  │          ⚠ 可能與 COMP 8010 T02 衝堂（週二 15:00-17:00）│
  └───────────────────────────────────────────────┘
───────────────────────────────────────
備註（選填）    [__________]
              [ 提交 ]   [ 提交並換下一門課 ]
```

要點：
- **兩區的卡片格式一致**。使用者選「可接受的組別」時，正是最需要時間資訊的時刻——他在 MyHKMU 看不到其他組的課表，這個頁面是他唯一的資訊來源。只給一個 `T01` 代號等於沒給。
- 每張卡列出該組**全部節次**：類別、星期時段、校區/房號、開課日期區間。同一時段的多段日期合併成一行。
- 校區代碼旁顯示全稱與地址 tooltip（`IOH – 香港都會大學賽馬會健康護理學院，九龍何文田常盛街1號`）。跨校區是換組的重要考量，別讓使用者去對照上方那張代碼表。
- 目標卡片標示**與現有組別的差異**（星期不同、校區不同），一眼看出換過去有什麼變化。
- 呼叫 `check_conflicts` 標出可能衝堂的組別，加「僅供參考」字樣。
- 已選的組別自動從「可接受」清單中隱藏。
- **可接受的組別是多選，選愈多成交機率愈高**，頁面上要明說這一點。附一個「除目前組別外全選」的快捷鍵——很多學生只是想避開某個時段，其餘都無所謂。
- 拖曳排序決定 `swap_targets.priority`，第一志願排最前；匹配結果會依此排序呈現。不想排序的人維持預設順序即可，不強制。
- 至少選一個，否則 `submit_swap` 會擋下來。
- 姓名／學號存 localStorage，連續提交多門課不用重打。
- 一門課只有一組時，直接提示「此課程僅開設一個組別，無法換組」。

### 7.2 查詢頁

輸入學號 + 姓名，顯示兩塊：

**我的意向**（`list_my_requests`）— 按課程分組，每組顯示持有組別、可接受組別、狀態、提交時間，附「修改」「撤銷」，以及右上角的 **「結束此課程匹配」**。

**匹配結果**（`query_matches`）— 卡片列表，可多筆。每卡顯示：
- 對方姓名、學號、手機、Email（一鍵複製）
- 這次換組的流向，**兩邊都帶時間**：
  `你 T03（週日 09:00-10:50 IOH/F0201）→ 對方 T01（週六 09:00-11:30 JCC/A0305）`
  環換則畫成 `你 → 甲 → 乙 → 你`，每個節點同樣附時間地點
- 提示：聯繫確認後請到 MyHKMU 完成換組，完成後回來按「結束此課程匹配」

### 7.3 管理頁

左課程、右組別的雙欄結構，加節次編輯。重點是**批次匯入**：課程／組別／節次手動建不現實，做一個貼上課表文字自動解析的入口（正則抓 `T\d+`、`Sun 11:00 - 11:50`、`IOH / F0201`、`06/09/2026 - 11/10/2026`），或走 CSV。aion2 已經引了 `tesseract.js`，若只有截圖也能沿用同一套 OCR 再解析。

管理頁請走 Supabase Auth 建管理員帳號，別用前端硬編碼密碼——那等於公開。

---

## 八、部署

| 項目 | 做法 |
|---|---|
| 前端 | `vite build` → Vercel / Netlify / Cloudflare Pages，靜態託管 |
| 資料庫 | Supabase 專案，執行本文 SQL |
| 排程 | Supabase 內建 pg_cron，無需額外服務 |
| 環境變數 | `VITE_SUPABASE_URL` / `VITE_SUPABASE_KEY`，沿用 aion2 的 `.env` |
| PWA | 沿用 `vite-plugin-pwa`，手機可加到桌面 |

注意：Supabase 免費專案閒置 7 天會暫停，pg_cron 隨之停擺。換組高峰期建議升 Pro，或用 GitHub Actions 每 10 分鐘打一次 RPC 兼作保活。

---

## 九、開發順序

1. 建表 + 觸發器 + 視圖，手動塞 ENVR 8951SCF 的 T01/T02/T03 當種子資料
2. 寫 `run_matching()`，在 SQL Editor 造資料驗證兩人互換與三人環換
3. 五個 RPC + RLS + 授權，逐個測
4. 提交頁（課程下拉 → 組別卡 radio → 目標多選）
5. 查詢頁（我的意向 + 匹配結果 + 結束匹配）
6. 管理頁 + 課表批次匯入
7. 掛 pg_cron，觀察一輪
8. 小範圍試用 → 開放

單人開發約 3~5 天可跑通。

---

## 十、待確認

1. **要不要支援跨課程互換？** 目前設計鎖定同課程換組。若需要「我退選 A 課、想要 B 課，跟人對換」，把 4.1 的 `b.course_id = a.course_id` 條件拿掉、`swap_targets` 的同課檢查放寬即可，表結構不用改。
2. **三人環換做不做？** 建議做。組別數少的課程，兩人互撞機率低，環換能明顯提升成交率。
3. **課表資料怎麼進 DB？** 有教務系統的匯出檔最好；只有 MyHKMU 網頁的話，貼上文字自動解析是最省力的路徑。
4. **要不要查詢碼？** 只靠學號 + 姓名保護個資偏弱，建議加。
5. **預估規模？** 幾百人以內 Supabase 免費層綽綽有餘。
6. **兩學期以上的課程怎麼處理？** 課表只列第一學期時間，第二學期另行公布。目前用 `courses.duration` 標記，前端加提示；若要精確管理需再拆學期維度。
