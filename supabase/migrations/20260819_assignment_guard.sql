-- 20260819_assignment_guard.sql
-- 작가 배정이 사라지면 안 되는 데이터라, 두 겹으로 지킨다.
--   ① 이력  : 배정이 바뀌거나 예약이 지워질 때마다 이전 값을 남긴다 → 언제든 되돌릴 수 있다
--   ② 점검  : 배정 수를 주기적으로 찍어두고, 줄어들면 대표에게 바로 알린다
-- 예약 자체가 지워져도 남도록 이름·예식일을 스냅샷으로 함께 보관한다(FK 없음).

create table if not exists public.assignment_audit (
  id            bigserial primary key,
  at            timestamptz not null default now(),
  booking_id    uuid,
  contractor_name text,
  wedding_date  date,
  field         text not null,          -- 'assignee_id'(메인) | 'sub_assignee_id'(서브)
  action        text not null,          -- 'set' | 'change' | 'clear' | 'booking_deleted'
  old_staff_id  uuid, old_staff_name text,
  new_staff_id  uuid, new_staff_name text
);
create index if not exists assignment_audit_at_idx on public.assignment_audit (at desc);
create index if not exists assignment_audit_booking_idx on public.assignment_audit (booking_id);
alter table public.assignment_audit enable row level security;
revoke all on public.assignment_audit from anon, authenticated;

create or replace function private.log_assignment_change()
returns trigger language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare
  nm text := coalesce(new.contractor_name, old.contractor_name);
  wd date := coalesce(new.wedding_date, old.wedding_date);
  bid uuid := coalesce(new.id, old.id);
  sname text;
begin
  if tg_op = 'DELETE' then
    if old.assignee_id is not null then
      select name into sname from public.staff where id = old.assignee_id;
      insert into public.assignment_audit (booking_id, contractor_name, wedding_date, field, action, old_staff_id, old_staff_name)
      values (bid, old.contractor_name, old.wedding_date, 'assignee_id', 'booking_deleted', old.assignee_id, sname);
    end if;
    if old.sub_assignee_id is not null then
      select name into sname from public.staff where id = old.sub_assignee_id;
      insert into public.assignment_audit (booking_id, contractor_name, wedding_date, field, action, old_staff_id, old_staff_name)
      values (bid, old.contractor_name, old.wedding_date, 'sub_assignee_id', 'booking_deleted', old.sub_assignee_id, sname);
    end if;
    return old;
  end if;

  if new.assignee_id is distinct from old.assignee_id then
    insert into public.assignment_audit (booking_id, contractor_name, wedding_date, field, action,
      old_staff_id, old_staff_name, new_staff_id, new_staff_name)
    values (bid, nm, wd, 'assignee_id',
      case when old.assignee_id is null then 'set' when new.assignee_id is null then 'clear' else 'change' end,
      old.assignee_id, (select name from public.staff where id = old.assignee_id),
      new.assignee_id, (select name from public.staff where id = new.assignee_id));
  end if;
  if new.sub_assignee_id is distinct from old.sub_assignee_id then
    insert into public.assignment_audit (booking_id, contractor_name, wedding_date, field, action,
      old_staff_id, old_staff_name, new_staff_id, new_staff_name)
    values (bid, nm, wd, 'sub_assignee_id',
      case when old.sub_assignee_id is null then 'set' when new.sub_assignee_id is null then 'clear' else 'change' end,
      old.sub_assignee_id, (select name from public.staff where id = old.sub_assignee_id),
      new.sub_assignee_id, (select name from public.staff where id = new.sub_assignee_id));
  end if;
  return new;
end$fn$;

drop trigger if exists trg_assignment_audit_upd on public.bookings;
create trigger trg_assignment_audit_upd
  after update of assignee_id, sub_assignee_id on public.bookings
  for each row execute function private.log_assignment_change();

drop trigger if exists trg_assignment_audit_del on public.bookings;
create trigger trg_assignment_audit_del
  after delete on public.bookings
  for each row execute function private.log_assignment_change();

-- ── ② 정기 점검 ───────────────────────────────────────────────
create table if not exists private.health_snapshot (
  at                timestamptz primary key default now(),
  upcoming_total    int not null,   -- 앞으로 예식(취소 제외)
  upcoming_assigned int not null,   -- 그중 메인 작가가 있는 건
  sub_assigned      int not null,
  staff_active      int not null,
  checks_total      int not null    -- 작가 확인 기록
);

create or replace function private.assignment_health_check()
returns jsonb language plpgsql security definer set search_path = public, private, extensions, pg_temp as $fn$
declare cur record; prev record; msgs text[] := '{}'; cleared int;
begin
  select
    (select count(*) from public.bookings where status <> '취소' and wedding_date >= current_date) as upcoming_total,
    (select count(*) from public.bookings where status <> '취소' and wedding_date >= current_date and assignee_id is not null) as upcoming_assigned,
    (select count(*) from public.bookings where status <> '취소' and wedding_date >= current_date and sub_assignee_id is not null) as sub_assigned,
    (select count(*) from public.staff where active) as staff_active,
    (select count(*) from public.assignment_checks) as checks_total
  into cur;

  select * into prev from private.health_snapshot order by at desc limit 1;

  if prev is not null then
    if cur.upcoming_assigned < prev.upcoming_assigned then
      msgs := msgs || ('작가 배정 ' || (prev.upcoming_assigned - cur.upcoming_assigned) || '건 줄어듦 ('
                       || prev.upcoming_assigned || '→' || cur.upcoming_assigned || ')');
    end if;
    if cur.sub_assigned < prev.sub_assigned then
      msgs := msgs || ('서브 배정 ' || (prev.sub_assigned - cur.sub_assigned) || '건 줄어듦');
    end if;
    if cur.staff_active < prev.staff_active then
      msgs := msgs || ('활성 작가 ' || (prev.staff_active - cur.staff_active) || '명 줄어듦');
    end if;
    if cur.checks_total < prev.checks_total then
      msgs := msgs || ('작가 확인기록 ' || (prev.checks_total - cur.checks_total) || '건 줄어듦');
    end if;
  end if;

  -- 짧은 시간에 배정이 여러 건 풀린 경우(사고 신호). 한 건씩 재배정하는 정상 작업과 구분.
  select count(*) into cleared from public.assignment_audit
   where action in ('clear', 'booking_deleted') and at > now() - interval '1 hour';
  if cleared >= 3 then
    msgs := msgs || ('최근 1시간 배정 해제·삭제 ' || cleared || '건');
  end if;

  insert into private.health_snapshot (upcoming_total, upcoming_assigned, sub_assigned, staff_active, checks_total)
  values (cur.upcoming_total, cur.upcoming_assigned, cur.sub_assigned, cur.staff_active, cur.checks_total);

  if array_length(msgs, 1) > 0 then
    perform private.otb_push('🚨 배정 데이터 이상', array_to_string(msgs, ' · ') || ' — 관리자에서 확인하세요.', '/admin');
  end if;

  return jsonb_build_object('ok', array_length(msgs, 1) is null, 'warnings', to_jsonb(msgs),
                            'upcoming_assigned', cur.upcoming_assigned, 'staff_active', cur.staff_active);
end$fn$;

do $cron$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'otb-assignment-health') then
      perform cron.unschedule('otb-assignment-health');
    end if;
    perform cron.schedule('otb-assignment-health', '7 * * * *', 'select private.assignment_health_check();');  -- 매시 7분
  end if;
end$cron$;

-- ── 관리자 조회 ───────────────────────────────────────────────
create or replace function public.admin_assignment_audit(p_days int default 30)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare n_days int := least(greatest(coalesce(p_days, 30), 1), 365); res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select jsonb_build_object(
    'now', (select jsonb_build_object(
        'upcoming_total', count(*),
        'upcoming_assigned', count(*) filter (where assignee_id is not null),
        'unassigned_soon', count(*) filter (where assignee_id is null and wedding_date <= current_date + 14))
      from public.bookings where status <> '취소' and wedding_date >= current_date),
    'last_check', (select jsonb_build_object('at', at, 'upcoming_assigned', upcoming_assigned)
      from private.health_snapshot order by at desc limit 1),
    'items', coalesce((select jsonb_agg(t order by t.at desc) from (
        select at, booking_id, contractor_name, wedding_date, field, action,
               old_staff_name, new_staff_name
        from public.assignment_audit
        where at > now() - (n_days || ' days')::interval
        order by at desc limit 100) t), '[]'::jsonb)
  ) into res;
  return res;
end$fn$;
revoke all on function public.admin_assignment_audit(int) from public, anon;
grant execute on function public.admin_assignment_audit(int) to authenticated;

-- 첫 스냅샷
select private.assignment_health_check();

-- 스냅샷 키 수정: now() 는 트랜잭션 시작 시각이라 같은 트랜잭션에서 두 번 점검하면 PK 충돌.
-- 시각을 키로 쓰지 말고 일련번호를 쓰고, 시각은 clock_timestamp() 로 실제 순간을 기록한다.
alter table private.health_snapshot add column if not exists id bigserial;
alter table private.health_snapshot drop constraint if exists health_snapshot_pkey;
alter table private.health_snapshot add primary key (id);
alter table private.health_snapshot alter column at set default clock_timestamp();
create index if not exists health_snapshot_at_idx on private.health_snapshot (at desc);
