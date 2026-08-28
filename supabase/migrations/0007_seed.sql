-- =====================================================================
-- 0007 · 2026 秋季學期課表（ENVR 四門課，各 T01/T02/T03）
-- weekday: 0=Sun 1=Mon 2=Tue 3=Wed 4=Thu 5=Fri 6=Sat
-- =====================================================================

select import_course_internal(
  'ENVR 8501SCF', '生態保護與修復', '2026-秋', '一學期',
  $json$
  [
    {"group_no":"T01","sessions":[
      {"seq":1,"kind":"FT 面授課","weekday":1,"start_time":"19:00","end_time":"20:50",
       "campus_code":"JCC","room":"E0313","start_date":"2026-09-07","end_date":"2026-10-12"},
      {"seq":1,"kind":"FT 面授課","weekday":1,"start_time":"19:00","end_time":"20:50",
       "campus_code":"JCC","room":"E0313","start_date":"2026-10-26","end_date":"2026-11-30"}
    ]},
    {"group_no":"T02","sessions":[
      {"seq":1,"kind":"FT 面授課","weekday":6,"start_time":"13:00","end_time":"14:50",
       "campus_code":"HKMU","room":"C0G01","start_date":"2026-09-05","end_date":"2026-09-19"},
      {"seq":1,"kind":"FT 面授課","weekday":6,"start_time":"13:00","end_time":"14:50",
       "campus_code":"HKMU","room":"C0G01","start_date":"2026-10-03","end_date":"2026-11-28"}
    ]},
    {"group_no":"T03","sessions":[
      {"seq":1,"kind":"FT 面授課","weekday":6,"start_time":"16:00","end_time":"17:50",
       "campus_code":"HKMU","room":"C0G01","start_date":"2026-09-05","end_date":"2026-09-19"},
      {"seq":1,"kind":"FT 面授課","weekday":6,"start_time":"16:00","end_time":"17:50",
       "campus_code":"HKMU","room":"C0G01","start_date":"2026-10-03","end_date":"2026-11-28"}
    ]}
  ]
  $json$::jsonb
);

select import_course_internal(
  'ENVR 8931SCF', '當代中國的環境政策與戰略', '2026-秋', '一學期',
  $json$
  [
    {"group_no":"T01","sessions":[
      {"seq":1,"kind":"FT 面授課","weekday":2,"start_time":"19:00","end_time":"20:50",
       "campus_code":"JCC","room":"E0313","start_date":"2026-09-01","end_date":"2026-11-24"}
    ]},
    {"group_no":"T02","sessions":[
      {"seq":1,"kind":"FT 面授課","weekday":6,"start_time":"09:00","end_time":"10:50",
       "campus_code":"HKMU","room":"C0G01","start_date":"2026-09-05","end_date":"2026-09-19"},
      {"seq":1,"kind":"FT 面授課","weekday":6,"start_time":"09:00","end_time":"10:50",
       "campus_code":"HKMU","room":"C0G01","start_date":"2026-10-03","end_date":"2026-11-28"}
    ]},
    {"group_no":"T03","sessions":[
      {"seq":1,"kind":"FT 面授課","weekday":6,"start_time":"19:00","end_time":"20:50",
       "campus_code":"HKMU","room":"C0G01","start_date":"2026-09-05","end_date":"2026-09-19"},
      {"seq":1,"kind":"FT 面授課","weekday":6,"start_time":"19:00","end_time":"20:50",
       "campus_code":"HKMU","room":"C0G01","start_date":"2026-10-03","end_date":"2026-11-28"}
    ]}
  ]
  $json$::jsonb
);

select import_course_internal(
  'ENVR 8941SCF', '中國環境保護的管理與實踐', '2026-秋', '一學期',
  $json$
  [
    {"group_no":"T01","sessions":[
      {"seq":1,"kind":"FT 面授課","weekday":3,"start_time":"19:00","end_time":"20:50",
       "campus_code":"JCC","room":"E0313","start_date":"2026-09-02","end_date":"2026-11-25"}
    ]},
    {"group_no":"T02","sessions":[
      {"seq":1,"kind":"FT 面授課","weekday":0,"start_time":"13:00","end_time":"14:50",
       "campus_code":"HKMU","room":"C0G01","start_date":"2026-09-06","end_date":"2026-10-11"},
      {"seq":1,"kind":"FT 面授課","weekday":0,"start_time":"13:00","end_time":"14:50",
       "campus_code":"HKMU","room":"C0G01","start_date":"2026-10-25","end_date":"2026-11-29"}
    ]},
    {"group_no":"T03","sessions":[
      {"seq":1,"kind":"FT 面授課","weekday":0,"start_time":"16:00","end_time":"17:50",
       "campus_code":"HKMU","room":"C0G01","start_date":"2026-09-06","end_date":"2026-10-11"},
      {"seq":1,"kind":"FT 面授課","weekday":0,"start_time":"16:00","end_time":"17:50",
       "campus_code":"HKMU","room":"C0G01","start_date":"2026-10-25","end_date":"2026-11-29"}
    ]}
  ]
  $json$::jsonb
);

select import_course_internal(
  'ENVR 8951SCF', '中國特色的可持續發展', '2026-秋', '一學期',
  $json$
  [
    {"group_no":"T01","sessions":[
      {"seq":1,"kind":"FT 面授課","weekday":4,"start_time":"19:00","end_time":"20:50",
       "campus_code":"JCC","room":"E0313","start_date":"2026-09-03","end_date":"2026-09-24"},
      {"seq":1,"kind":"FT 面授課","weekday":4,"start_time":"19:00","end_time":"20:50",
       "campus_code":"JCC","room":"E0313","start_date":"2026-10-08","end_date":"2026-11-26"}
    ]},
    {"group_no":"T02","sessions":[
      {"seq":1,"kind":"FT 面授課","weekday":0,"start_time":"09:00","end_time":"10:50",
       "campus_code":"HKMU","room":"C0G01","start_date":"2026-09-06","end_date":"2026-10-11"},
      {"seq":1,"kind":"FT 面授課","weekday":0,"start_time":"09:00","end_time":"10:50",
       "campus_code":"HKMU","room":"C0G01","start_date":"2026-10-25","end_date":"2026-11-29"}
    ]},
    {"group_no":"T03","sessions":[
      {"seq":1,"kind":"FT 面授課","weekday":0,"start_time":"09:00","end_time":"10:50",
       "campus_code":"IOH","room":"F0201","start_date":"2026-09-06","end_date":"2026-10-11"},
      {"seq":1,"kind":"FT 面授課","weekday":0,"start_time":"09:00","end_time":"10:50",
       "campus_code":"IOH","room":"F0201","start_date":"2026-10-25","end_date":"2026-11-29"}
    ]}
  ]
  $json$::jsonb
);
