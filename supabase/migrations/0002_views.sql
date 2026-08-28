-- =====================================================================
-- 0002 · 顯示用的視圖與標籤函式
-- 設計文件 3.3 / 3.3.1：任何出現組別代號的地方，一律附時間與地點
-- =====================================================================

create or replace function wd(n smallint) returns text
language sql immutable set search_path = public as $$
  select (array['週日','週一','週二','週三','週四','週五','週六'])[n + 1]
$$;

-- 把「同一時段的多段開課日期」合併成一列，這是 3.3 說的「顯示時再合併」
create or replace view v_group_session_merged as
select s.group_id,
       min(s.seq)                                  as ord,
       s.kind,
       s.weekday,
       s.start_time,
       s.end_time,
       s.campus_code,
       s.room,
       array_agg(
         to_char(s.start_date,'DD/MM/YYYY') || ' - ' || to_char(s.end_date,'DD/MM/YYYY')
         order by s.start_date
       ) filter (where s.start_date is not null)   as date_ranges,
       min(s.start_date)                           as first_date,
       max(s.end_date)                             as last_date,
       nullif(string_agg(distinct s.remark, ' / '), '') as remark
from group_sessions s
group by s.group_id, s.kind, s.weekday, s.start_time, s.end_time, s.campus_code, s.room;

-- 回傳如：FT 面授課 週日 09:00-10:50 · IOH/F0201 ｜ FT 導修課 週日 11:00-11:50 · IOH/F0201
create or replace function group_time_label(p_group bigint) returns text
language sql stable set search_path = public as $$
  select string_agg(
           trim(coalesce(m.kind,'') || ' ' || wd(m.weekday)) || ' ' ||
           to_char(m.start_time,'HH24:MI') || '-' || to_char(m.end_time,'HH24:MI') ||
           ' · ' || coalesce(m.campus_code,'?') || '/' || coalesce(m.room,'?'),
           ' ｜ ' order by m.ord, m.weekday, m.start_time)
  from v_group_session_merged m
  where m.group_id = p_group
$$;

-- 匹配結果 / 意向列表用的組別標籤，永遠帶時間
create or replace function group_label(p_id bigint) returns text
language sql stable set search_path = public as $$
  select g.group_no || '（' || coalesce(group_time_label(g.id), '時間待定') || '）'
  from course_groups g where g.id = p_id
$$;

-- 前端一次取用：課程 → 組別 → 節次
create or replace view v_group_detail as
select g.id          as group_id,
       g.course_id,
       g.group_no,
       g.capacity,
       c.code        as course_code,
       c.name        as course_name,
       c.term,
       c.duration,
       coalesce(
         jsonb_agg(
           jsonb_build_object(
             'kind',        m.kind,
             'weekday',     m.weekday,
             'weekday_zh',  wd(m.weekday),
             'time',        to_char(m.start_time,'HH24:MI') || ' - ' || to_char(m.end_time,'HH24:MI'),
             'start_time',  to_char(m.start_time,'HH24:MI'),
             'end_time',    to_char(m.end_time,'HH24:MI'),
             'campus',      m.campus_code,
             'campus_name', cp.name,
             'campus_addr', cp.address,
             'room',        m.room,
             'date_ranges', to_jsonb(coalesce(m.date_ranges, array[]::text[])),
             'remark',      m.remark
           ) order by m.ord, m.weekday, m.start_time
         ) filter (where m.group_id is not null),
         '[]'::jsonb
       ) as sessions
from course_groups g
join courses c on c.id = g.course_id
left join v_group_session_merged m on m.group_id = g.id
left join campuses cp on cp.code = m.campus_code
where g.is_active and c.is_active
group by g.id, g.course_id, g.group_no, g.capacity, c.code, c.name, c.term, c.duration;
