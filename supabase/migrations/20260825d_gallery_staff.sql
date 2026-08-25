-- 갤러리 사진에 «누가 찍었는지» 를 붙이고, 작가별 «가본 예식장» 을 낸다.
-- 대표 요청 2026-08-25 — 지정(작가 고르기)에 쓸 자료다.
--   "작가들이 어디를 많이 갔는지 정보가 필요해 / 다른업체에서 촬영한건 빼고
--    우리 스케줄로 한게 필요해 / 갤러리도 누구사진인지 보여주는게 필요해"
--
-- «우리 스케줄로 한 것만» — public.bookings 에서만 센다. 작가 캘린더의 「다른 촬영」
-- (public.staff_busy)은 다른 업체 일이라 여기 안 들어온다. 자료를 섞지 않는다.
--
-- 갤러리에 작가를 자동으로 못 붙이는 이유 (대표에게 설명함):
--   · 갤러리 사진에는 날짜가 없다 (created_at 은 올린 날)
--   · 예식장 이름이 서로 다르게 적혀 있다 — 갤러리 「아펠가모-광화문」 / 예약 「광화문 아펠가모」
--   · 같은 예식장을 여러 번 갔다 (공덕 아펠가모 12건) → 어느 예식 사진인지 특정 불가
-- 그래서 대표가 한 번은 손으로 찍는다. 예식장 묶음으로 한꺼번에 찍을 수 있게 만든다.


-- ===== 예식장 이름 묶기 =====
-- 「그랜드홀」·「2층 볼룸」 처럼 뒤에 붙는 말 때문에 문자열 비교로는 안 묶인다.
-- 홀·볼룸·층·룸 으로 끝나는 낱말을 떼고, 남은 낱말을 정렬해 이어붙인다.
-- admin_sales 가 쓰던 식을 그대로 함수로 뺐다 — 두 곳이 다르게 묶으면 숫자가 안 맞는다
create or replace function private.venue_key(v text)
returns text language sql immutable as $$
  select coalesce(nullif((
    select string_agg(w, '' order by w)
    from unnest(string_to_array(regexp_replace(lower(coalesce(v, '')), '[^[:alnum:]]+', ' ', 'g'), ' ')) w
    where w <> '' and w !~ '(홀|볼룸|층|룸)$'), ''), lower(coalesce(v, '')))
$$;


-- ===== 갤러리에 작가 칸 =====
alter table public.gallery add column if not exists staff_id uuid;
do $$ begin
  alter table public.gallery add constraint gallery_staff_id_fkey
    foreign key (staff_id) references public.staff(id) on delete set null;
exception when duplicate_object then null; end $$;
create index if not exists gallery_staff_idx on public.gallery (staff_id);

comment on column public.gallery.staff_id is
  '이 사진을 찍은 작가. 손으로 지정한다 (사진에 날짜가 없어 자동 매칭 불가)';


-- 홈 갤러리 — 작가 이름을 같이 낸다.
-- 아직 안 찍은 사진은 staff_name 이 null 이라 화면에서 그냥 이름을 안 보여주면 된다.
-- 돌려주는 칸이 늘어나므로 create or replace 로는 안 된다 — 먼저 지운다
drop function if exists public.gallery_public();
create or replace function public.gallery_public()
returns table(id uuid, image_url text, venue text, staff_name text)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select g.id, g.image_url, g.venue, s.name
  from public.gallery g
  left join public.staff s on s.id = g.staff_id
  order by g.sort asc, g.created_at desc
$$;


-- ===== 관리자: 작가 찍기 =====
-- 한 장씩. p_staff_id 를 null 로 주면 지운다 (잘못 찍었을 때 되돌릴 길이 있어야 한다)
create or replace function public.admin_gallery_staff(p_id uuid, p_staff_id uuid)
returns public.gallery language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare r public.gallery;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_staff_id is not null and not exists (select 1 from public.staff where id = p_staff_id) then
    raise exception 'staff not found';
  end if;
  update public.gallery set staff_id = p_staff_id where id = p_id returning * into r;
  if not found then raise exception 'photo not found'; end if;
  return r;
end$$;

-- 예식장 묶음으로 한꺼번에. 689장을 한 장씩 찍는 건 사람이 할 일이 아니다.
-- p_only_empty 를 켜면 «아직 안 찍은 것» 만 바꾼다 — 이미 손본 것을 덮어쓰지 않는다
create or replace function public.admin_gallery_staff_bulk(
  p_venue text, p_staff_id uuid, p_only_empty boolean default true)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_staff_id is not null and not exists (select 1 from public.staff where id = p_staff_id) then
    raise exception 'staff not found';
  end if;
  update public.gallery
     set staff_id = p_staff_id
   where venue is not distinct from nullif(p_venue, '')
     and (not p_only_empty or staff_id is null);
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'venue', p_venue, 'n', n);
end$$;


-- ===== 작가별 «가본 예식장» =====
-- 지난 예식(been)과 앞으로 잡힌 것(booked)을 나눠 낸다.
-- 우리 예약이 2026-06 부터라 지난 것만 보면 너무 적다 — 둘 다 보여주고 고르게 한다.
-- 메인·서브 둘 다 «갔다» 로 친다. 실제로 그 예식장에 가 본 것이 맞다
create or replace function public.admin_staff_venues(p_days integer default 3650)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare res jsonb; today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  with v as (
    select st.id as staff_id, st.name as staff_name,
           private.venue_key(b.wedding_venue) as vkey,
           b.wedding_venue, b.wedding_date
    from public.bookings b
    join public.staff st on st.id in (b.assignee_id, b.sub_assignee_id)
    where b.status <> '취소'
      and coalesce(nullif(trim(b.wedding_venue), ''), '') <> ''
      and b.wedding_date >= today - p_days
  ),
  per as (
    select staff_id, staff_name, vkey,
           -- 보여줄 이름은 그 묶음에서 제일 자주 쓰인 표기로 (제각각 적힌 것 중 하나를 고른다)
           (array_agg(wedding_venue order by wedding_date desc))[1] as venue,
           count(*) filter (where wedding_date <  today) as been,
           count(*) filter (where wedding_date >= today) as booked
    from v group by 1, 2, 3
  )
  select coalesce(jsonb_agg(t order by t.been desc, t.booked desc, t.staff_name), '[]'::jsonb) into res
  from (
    select p.staff_id, p.staff_name,
           sum(p.been)::int as been, sum(p.booked)::int as booked,
           count(*)::int as venues,
           jsonb_agg(jsonb_build_object('venue', p.venue, 'been', p.been, 'booked', p.booked)
                     order by p.been desc, p.booked desc, p.venue) as list
    from per p group by 1, 2) t;
  return jsonb_build_object('ok', true, 'today', today, 'staff', res);
end$$;


-- ===== 예식장으로 작가 찾기 =====
-- 신부가 「제 예식장에 가보신 분」 을 찾을 때 쓴다. 지정의 핵심 근거다.
-- 이름을 대충 적어도 묶어서 찾는다 (「광화문 아펠가모」 = 「아펠가모-광화문」)
create or replace function public.admin_venue_staff(p_venue text)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare res jsonb; today date := (now() at time zone 'Asia/Seoul')::date; k text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  k := private.venue_key(p_venue);
  if coalesce(k, '') = '' then return jsonb_build_object('ok', true, 'venue', p_venue, 'staff', '[]'::jsonb); end if;
  select coalesce(jsonb_agg(t order by t.been desc, t.booked desc, t.staff_name), '[]'::jsonb) into res
  from (
    select st.id as staff_id, st.name as staff_name,
           count(*) filter (where b.wedding_date <  today)::int as been,
           count(*) filter (where b.wedding_date >= today)::int as booked,
           max(b.wedding_date) filter (where b.wedding_date < today) as last_been
    from public.bookings b
    join public.staff st on st.id in (b.assignee_id, b.sub_assignee_id)
    where b.status <> '취소' and private.venue_key(b.wedding_venue) = k
    group by 1, 2) t;
  return jsonb_build_object('ok', true, 'venue', p_venue, 'key', k, 'staff', res);
end$$;

revoke all on function private.venue_key(text) from public, anon, authenticated;
