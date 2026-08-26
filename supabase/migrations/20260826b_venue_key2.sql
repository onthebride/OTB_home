-- 예식장 묶기 2차 고침. 대표 지적 2026-08-26:
--   「많이가본예식장이 수가 너무 적어 / 아펠가모 잠실같은경우는 30번도 더 갔을 것 같은데」
--
-- 1차 고침 뒤에도 김병훈 아펠가모가 아홉 조각으로 흩어져 있었다:
--   선릉아펠가모 10 · 광화문아펠가모 10 · 아펠가모잠실 9 · 공덕아펠가모 8 · 반포아펠가모 3
--   + 반포서울아펠가모 1 · 선릉점아펠가모 1 · 아펠가모 1 · 아펠가모선릉 1
--
-- 남아 있던 네 가지 —
--   ① 붙여 쓴 이름   「아펠가모선릉」 = 낱말 하나  ≠ 「아펠가모 선릉」 = 낱말 둘
--   ② 「점」 이 붙은 것 「아펠가모 선릉점」 → 선릉점아펠가모
--   ③ 괄호 안 지점    「아펠가모(잠실)」 → 괄호를 떼는 바람에 「아펠가모」 만 남아 지점이 사라짐
--   ④ 지역이 가운데   「서울 반포 아펠가모」 → 반포서울아펠가모.
--                     낱말을 정렬해 이어붙이므로 «서울» 이 가운데 끼어
--                     「반포아펠가모」 를 통째로 품지 못한다 → 글자로 훑는 잇기가 못 찾는다
--
-- 고치는 법 —
--   · 괄호 안을 **버리지 않고 낱말로 쓴다**. 「아펠가모(잠실)」 = {아펠가모, 잠실} 로 제대로 묶인다.
--     「상록아트홀(선릉)」 은 {상록아트홀, 선릉} 이 되어 「상록아트홀」 과 갈라지지만,
--     그건 아래 잇기(낱말 품기)가 도로 붙여준다
--   · 낱말 끝의 「점」·「지점」 을 뗀다 (선릉점 → 선릉)
--   · 잇기를 **글자 훑기가 아니라 낱말 셈**으로 한다 ↓ admin_venue_alias_suggest

create or replace function private.venue_key(v text)
returns text language sql immutable as $$
  with base as (
    -- 괄호는 «떼는» 게 아니라 «여는» 다. 안에 든 지점 이름이 사라지면 안 된다
    select w from unnest(string_to_array(
      regexp_replace(lower(coalesce(v, '')), '[^[:alnum:]]+', ' ', 'g'), ' ')) w
    where w <> ''
  ),
  trimmed as (
    -- 「선릉점」 → 「선릉」. 두 글자 이상 남을 때만 뗀다 (「점」 한 글자짜리를 지우지 않게)
    select case when w ~ '.{2,}(지점|점)$' then regexp_replace(w, '(지점|점)$', '') else w end as w
    from base
  ),
  kept as (
    select w from trimmed
    where w !~ '^([0-9]+|[a-z]|지하|b)?층$'
      and w not in ('아트홀','그랜드볼룸','그랜드볼룸홀','그랜드홀','볼룸','채플홀','컨벤션홀',
                    '웨딩홀','연회홀','연회장','대연회장','본홀','신관','별관','본관','홀',
                    '가든홀','크리스탈홀','다이아몬드홀','에메랄드홀','루비홀','사파이어홀',
                    '펄홀','아이보리홀','화이트홀','블랑홀','그레이스홀','로즈홀','릴리홀',
                    '스타홀','문홀','썬홀','제니스홀','노블레스홀','프레지던트홀','마리에홀')
  )
  select coalesce(
    nullif((select string_agg(w, '' order by w) from kept), ''),
    nullif((select string_agg(w, '' order by w) from trimmed), ''),
    ''
  )
$$;

-- 묶음키의 «낱말들». 잇기를 낱말 셈으로 하려면 필요하다
create or replace function private.venue_words(v text)
returns text[] language sql immutable as $$
  with base as (
    select w from unnest(string_to_array(
      regexp_replace(lower(coalesce(v, '')), '[^[:alnum:]]+', ' ', 'g'), ' ')) w
    where w <> ''
  ),
  trimmed as (
    select case when w ~ '.{2,}(지점|점)$' then regexp_replace(w, '(지점|점)$', '') else w end as w
    from base
  ),
  kept as (
    select w from trimmed
    where w !~ '^([0-9]+|[a-z]|지하|b)?층$'
      and w not in ('아트홀','그랜드볼룸','그랜드볼룸홀','그랜드홀','볼룸','채플홀','컨벤션홀',
                    '웨딩홀','연회홀','연회장','대연회장','본홀','신관','별관','본관','홀',
                    '가든홀','크리스탈홀','다이아몬드홀','에메랄드홀','루비홀','사파이어홀',
                    '펄홀','아이보리홀','화이트홀','블랑홀','그레이스홀','로즈홀','릴리홀',
                    '스타홀','문홀','썬홀','제니스홀','노블레스홀','프레지던트홀','마리에홀')
  )
  select coalesce(
    nullif(array(select w from kept order by w), '{}'),
    array(select w from trimmed order by w))
$$;

revoke all on function private.venue_words(text) from public, anon, authenticated;


-- ===== 규칙이 바뀌었으니 다시 계산 =====
delete from public.staff_history a
 using public.staff_history b
 where a.id > b.id and a.shot_on = b.shot_on and a.staff_name = b.staff_name
   and a.as_sub = b.as_sub and private.venue_key(a.venue) = private.venue_key(b.venue);

update public.staff_history set venue_key = private.venue_key(venue)
 where venue_key is distinct from private.venue_key(venue);

-- 옛 규칙으로 이어둔 것은 버린다. 아래에서 다시 잇는다
delete from public.venue_alias;


-- ===== 지점이 여러 곳인 브랜드는 통째로 빨아들이면 안 된다 =====
-- 「위더스」 하나에 영등포·안양·중랑이 한 곳으로 묶여버렸다 (2026-08-26 확인).
-- 지점 이름이 키에 안 들어간 브랜드는 «모으는 자리» 가 되면 안 된다.
-- (아펠가모·라마다는 이미 지점이 키에 들어 있어 괜찮다 — 「선릉아펠가모」 처럼)
--
-- 자동으로는 못 가른다. 「서울 상록아트홀」의 «서울» 과 「안양 위더스」의 «안양» 은
-- 생김새가 같은데 하나는 같은 곳이고 하나는 다른 곳이다. 그래서 목록으로 둔다.
create table if not exists public.venue_stem_block (
  stem text primary key,
  note text,
  created_at timestamptz not null default now()
);
alter table public.venue_stem_block enable row level security;
revoke all on public.venue_stem_block from anon, authenticated;
comment on table public.venue_stem_block is
  '지점이 여러 곳인 브랜드 — 예식장 이름 잇기에서 «모으는 자리» 가 되면 안 되는 묶음키';

insert into public.venue_stem_block (stem, note) values
  ('위더스', '영등포·안양·중랑 — 서로 다른 예식장이다')
on conflict (stem) do nothing;


-- ===== 잇기 — 글자 훑기가 아니라 낱말 셈 =====
-- 「서울 반포 아펠가모」 는 「반포 아펠가모」 의 낱말을 전부 품는다 → 같은 곳.
-- 글자로 훑으면 «서울» 이 가운데 끼어 못 찾는다.
-- 붙여 쓴 이름(「아펠가모선릉」)은 글자를 세어 맞춘다 — 같은 글자가 같은 수만큼 있으면 같은 곳
create or replace function public.admin_venue_alias_suggest(p_min integer default 2)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  with k0 as (
    select venue_key, count(*) n, (array_agg(venue order by shot_on desc))[1] as venue
    from public.staff_history
    where coalesce(venue_key, '') <> ''
    group by venue_key
  ),
  k as (
    -- 낱말은 **원문 이름**에서 뽑는다. 묶음키는 이미 붙여놓은 것이라
    -- venue_words(키) 를 하면 낱말이 늘 하나로 잡혀 품기가 아예 안 걸린다
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
        -- ① b 의 낱말을 a 가 전부 품는다 = a 는 b 에 지역·홀 이름이 더 붙은 것.
        --    지점이 여럿인 브랜드(아펠가모)도 안전하다 — 괄호를 열어 두었기 때문에
        --    지점 이름이 이미 b 안에 들어 있다 (「아펠가모 선릉」이 b 이지 「아펠가모」가 아니다)
        (b.w <@ a.w and array_length(b.w, 1) >= 1
         and exists (select 1 from unnest(b.w) x where length(x) >= 3))
        -- ② 붙여 쓴 것 — 글자가 똑같다 (「아펠가모선릉」 = 「선릉 아펠가모」)
        or (a.sorted_chars = b.sorted_chars and length(a.venue_key) >= 5)
      )
      -- 더 짧은(=더 뿌리에 가까운) 이름으로 모은다. 길이가 같으면 자주 나온 쪽으로
      and (length(b.venue_key) < length(a.venue_key)
           or (length(b.venue_key) = length(a.venue_key) and b.n > a.n))
      and not exists (select 1 from public.venue_alias x where x.from_key = a.venue_key)
      -- 지점이 여러 곳인 브랜드는 모으는 자리가 될 수 없다
      and not exists (select 1 from public.venue_stem_block z where z.stem = b.venue_key)
  )
  select coalesce(jsonb_agg(t order by t.long_n desc), '[]'::jsonb) into res
  from (select distinct on (long_key) * from pair order by long_key, rank, short_n desc) t;
  return jsonb_build_object('ok', true, 'pairs', res);
end$$;
