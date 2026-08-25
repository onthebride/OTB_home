-- 예식장 묶기 고침. 대표 신고 2026-08-25:
--   「상록아트홀을 내가 한달에만 10번넘게 간적이 있는데 정확한거야?」
-- 확인해보니 대표 상록아트홀 기록 32회가 19조각으로 흩어져 9회로만 세어지고 있었다.
--
-- 무엇이 잘못됐나 —
-- 옛 규칙은 「홀·볼룸·층·룸 으로 끝나는 낱말」을 통째로 뺐다.
-- 「아펠가모 광화문 그랜드홀」 = 「광화문 아펠가모」 로 묶으려던 것인데,
-- **이름 자체가 홀로 끝나는 예식장**이 무너졌다:
--     상록아트홀              → 낱말이 하나뿐인데 그게 빠져서 빈 값 → 원문으로 되돌아감
--     상록아트홀 아트홀        → 둘 다 빠져서 빈 값 → 원문 「상록아트홀 아트홀」 (안 묶임)
--     상록아트홀(선릉)         → 「선릉」만 남음        ← 이름이 사라졌다
--     서울 강남 상록아트홀      → 「강남서울」          ← 이름이 사라졌다
--
-- 새 규칙 —
--  1. 괄호 안은 뗀다. 거의 전부 홀 이름이나 메모다 (「(선릉)」「(어두운홀)」「(통창 밝은홀)」)
--  2. **낱말 꼬리로 판단하지 않는다.** 홀 이름으로만 쓰이는 낱말을 목록으로 못박아 그것만 뺀다
--     (아트홀·그랜드볼룸·채플홀·N층·L층 …). 「상록아트홀」은 목록에 없으니 살아남는다
--  3. 다 빼서 아무것도 안 남으면 빼기 전으로 되돌린다 (이름이 사라지는 일이 없게)
--  4. 남은 낱말을 정렬해 이어붙인다 — 「광화문 아펠가모」와 「아펠가모 광화문」이 같아지게
--
-- 지역이 앞에 붙은 것(「서울 강남 상록아트홀」)은 이것만으로는 안 묶인다.
-- 그건 아래 venue_alias 로 잇는다.

create or replace function private.venue_key(v text)
returns text language sql immutable as $$
  with base as (
    -- 괄호 안은 뗀다. 그 다음 글자·숫자만 남기고 낱말로 쪼갠다
    select w from unnest(string_to_array(
      regexp_replace(
        regexp_replace(lower(coalesce(v, '')), '[(（\[][^)）\]]*[)）\]]', ' ', 'g'),
        '[^[:alnum:]]+', ' ', 'g'), ' ')) w
    where w <> ''
  ),
  kept as (
    select w from base
    -- 홀·층 이름으로만 쓰이는 낱말. 여기 없는 말은 예식장 이름의 일부로 본다.
    -- 꼬리가 「홀」이라고 무조건 빼면 상록«아트홀» 같은 이름이 통째로 사라진다
    where w !~ '^([0-9]+|[a-z]|지하|b)?층$'
      and w not in ('아트홀','그랜드볼룸','그랜드볼룸홀','그랜드홀','볼룸','채플홀','컨벤션홀',
                    '웨딩홀','연회홀','연회장','대연회장','본홀','신관','별관','본관','홀',
                    '가든홀','크리스탈홀','다이아몬드홀','에메랄드홀','루비홀','사파이어홀',
                    '펄홀','아이보리홀','화이트홀','블랑홀','그레이스홀','로즈홀','릴리홀',
                    '스타홀','문홀','썬홀','제니스홀','노블레스홀','프레지던트홀','마리에홀')
  )
  select coalesce(
    -- 뺄 것 빼고 남은 것
    nullif((select string_agg(w, '' order by w) from kept), ''),
    -- 다 빠졌으면 빼기 전으로 (이름이 사라지느니 안 묶이는 게 낫다)
    nullif((select string_agg(w, '' order by w) from base), ''),
    ''
  )
$$;


-- ===== 같은 곳인데 규칙만으로는 안 묶이는 것들 =====
-- 「서울 강남 상록아트홀」·「상록웨딩홀」 처럼 지역이 앞에 붙거나 예전 이름으로 적힌 것.
-- 규칙을 더 세게 만들면 다른 곳까지 잘못 묶이므로, 이런 건 하나씩 이어준다.
create table if not exists public.venue_alias (
  from_key   text primary key,
  to_key     text not null,
  note       text,
  created_at timestamptz not null default now(),
  check (from_key <> to_key)
);
alter table public.venue_alias enable row level security;
revoke all on public.venue_alias from anon, authenticated;

comment on table public.venue_alias is
  '같은 예식장인데 venue_key 로는 안 묶이는 것을 잇는다 (지역이 앞에 붙거나 예전 이름)';

-- 이어준 뒤의 «진짜» 묶음키. 표를 읽으므로 immutable 이 아니라 stable 이다
create or replace function private.venue_canon(v text)
returns text language sql stable
set search_path to 'private', 'public', 'pg_temp'
as $$
  select coalesce((select a.to_key from public.venue_alias a where a.from_key = private.venue_key(v)),
                  private.venue_key(v))
$$;

-- 이미 만들어 둔 키에도 쓸 수 있게 (staff_history.venue_key 는 값으로 들고 있다)
create or replace function private.venue_canon_key(k text)
returns text language sql stable
set search_path to 'private', 'public', 'pg_temp'
as $$
  select coalesce((select a.to_key from public.venue_alias a where a.from_key = k), k)
$$;

revoke all on function private.venue_canon(text) from public, anon, authenticated;
revoke all on function private.venue_canon_key(text) from public, anon, authenticated;


-- ===== 규칙이 바뀌었으니 이력의 묶음키를 다시 계산한다 =====
-- 새 규칙으로 묶이면 «같은 날·같은 곳·같은 사람» 이 겹치게 된다 — 그게 고쳐졌다는 뜻이다.
-- (예: 같은 날 「상록아트홀」과 「상록아트홀 5층 아트홀」이 따로 들어와 있던 것)
-- 겹치는 것은 먼저 하나만 남기고 지운 다음에 키를 바꾼다. 안 그러면 unique 에 걸린다
delete from public.staff_history a
 using public.staff_history b
 where a.id > b.id
   and a.shot_on = b.shot_on
   and a.staff_name = b.staff_name
   and a.as_sub = b.as_sub
   and private.venue_key(a.venue) = private.venue_key(b.venue);

update public.staff_history set venue_key = private.venue_key(venue)
 where venue_key is distinct from private.venue_key(venue);


-- ===== 이어주기 관리 =====
create or replace function public.admin_venue_alias_set(p_from text, p_to text, p_note text default null)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare a text; b text; n int;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  a := private.venue_key(p_from);
  b := private.venue_key(p_to);
  if coalesce(a,'') = '' or coalesce(b,'') = '' then raise exception '예식장 이름이 비어 있습니다'; end if;
  if a = b then return jsonb_build_object('ok', true, 'same', true, 'key', a); end if;
  insert into public.venue_alias (from_key, to_key, note) values (a, b, p_note)
    on conflict (from_key) do update set to_key = excluded.to_key, note = excluded.note;
  select count(*) into n from public.staff_history where venue_key = a;
  return jsonb_build_object('ok', true, 'from', a, 'to', b, 'moved', n);
end$$;

create or replace function public.admin_venue_alias_del(p_from text)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  delete from public.venue_alias where from_key = private.venue_key(p_from);
  return jsonb_build_object('ok', true);
end$$;

-- 안 묶인 채 남아 있는 것 찾기 — 한 이름이 다른 이름 안에 통째로 들어 있으면 같은 곳일 가능성이 높다.
-- 자동으로 잇지는 않는다. 대표가 보고 고르게 목록만 낸다
create or replace function public.admin_venue_alias_suggest(p_min integer default 2)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  with k as (
    select venue_key, count(*) n, (array_agg(venue order by shot_on desc))[1] as venue
    from public.staff_history
    where coalesce(venue_key,'') <> ''
    group by 1
  ),
  pair as (
    select a.venue_key as long_key, a.venue as long_venue, a.n as long_n,
           b.venue_key as short_key, b.venue as short_venue, b.n as short_n
    from k a join k b
      on a.venue_key <> b.venue_key
     and length(b.venue_key) >= 5
     and a.venue_key like '%' || b.venue_key || '%'
    where not exists (select 1 from public.venue_alias x where x.from_key = a.venue_key)
      and a.n >= p_min
  )
  select coalesce(jsonb_agg(t order by t.long_n desc), '[]'::jsonb) into res
  from (select distinct on (long_key) * from pair order by long_key, short_n desc) t;
  return jsonb_build_object('ok', true, 'pairs', res);
end$$;
