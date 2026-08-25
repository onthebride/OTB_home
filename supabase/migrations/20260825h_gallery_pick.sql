-- 갤러리 작가 지정 — 고른 사진만 찍기. 대표 요청 2026-08-25:
--   「예식장이름 눌러야 작가이름 넣을 수 있게 되어 있는데 검색만으로 지정할 수 있게 해줘
--    그 안에도 여러작가들 있거든 그래서 체크 해서 체크한것만 지정할 수 있게 해줘」
--
-- 예식장 묶음으로 통째 찍는 것(admin_gallery_staff_bulk)만으로는 모자란다.
-- 한 예식장 사진에 작가가 여럿 섞여 있으면 골라서 찍어야 한다.

create or replace function public.admin_gallery_staff_many(p_ids uuid[], p_staff_id uuid)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_ids is null or array_length(p_ids, 1) is null then
    return jsonb_build_object('ok', true, 'n', 0);
  end if;
  -- 한 번에 너무 많이 보내면 실수로 통째 덮어쓸 수 있다. 한 화면 분량이면 넉넉하다
  if array_length(p_ids, 1) > 500 then raise exception '한 번에 500장까지만 됩니다'; end if;
  if p_staff_id is not null and not exists (select 1 from public.staff where id = p_staff_id) then
    raise exception 'staff not found';
  end if;
  update public.gallery set staff_id = p_staff_id where id = any(p_ids);
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'n', n);
end$$;


-- ===== 작가별 촬영 이력 간추림 =====
-- 대표 요청 «전체 촬영건수도 기록해주고 / 홀별로 많이 간 순위 10위까지».
-- admin_staff_venues 는 작가마다 스무 곳씩 실어 무겁다.
-- 화면 옆에 붙일 용도로 가벼운 것을 따로 낸다
create or replace function public.admin_staff_shots(p_top integer default 10)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare res jsonb; top jsonb; today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  with raw as (
    select 0 as src, st.id as staff_id, st.name as staff_name, coalesce(st.active, false) as active,
           private.venue_canon(b.wedding_venue) as vkey, b.wedding_venue as venue, b.wedding_date as d
    from public.bookings b
    join public.staff st on st.id in (b.assignee_id, b.sub_assignee_id)
    where b.status <> '취소' and coalesce(nullif(trim(b.wedding_venue), ''), '') <> ''
    union all
    select 1, h.staff_id, coalesce(s.name, h.staff_name), coalesce(s.active, false),
           private.venue_canon_key(h.venue_key), h.venue, h.shot_on
    from public.staff_history h
    left join public.staff s on s.id = h.staff_id
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
  with raw as (
    select private.venue_canon(b.wedding_venue) as vkey, b.wedding_venue as venue,
           b.wedding_date as d, b.id::text as k
    from public.bookings b
    where b.status <> '취소' and coalesce(nullif(trim(b.wedding_venue), ''), '') <> ''
    union all
    select private.venue_canon_key(h.venue_key), h.venue, h.shot_on,
           h.shot_on::text || ':' || h.venue_key
    from public.staff_history h where not h.as_sub
  ),
  -- 같은 날 같은 곳은 한 예식으로 본다 (메인·서브가 따로 들어와 있어도 한 번)
  uniq as (select distinct vkey, d from raw where d < today)
  select coalesce(jsonb_agg(t order by t.n desc, t.venue), '[]'::jsonb) into top
  from (
    select u.vkey, (select r.venue from raw r where r.vkey = u.vkey order by r.d desc limit 1) as venue,
           count(*)::int as n
    from uniq u group by u.vkey order by count(*) desc limit p_top) t;

  return jsonb_build_object('ok', true, 'staff', res, 'venues', top);
end$$;


-- ===== 올릴 때 작가도 같이 =====
-- 대표 요청 «갤러리 올릴때 작가 이름 넣는거만 해줘».
-- 앞으로 올리는 것은 올리는 자리에서 찍으면 나중에 손볼 일이 없다
create or replace function public.admin_gallery_add(payload jsonb)
returns public.gallery language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare r public.gallery; sid uuid;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  sid := nullif(payload->>'staff_id', '')::uuid;
  if sid is not null and not exists (select 1 from public.staff where id = sid) then
    raise exception 'staff not found';
  end if;
  insert into public.gallery (image_path, image_url, venue, sort, staff_id)
  values (payload->>'image_path', payload->>'image_url', nullif(payload->>'venue',''),
          coalesce((payload->>'sort')::int, 0), sid)
  returning * into r;
  return r;
end$$;
