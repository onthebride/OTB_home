-- 작가별 촬영 이력(admin_staff_shots) 가 느렸다 — 운영 누적 평균 1,268ms, 최대 2.7초.
-- 홈의 「많이 간 예식장」 줄과 「작가 평가」 칸이 이걸 기다린다.
--
-- 느렸던 이유 둘. 결과는 그대로 두고 방법만 바꾼다.
--
--  ① 예식장 묶음키를 줄마다 함수로 구했다
--     private.venue_canon(...) 은 안에서 venue_alias 를 조회한다. 예약+지난이력
--     4,363줄에 이것을 걸었고, 앞뒤 두 덩이가 각각 다시 걸어 8천 번 넘게 불렀다.
--     → venue_alias 를 left join 으로 **한 번만** 이어붙인다.
--       (staff_history 는 venue_key 가 칸으로 이미 있어 alias 만 붙이면 된다)
--
--  ② 예식장 이름을 예식장마다 처음부터 다시 찾았다
--     (select r.venue from raw r where r.vkey = u.vkey order by r.d desc limit 1)
--     묶음키 하나마다 4,363줄짜리 임시표를 통째로 훑는다. 그 부분만 289ms 였다.
--     → distinct on (vkey) 로 한 번 훑어 이름표를 만들고 이어붙인다.
--
-- ⚠ 결과가 달라지면 안 된다. 특히 지킨 것:
--    - venue_key 가 비어 있는 지난 이력 줄도 빼지 않는다 (예전에도 안 뺐다)
--    - 그런 줄은 이름표와 안 이어진다 — 예전 상관 서브쿼리도 null 은 못 찾아 null 이었다.
--      그래서 join 이 아니라 left join 이다
--    - 오늘 기준은 서울 시각이다 (current_date 아님)
--    - 「같은 날 같은 곳은 한 예식」, 「예약이 이력보다 먼저(src 0)」 규칙 그대로

create or replace function public.admin_staff_shots(p_top integer default 10)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'private', 'pg_temp'
as $function$
declare res jsonb; top jsonb; today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;

  with bk as (
    select b.assignee_id, b.sub_assignee_id, b.wedding_venue as venue, b.wedding_date as d,
           private.venue_key(b.wedding_venue) as k0
    from public.bookings b
    where b.status <> '취소' and coalesce(nullif(trim(b.wedding_venue), ''), '') <> ''
  ),
  bkc as (
    select bk.*, coalesce(a.to_key, bk.k0) as vkey
    from bk left join public.venue_alias a on a.from_key = bk.k0
  ),
  hic as (
    select h.staff_id, h.staff_name, h.venue, h.shot_on as d,
           coalesce(a.to_key, h.venue_key) as vkey
    from public.staff_history h
    left join public.venue_alias a on a.from_key = h.venue_key
  ),
  raw as (
    select 0 as src, st.id as staff_id, st.name as staff_name, coalesce(st.active, false) as active,
           c.vkey, c.venue, c.d
    from bkc c
    join public.staff st on st.id in (c.assignee_id, c.sub_assignee_id)
    union all
    select 1, hc.staff_id, coalesce(s.name, hc.staff_name), coalesce(s.active, false),
           hc.vkey, hc.venue, hc.d
    from hic hc
    left join public.staff s on s.id = hc.staff_id
  ),
  uniq as (
    select distinct on (coalesce(staff_id::text, staff_name), vkey, d) *
    from raw order by coalesce(staff_id::text, staff_name), vkey, d, src
  ),
  per as (
    select coalesce(staff_id::text, staff_name) as skey,
           max(staff_id::text) as staff_id, min(staff_name) as staff_name, bool_or(active) as active,
           vkey, (array_agg(venue order by d desc))[1] as venue,
           count(*) filter (where d < today) as been
    from uniq group by 1, 5
  ),
  ranked as (
    select p.*, row_number() over (partition by p.skey order by p.been desc, p.venue) as rn from per p
  )
  select coalesce(jsonb_agg(t order by t.shots desc, t.staff_name), '[]'::jsonb) into res
  from (
    select max(r.staff_id) as staff_id, r.staff_name, bool_or(r.active) as active,
           sum(r.been)::int as shots, count(*)::int as venues,
           coalesce(jsonb_agg(jsonb_build_object('venue', r.venue, 'n', r.been)
                      order by r.been desc, r.venue) filter (where r.rn <= p_top), '[]'::jsonb) as top
    from ranked r group by r.skey, r.staff_name) t;

  -- 우리가 많이 간 예식장 (작가 무관)
  with bkc as (
    select coalesce(a.to_key, k.k0) as vkey, k.venue, k.d
    from (
      select private.venue_key(b.wedding_venue) as k0, b.wedding_venue as venue, b.wedding_date as d
      from public.bookings b
      where b.status <> '취소' and coalesce(nullif(trim(b.wedding_venue), ''), '') <> ''
    ) k
    left join public.venue_alias a on a.from_key = k.k0
  ),
  hic as (
    select coalesce(a.to_key, h.venue_key) as vkey, h.venue, h.shot_on as d
    from public.staff_history h
    left join public.venue_alias a on a.from_key = h.venue_key
    where not h.as_sub
  ),
  raw as (select * from bkc union all select * from hic),
  -- 같은 날 같은 곳은 한 예식으로 본다 (메인·서브가 따로 들어와 있어도 한 번)
  uniq as (select distinct vkey, d from raw where d < today),
  -- 묶음키마다 가장 최근 표기 하나. 한 번만 훑는다
  latest as (select distinct on (vkey) vkey, venue from raw order by vkey, d desc, venue)
  select coalesce(jsonb_agg(t order by t.n desc, t.venue), '[]'::jsonb) into top
  from (
    select u.vkey, l.venue, count(*)::int as n
    from uniq u
    left join latest l on l.vkey = u.vkey
    group by u.vkey, l.venue
    order by count(*) desc limit p_top) t;

  return jsonb_build_object('ok', true, 'staff', res, 'venues', top);
end$function$;
