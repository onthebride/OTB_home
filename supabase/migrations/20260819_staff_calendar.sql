-- 20260819_staff_calendar.sql
-- 작가별 캘린더 1단계: 작가가 스스로 '안 되는 날'과 '다른 일정'을 등록하고,
-- 우리 배정과 합쳐서 그 날 배정이 가능한지 판단할 수 있게 한다.
--
-- 대표 규칙:
--   · 날짜를 그냥 찍으면 그날은 불가 (kind='off')
--   · 다른 촬영이 있으면 시간·장소를 적게 하고(kind='busy'), 우리 예식과 4시간 이상
--     벌어져 있으면 배정 가능. 하루 두 건 촬영은 일반적이라 막지 않는다.

create table if not exists public.staff_busy (
  id         bigserial primary key,
  staff_id   uuid not null references public.staff(id) on delete cascade,
  the_date   date not null,
  kind       text not null check (kind in ('off', 'busy')),
  at_time    text,                       -- 'HH:MM' (busy 일 때만)
  place      text,                       -- 촬영 장소 (busy 일 때만)
  note       text,
  created_at timestamptz not null default now()
);
create index if not exists staff_busy_idx on public.staff_busy (staff_id, the_date);
-- 하루 전체 불가는 날짜당 하나면 충분
create unique index if not exists staff_busy_off_uniq on public.staff_busy (staff_id, the_date) where kind = 'off';
alter table public.staff_busy enable row level security;
revoke all on public.staff_busy from anon, authenticated;

-- 같은 날 두 일정이 붙어 있는지 (4시간 미만이면 위험)
create or replace function private.too_close(t1 text, t2 text, p_hours int default 4)
returns boolean language sql immutable as $fn$
  select case
    when t1 is null or t2 is null or t1 = '' or t2 = '' then false   -- 시간을 모르면 판단하지 않는다
    else abs(extract(epoch from (t1::time - t2::time))) < p_hours * 3600
  end;
$fn$;

-- ── 작가용 (링크: /staff-calendar?s=<작가ID>) ──────────────────
-- 그 달의 내 배정 + 내가 등록한 일정
create or replace function public.staff_calendar(p_staff_id uuid, p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare st public.staff; res jsonb;
begin
  select * into st from public.staff where id = p_staff_id;
  if not found then return null; end if;
  if p_to < p_from or p_to > p_from + 400 then raise exception 'bad range'; end if;

  select jsonb_build_object(
    'staff_name', st.name,
    'from', p_from, 'to', p_to,
    -- 우리 예식 배정 (연락처는 예식 2주 전부터만 — 그 전엔 필요 없음)
    'bookings', coalesce((select jsonb_agg(x order by x->>'wedding_date', x->>'wedding_time') from (
        select jsonb_build_object(
          'booking_id', b.id, 'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time,
          'wedding_venue', b.wedding_venue,
          'role', case when b.assignee_id = p_staff_id then '메인' else '서브' end,
          'bride_name', b.bride_name, 'groom_name', b.groom_name,
          'bride_phone', case when b.wedding_date <= current_date + 14 then b.bride_phone end,
          'groom_phone', case when b.wedding_date <= current_date + 14 then b.groom_phone end,
          'option_reception', b.option_reception, 'option_pyebaek', b.option_pyebaek,
          'option_part2', b.option_part2, 'photographer', b.photographer, 'rep_designation', b.rep_designation
        ) as x
        from public.bookings b
        where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
          and b.status <> '취소' and b.wedding_date between p_from and p_to) t), '[]'::jsonb),
    -- 작가가 직접 등록한 것
    'busy', coalesce((select jsonb_agg(jsonb_build_object(
          'id', sb.id, 'the_date', sb.the_date, 'kind', sb.kind,
          'at_time', sb.at_time, 'place', sb.place, 'note', sb.note) order by sb.the_date, sb.at_time)
        from public.staff_busy sb
        where sb.staff_id = p_staff_id and sb.the_date between p_from and p_to), '[]'::jsonb)
  ) into res;
  return res;
end$fn$;
revoke all on function public.staff_calendar(uuid, date, date) from public;
grant execute on function public.staff_calendar(uuid, date, date) to anon, authenticated;

-- 작가가 '안 되는 날' / '다른 일정' 등록
create or replace function public.staff_busy_add(p_staff_id uuid, p_date date, p_kind text,
                                                 p_time text default null, p_place text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare newid bigint;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and active) then raise exception 'staff not found'; end if;
  if p_kind not in ('off', 'busy') then raise exception 'bad kind'; end if;
  if p_date < current_date - 1 then raise exception '지난 날짜는 등록할 수 없습니다'; end if;
  if p_kind = 'busy' and (p_time is null or p_time !~ '^[0-2][0-9]:[0-5][0-9]$') then
    raise exception '시간을 HH:MM 형식으로 입력해 주세요';
  end if;

  if p_kind = 'off' then
    -- 하루 전체 불가면 그날 다른 일정 기록은 의미가 없으니 정리
    delete from public.staff_busy where staff_id = p_staff_id and the_date = p_date;
    insert into public.staff_busy (staff_id, the_date, kind, note) values (p_staff_id, p_date, 'off', nullif(p_note,''))
    returning id into newid;
  else
    delete from public.staff_busy where staff_id = p_staff_id and the_date = p_date and kind = 'off';
    insert into public.staff_busy (staff_id, the_date, kind, at_time, place, note)
    values (p_staff_id, p_date, 'busy', p_time, nullif(p_place,''), nullif(p_note,''))
    returning id into newid;
  end if;
  return jsonb_build_object('ok', true, 'id', newid);
end$fn$;
revoke all on function public.staff_busy_add(uuid, date, text, text, text, text) from public;
grant execute on function public.staff_busy_add(uuid, date, text, text, text, text) to anon, authenticated;

create or replace function public.staff_busy_del(p_staff_id uuid, p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
begin
  delete from public.staff_busy where id = p_id and staff_id = p_staff_id;   -- 본인 것만
  return jsonb_build_object('ok', found);
end$fn$;
revoke all on function public.staff_busy_del(uuid, bigint) from public;
grant execute on function public.staff_busy_del(uuid, bigint) to anon, authenticated;

-- ── 관리자: 특정 날짜·시간에 배정 가능한 작가 ─────────────────
-- status: 'ok'(문제 없음) | 'tight'(4시간 안에 다른 일정) | 'off'(작가가 불가로 찍음)
create or replace function public.admin_staff_availability(p_date date, p_time text default null)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(t order by (t.status <> 'ok'), t.name), '[]'::jsonb) into res from (
    select s.id, s.name,
      case when exists(select 1 from public.staff_busy sb
                        where sb.staff_id = s.id and sb.the_date = p_date and sb.kind = 'off') then 'off'
           when exists(select 1 from public.staff_busy sb
                        where sb.staff_id = s.id and sb.the_date = p_date and sb.kind = 'busy'
                          and private.too_close(sb.at_time, p_time)) then 'tight'
           when exists(select 1 from public.bookings b
                        where (b.assignee_id = s.id or b.sub_assignee_id = s.id)
                          and b.status <> '취소' and b.wedding_date = p_date
                          and private.too_close(b.wedding_time, p_time)) then 'tight'
           else 'ok' end as status,
      -- 그날 이미 있는 일정(우리 예식 + 본인 등록) 요약
      coalesce((select string_agg(x, ' / ' order by x) from (
          select coalesce(public.fmt_ktime(b.wedding_time), '시간미정') || ' ' || coalesce(b.wedding_venue,'') as x
          from public.bookings b
          where (b.assignee_id = s.id or b.sub_assignee_id = s.id)
            and b.status <> '취소' and b.wedding_date = p_date
          union all
          select coalesce(public.fmt_ktime(sb.at_time), '하루 불가')
                 || coalesce(' ' || nullif(sb.place,''), '') || ' (본인 등록)'
          from public.staff_busy sb where sb.staff_id = s.id and sb.the_date = p_date) u), '') as detail
    from public.staff s where s.active
  ) t;
  return res;
end$fn$;
revoke all on function public.admin_staff_availability(date, text) from public, anon;
grant execute on function public.admin_staff_availability(date, text) to authenticated;
