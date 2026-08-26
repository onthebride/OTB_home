-- 작가 본인이 보는 「내 기록」. 대표 요청 2026-08-26:
--   「작가별 통계 만들자 작가본인들 캘린더에 별로로 탭 분리해서 넣을거야
--    촬영건수 / 많이간 예식장 순위 / 후기 점수 / 후기내용」
--
-- 작가 캘린더(/staff-calendar?s=<작가ID>)와 같은 방식이다 — 링크를 아는 사람만 본다.
-- staff_calendar 처럼 anon 이 부를 수 있게 열되, **그 작가 것만** 낸다.
--
-- 고객 정보는 안 낸다. 후기 글에는 날짜와 예식장만 붙인다 —
-- 그 예식에 본인이 갔으니 이미 아는 것이고, 신부 이름·번호는 알 필요가 없다.
-- (관리자 화면은 이름을 보여주지만 이건 작가에게 나가는 것이라 다르다)

create or replace function public.staff_stats(p_staff_id uuid)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  st public.staff;
  today date := (now() at time zone 'Asia/Seoul')::date;
  res jsonb; venues jsonb; fb jsonb; said jsonb; subs jsonb;
begin
  select * into st from public.staff where id = p_staff_id;
  if not found then return null; end if;

  -- ── 촬영: 우리 예약(2026-06~)과 캘린더 이력(2018~)을 합치되
  --    같은 곳·같은 날은 한 번만 (메인·서브가 따로 들어와 있어도 한 번)
  with raw as (
    select 0 as src, private.venue_canon(b.wedding_venue) as vkey,
           b.wedding_venue as venue, b.wedding_date as d
    from public.bookings b
    where b.status <> '취소'
      and coalesce(nullif(trim(b.wedding_venue), ''), '') <> ''
      and p_staff_id in (b.assignee_id, b.sub_assignee_id)
    union all
    select 1, private.venue_canon_key(h.venue_key), h.venue, h.shot_on
    from public.staff_history h
    where h.staff_id = p_staff_id
  ),
  uniq as (
    select distinct on (vkey, d) * from raw order by vkey, d, src
  ),
  per as (
    select vkey, (array_agg(venue order by d desc))[1] as venue,
           count(*) filter (where d <  today) as been,
           count(*) filter (where d >= today) as booked
    from uniq group by vkey
  )
  select jsonb_build_object(
    'shots',  coalesce((select sum(been)   from per), 0),
    'booked', coalesce((select sum(booked) from per), 0),
    'venues', coalesce((select count(*)    from per where been > 0), 0),
    'first',  (select min(d) from uniq where d < today),
    'last',   (select max(d) from uniq where d < today)
  ) into res;

  -- 많이 간 예식장 (열 곳)
  with raw as (
    select 0 as src, private.venue_canon(b.wedding_venue) as vkey,
           b.wedding_venue as venue, b.wedding_date as d
    from public.bookings b
    where b.status <> '취소'
      and coalesce(nullif(trim(b.wedding_venue), ''), '') <> ''
      and p_staff_id in (b.assignee_id, b.sub_assignee_id)
    union all
    select 1, private.venue_canon_key(h.venue_key), h.venue, h.shot_on
    from public.staff_history h where h.staff_id = p_staff_id
  ),
  uniq as (select distinct on (vkey, d) * from raw order by vkey, d, src)
  select coalesce(jsonb_agg(t order by t.n desc, t.venue), '[]'::jsonb) into venues
  from (
    select (array_agg(venue order by d desc))[1] as venue, count(*)::int as n
    from uniq where d < today group by vkey order by count(*) desc limit 10) t;

  -- ── 후기 점수 (메인으로 간 예식만. 서브 별점은 아래에 따로)
  with f as (
    select fb.*, private.fb_score(fb.*) as score
    from public.feedback fb where fb.staff_id = p_staff_id
  ),
  tgt as (
    select count(*) as n from public.bookings b
    where b.status <> '취소' and b.assignee_id = p_staff_id
      and b.wedding_date is not null and b.wedding_date < today
  )
  select jsonb_build_object(
    'n',        (select count(*) from f),
    'score',    (select round(avg(score)::numeric, 1)     from f),
    'overall',  (select round(avg(overall)::numeric, 1)   from f),
    'rec',      (select round(avg(recommend)::numeric, 1) from f),
    'target',   (select n from tgt),
    'rate',     (select case when (select n from tgt) = 0 then null
                       else least(100, round(100.0 * (select count(*) from f) / (select n from tgt))) end),
    'late',     (select count(*) from f where arrival <> 'ontime')
  ) into fb;

  -- 서브로 받은 별점
  select jsonb_build_object(
    'n',   count(*),
    'avg', round(avg(sub_stars)::numeric, 1)
  ) into subs from public.feedback where sub_staff_id = p_staff_id and sub_stars is not null;

  -- ── 신부님이 남긴 글. 이름·번호는 안 낸다 (날짜·예식장까지만)
  select coalesce(jsonb_agg(t order by t.wedding_date desc nulls last), '[]'::jsonb) into said
  from (
    select b.wedding_date, b.wedding_venue,
           f.overall, f.recommend, f.arrival,
           nullif(trim(coalesce(f.message, '')), '')  as message,
           nullif(trim(coalesce(f.next_req, '')), '') as next_req,
           (f.sub_staff_id = p_staff_id) as as_sub,
           case when f.sub_staff_id = p_staff_id then f.sub_stars else null end as sub_stars
    from public.feedback f
    join public.bookings b on b.id = f.booking_id
    where (f.staff_id = p_staff_id or f.sub_staff_id = p_staff_id)
      and (coalesce(f.message, '') <> '' or coalesce(f.next_req, '') <> '')) t;

  return jsonb_build_object(
    'ok', true, 'staff_name', st.name, 'today', today,
    'shot', res, 'venues', venues, 'fb', fb, 'sub', subs, 'said', said);
end$$;

-- 작가 캘린더와 같다 — 링크(작가ID)를 아는 사람만 본다
grant execute on function public.staff_stats(uuid) to anon, authenticated;
