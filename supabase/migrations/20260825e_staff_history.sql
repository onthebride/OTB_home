-- 지난 촬영 이력 (2018~) — 작가가 어느 예식장에 몇 번 갔는지.
-- 대표가 네이버웍스 캘린더 .ics 5개를 줘서 읽어 넣는다 (2026-08-25).
--
-- **예약(public.bookings)과 섞지 않는다.** 매출·순이익 통계가 실제 예약 기준이라
-- 여기 3,256건을 섞으면 숫자가 통째로 틀어진다. 이 표는 «어디에 가봤나» 만 본다.
--
-- 캘린더 한 줄 생김새:
--   SUMMARY:ㅇ-[양재훈] 홍길동 : 스페셜/11시/보타닉파크웨딩
--   LOCATION:ㅇ-이병호                     ← 서브 작가
--   DESCRIPTION: … * 예식장소 : 상암 월드컵컨벤션 …
-- 대괄호 안이 메인 작가다. 「대표」로 적힌 것은 김병훈이다 (대표 확인).
-- 「@ 고객명」 은 작가 미정이라 뺀다 (대표 지시 «작가에 이름 없는 사람은 패스»).
--
-- 고객 이름·연락처는 **넣지 않는다.** 날짜·예식장·작가만 넣는다. 이 표에는 개인정보가 없다.

create table if not exists public.staff_history (
  id          bigint generated always as identity primary key,
  shot_on     date not null,
  venue       text not null,
  venue_key   text not null,              -- private.venue_key(venue) — 이름이 제각각이라 묶어서 센다
  staff_name  text not null,              -- 캘린더에 적힌 이름 그대로 (그만둔 분도 있다)
  staff_id    uuid references public.staff(id) on delete set null,   -- 지금 명단에 있으면 이어둔다
  as_sub      boolean not null default false,
  source      text not null default 'ics',
  created_at  timestamptz not null default now(),
  unique (shot_on, venue_key, staff_name, as_sub)   -- 같은 날 같은 곳 같은 사람은 한 번만
);

create index if not exists staff_history_staff_idx on public.staff_history (staff_id);
create index if not exists staff_history_vkey_idx  on public.staff_history (venue_key);
create index if not exists staff_history_date_idx  on public.staff_history (shot_on);

comment on table public.staff_history is
  '지난 촬영 이력(2018~). 캘린더에서 읽어 넣는다. 예약(bookings)과 별개 — 매출 통계에는 안 쓴다';

-- ⚠ 이 표에는 고객 정보가 절대 들어오면 안 된다.
-- 2026-08-25 사고: 캘린더를 읽는 쪽에서 「예식장소 :」 뒤를 한 줄로 안 끊는 바람에
-- 이름·전화번호가 통째로 예식장 칸에 들어갔다 (350줄). 지우고 다시 넣었다.
-- 화면 쪽만 고치면 다음에 또 당한다. DB 에서 막는다.
alter table public.staff_history drop constraint if exists staff_history_venue_clean;
alter table public.staff_history add constraint staff_history_venue_clean check (
  length(venue) <= 60
  and venue !~ '[0-9]{3}-?[0-9]{4}-?[0-9]{4}'          -- 전화번호
  and venue !~ '(연락처|성함|신부님|신랑님|예식시간|포스팅|이메일)'
  and venue not like '%' || chr(10) || '%'              -- 줄바꿈이 들어왔다는 건 여러 줄이 딸려온 것
);

-- 관리자만 본다 (개인정보는 없지만 우리 영업 자료다)
alter table public.staff_history enable row level security;
revoke all on public.staff_history from anon, authenticated;


-- ===== 넣기 (관리자) =====
-- 같은 자료를 두 번 넣어도 늘어나지 않는다 (unique + on conflict do nothing)
create or replace function public.admin_staff_history_load(payload jsonb)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare n_in int; n_before int;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select count(*) into n_before from public.staff_history;

  with src as (
    select (x->>'date')::date            as shot_on,
           trim(x->>'venue')             as venue,
           trim(x->>'staff')             as staff_name,
           coalesce((x->>'as_sub')::boolean, false) as as_sub
    from jsonb_array_elements(payload) x
  ),
  good as (
    select shot_on, venue, private.venue_key(venue) as vkey, staff_name, as_sub
    from src
    where shot_on is not null and coalesce(venue,'') <> '' and coalesce(staff_name,'') <> ''
      and coalesce(private.venue_key(venue), '') <> ''
  )
  insert into public.staff_history (shot_on, venue, venue_key, staff_name, staff_id, as_sub)
  select g.shot_on, g.venue, g.vkey, g.staff_name,
         -- 지금 명단에 있으면 이어 둔다. 「최선종(서브)」 처럼 꼬리가 붙어 있어도 맞춘다
         (select s.id from public.staff s
           where regexp_replace(s.name, '\s*[(（][^)）]*[)）]', '', 'g') = g.staff_name limit 1),
         g.as_sub
  from good g
  on conflict (shot_on, venue_key, staff_name, as_sub) do nothing;
  get diagnostics n_in = row_count;

  return jsonb_build_object('ok', true, 'inserted', n_in,
    'before', n_before, 'total', (select count(*) from public.staff_history));
end$$;

-- 이름이 나중에 명단에 들어온 경우(새로 등록한 작가) 다시 이어 준다
create or replace function public.admin_staff_history_relink()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.staff_history h
     set staff_id = s.id
    from public.staff s
   where h.staff_id is null
     and regexp_replace(s.name, '\s*[(（][^)）]*[)）]', '', 'g') = h.staff_name;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'linked', n,
    'still_unlinked', (select count(*) from public.staff_history where staff_id is null));
end$$;
