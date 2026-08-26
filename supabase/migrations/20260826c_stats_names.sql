-- 두 가지. 대표 요청 2026-08-26.
--
-- ① 「작가 캘린더에 후기 보여주는거 신부 이름 넣어줘」
--    앞서 내가 이름을 뺐다 — 링크만 알면 열리는 화면이라 조심한 것이다.
--    대표가 넣자고 하니 **이름만** 넣는다. 전화번호·이메일은 여전히 안 낸다.
--    (그 예식은 본인이 찍은 것이고, 신부님 이름을 알아야 「누구 후기인지」 안다)
--
-- ② 「이제부터 우리 집계는 정확하게 쌓이는거지?」 — 구멍이 하나 있었다.
--    예식장 이름 잇기(admin_venue_alias_suggest)가 지난 이력(staff_history)만 봤다.
--    앞으로 들어오는 **예약(bookings)의 예식장 이름은 못 본다** —
--    대표가 손으로 적는 칸이라 「아펠가모 잠실점」 같은 새 표기가 또 나온다.
--    예약 쪽도 같이 보게 고친다. 그래야 새 예약이 쌓여도 저절로 묶인다.

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
  uniq as (select distinct on (vkey, d) * from raw order by vkey, d, src),
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

  select jsonb_build_object('n', count(*), 'avg', round(avg(sub_stars)::numeric, 1))
    into subs from public.feedback where sub_staff_id = p_staff_id and sub_stars is not null;

  -- 신부님 이름을 넣는다 (대표 요청 2026-08-26). 번호·이메일은 여전히 안 낸다
  select coalesce(jsonb_agg(t order by t.wedding_date desc nulls last), '[]'::jsonb) into said
  from (
    select b.wedding_date, b.wedding_venue,
           coalesce(nullif(trim(b.bride_name), ''), nullif(trim(b.contractor_name), '')) as bride_name,
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

grant execute on function public.staff_stats(uuid) to anon, authenticated;


-- ===== 앞으로 들어오는 예약도 같이 봐야 저절로 묶인다 =====
create or replace function public.admin_venue_alias_suggest(p_min integer default 2)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  with src as (
    -- 지난 이력 + **앞으로 들어오는 예약**. 예식장은 대표가 손으로 적는 칸이라
    -- 새 표기가 계속 나온다. 예약 쪽을 안 보면 새 예약이 영영 안 묶인다
    select venue_key as vk, venue, shot_on as d from public.staff_history
    where coalesce(venue_key, '') <> ''
    union all
    select private.venue_key(b.wedding_venue), b.wedding_venue, b.wedding_date
    from public.bookings b
    where b.status <> '취소'
      and coalesce(nullif(trim(b.wedding_venue), ''), '') <> ''
      and coalesce(private.venue_key(b.wedding_venue), '') <> ''
  ),
  k0 as (
    select vk as venue_key, count(*) n, (array_agg(venue order by d desc))[1] as venue
    from src group by vk
  ),
  k as (
    -- 낱말은 원문 이름에서 뽑는다 (묶음키는 이미 붙어 있어 낱말이 하나로 잡힌다)
    select venue_key, n, venue, private.venue_words(venue) as w,
           (select string_agg(ch, '' order by ch)
              from regexp_split_to_table(venue_key, '') ch) as sorted_chars
    from k0
  ),
  pair as (
    select a.venue_key as long_key, a.venue as long_venue, a.n as long_n,
           b.venue_key as short_key, b.venue as short_venue, b.n as short_n,
           case when b.w <@ a.w then 1 else 2 end as rank
    from k a join k b on a.venue_key <> b.venue_key
    where (
        (b.w <@ a.w and array_length(b.w, 1) >= 1
         and exists (select 1 from unnest(b.w) x where length(x) >= 3))
        or (a.sorted_chars = b.sorted_chars and length(a.venue_key) >= 5)
      )
      and (length(b.venue_key) < length(a.venue_key)
           or (length(b.venue_key) = length(a.venue_key) and b.n > a.n))
      and not exists (select 1 from public.venue_alias x where x.from_key = a.venue_key)
      and not exists (select 1 from public.venue_stem_block z where z.stem = b.venue_key)
  )
  select coalesce(jsonb_agg(t order by t.long_n desc), '[]'::jsonb) into res
  from (select distinct on (long_key) * from pair order by long_key, rank, short_n desc) t;
  return jsonb_build_object('ok', true, 'pairs', res);
end$$;
