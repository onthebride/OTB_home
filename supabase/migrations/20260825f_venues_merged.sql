-- 「가본 예식장」을 예약(2026-06~)과 지난 이력(2018~) 을 합쳐서 센다.
-- 대표가 캘린더를 줘서 이력이 3,843건 생겼다 (2026-08-25).
--
-- 겹치는 구간이 있다 — 2026-06-20 뒤로는 같은 예식이 두 곳에 다 있을 수 있다.
-- 그래서 (작가, 예식장묶음, 날짜) 가 같으면 한 번만 센다.
-- 예약 쪽을 먼저 두어(src=0) 이름 표기는 예약 것을 쓴다.

create or replace function public.admin_staff_venues(p_days integer default 3650)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare res jsonb; today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  with raw as (
    -- 우리 예약 (메인·서브 둘 다 «갔다» 로 친다)
    select 0 as src, st.id as staff_id, st.name as staff_name, coalesce(st.active, false) as active,
           private.venue_key(b.wedding_venue) as vkey, b.wedding_venue as venue, b.wedding_date as d
    from public.bookings b
    join public.staff st on st.id in (b.assignee_id, b.sub_assignee_id)
    where b.status <> '취소'
      and coalesce(nullif(trim(b.wedding_venue), ''), '') <> ''
      and b.wedding_date >= today - p_days
    union all
    -- 캘린더에서 읽어 넣은 지난 이력. 그만두신 분은 staff_id 가 없다
    select 1, h.staff_id, coalesce(s.name, h.staff_name), coalesce(s.active, false),
           h.venue_key, h.venue, h.shot_on
    from public.staff_history h
    left join public.staff s on s.id = h.staff_id
    where h.shot_on >= today - p_days
  ),
  -- 같은 사람·같은 곳·같은 날은 한 번만. 예약 쪽(src=0)을 살린다
  uniq as (
    select distinct on (coalesce(staff_id::text, staff_name), vkey, d) *
    from raw order by coalesce(staff_id::text, staff_name), vkey, d, src
  ),
  per as (
    select coalesce(staff_id::text, staff_name) as skey,
           max(staff_id::text) as staff_id, min(staff_name) as staff_name, bool_or(active) as active,
           vkey,
           (array_agg(venue order by d desc))[1] as venue,
           count(*) filter (where d <  today) as been,
           count(*) filter (where d >= today) as booked,
           max(d) filter (where d < today) as last_been
    from uniq group by 1, 5
  ),
  -- 많이 간 곳부터 차례를 매긴다. 한 번뿐인 곳까지 다 담으면 무거워서 스무 곳만 보낸다.
  -- (jsonb 는 «-> '[0:19]'» 같은 자르기가 없다 — 그건 PostgREST 문법이지 SQL 이 아니다)
  ranked as (
    select p.*, row_number() over (partition by p.skey
             order by p.been desc, p.booked desc, p.venue) as rn
    from per p
  )
  select coalesce(jsonb_agg(t order by t.been desc, t.booked desc, t.staff_name), '[]'::jsonb) into res
  from (
    select max(r.staff_id) as staff_id, r.staff_name, bool_or(r.active) as active,
           sum(r.been)::int as been, sum(r.booked)::int as booked,
           count(*)::int as venues,
           max(r.last_been) as last_been,
           coalesce(jsonb_agg(jsonb_build_object('venue', r.venue, 'been', r.been, 'booked', r.booked)
                      order by r.been desc, r.booked desc, r.venue)
                    filter (where r.rn <= 20), '[]'::jsonb) as list
    from ranked r group by r.skey, r.staff_name) t;
  return jsonb_build_object('ok', true, 'today', today, 'staff', res);
end$$;


create or replace function public.admin_venue_staff(p_venue text)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare res jsonb; today date := (now() at time zone 'Asia/Seoul')::date; k text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  k := private.venue_key(p_venue);
  if coalesce(k, '') = '' then
    return jsonb_build_object('ok', true, 'venue', p_venue, 'staff', '[]'::jsonb);
  end if;
  with raw as (
    select 0 as src, st.id as staff_id, st.name as staff_name, coalesce(st.active, false) as active,
           b.wedding_date as d
    from public.bookings b
    join public.staff st on st.id in (b.assignee_id, b.sub_assignee_id)
    where b.status <> '취소' and private.venue_key(b.wedding_venue) = k
    union all
    select 1, h.staff_id, coalesce(s.name, h.staff_name), coalesce(s.active, false), h.shot_on
    from public.staff_history h
    left join public.staff s on s.id = h.staff_id
    where h.venue_key = k
  ),
  uniq as (
    select distinct on (coalesce(staff_id::text, staff_name), d) *
    from raw order by coalesce(staff_id::text, staff_name), d, src
  )
  select coalesce(jsonb_agg(t order by t.been desc, t.booked desc, t.staff_name), '[]'::jsonb) into res
  from (
    select max(staff_id::text) as staff_id, min(staff_name) as staff_name, bool_or(active) as active,
           count(*) filter (where d <  today)::int as been,
           count(*) filter (where d >= today)::int as booked,
           max(d) filter (where d < today) as last_been
    from uniq group by coalesce(staff_id::text, staff_name)) t;
  return jsonb_build_object('ok', true, 'venue', p_venue, 'key', k, 'staff', res);
end$$;
