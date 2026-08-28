-- 작가가 캘린더를 「열었다」 는 기록 (대표 요청 2026-08-28 «이거 접속 기록이 있음 좋을거 같은데»)
--
-- 지금까지는 작가가 캘린더를 보는지 알 방법이 없었다. 불가일을 안 적었다고 해서
-- 「안 봤다」 고 할 수는 없다 — 진짜로 다 가능했을 수도 있다. 그래서 여는 순간을 남긴다.
--
-- ⚠ 작가는 로그인을 하지 않는다. 링크에 실린 작가 번호로만 가린다.
--   그래서 이 함수는 «틀리면 조용히 아무것도 안 한다» — 화면이 깨지면 안 된다.
-- ⚠ 하루에 여러 번 열어도 줄은 하루에 하나. 15명이 매일 봐도 1년에 5천 줄쯤이다.

alter table public.staff add column if not exists last_seen_at timestamptz;

create table if not exists public.staff_visit (
  staff_id  uuid not null references public.staff(id) on delete cascade,
  the_day   date not null,
  n         int  not null default 1,          -- 그날 몇 번 열었나
  first_at  timestamptz not null default now(),
  last_at   timestamptz not null default now(),
  primary key (staff_id, the_day)
);
alter table public.staff_visit enable row level security;
-- 표를 직접 읽고 쓸 일은 없다. 아래 함수들로만 오간다
revoke all on table public.staff_visit from anon, authenticated;

-- 작가 화면이 열릴 때 부른다. 실패해도 화면은 그대로 돌아가야 하므로 예외를 던지지 않는다
create or replace function public.staff_seen(p_staff_id uuid)
returns void language plpgsql security definer set search_path=public, pg_temp as $$
declare d date := (now() at time zone 'Asia/Seoul')::date;
begin
  if p_staff_id is null then return; end if;
  if not exists (select 1 from public.staff where id = p_staff_id and coalesce(active,false)) then
    return;                                   -- 없는 사람·쉬는 사람이면 조용히 지나간다
  end if;
  insert into public.staff_visit (staff_id, the_day) values (p_staff_id, d)
  on conflict (staff_id, the_day) do update
    set n = public.staff_visit.n + 1, last_at = now();
  update public.staff set last_seen_at = now() where id = p_staff_id;
end$$;
revoke all on function public.staff_seen(uuid) from public;
grant execute on function public.staff_seen(uuid) to anon, authenticated;

-- 대표가 보는 요약 — 작가별 «마지막 접속 · 최근 며칠 들어왔나 · 몇 번 열었나»
create or replace function public.admin_staff_visits(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path=public, pg_temp as $$
declare res jsonb; dd int := greatest(1, least(coalesce(p_days, 30), 400));
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_object_agg(t.staff_id, jsonb_build_object(
    'last', t.last_at, 'days', t.days, 'opens', t.opens, 'first', t.first_day)), '{}'::jsonb) into res
  from (
    select v.staff_id::text as staff_id,
           max(v.last_at) as last_at,
           count(*) filter (where v.the_day > (now() at time zone 'Asia/Seoul')::date - dd)::int as days,
           coalesce(sum(v.n) filter (where v.the_day > (now() at time zone 'Asia/Seoul')::date - dd), 0)::int as opens,
           min(v.the_day) as first_day
    from public.staff_visit v
    group by v.staff_id
  ) t;
  return res;
end$$;
revoke all on function public.admin_staff_visits(int) from public, anon;
grant execute on function public.admin_staff_visits(int) to authenticated;
