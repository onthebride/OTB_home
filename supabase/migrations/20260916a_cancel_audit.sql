-- 예식이 취소되면 배정이력에도 남긴다 (대표 2026-09-16)
--   «예식 취소로 배정이 취소된건 배정이력에 반영이 안되네? 그것만 해도 될꺼 같은데»
--
-- 맞는 지적이다. 지금까지 배정이력(public.assignment_audit)은 **배정 칸이 바뀔 때만** 남았다
-- (trg_assignment_audit_upd 는 update of assignee_id, sub_assignee_id 다).
-- 예식을 취소하면 배정 칸은 그대로라 이력에 한 줄도 안 남는다. 그런데
--   · 작가 캘린더에서는 그 예식이 사라지고 (staff_calendar 가 취소를 거른다)
--   · private.assignment_health_check() 의 배정 수도 하나 줄고
--     (upcoming_assigned = status <> '취소' and wedding_date >= today and assignee_id is not null)
--   · 그래서 매시 7분 점검에서 「🚨 작가 배정 1건 줄어듦」 이 대표 폰으로 간다
-- 이력에는 아무것도 없으니 **왜 줄었는지 알 길이 없었다.**
-- 2026-09-16 11:24 에 2월 21일 예식(신부 서은영)을 취소하셨을 때가 바로 그 경우다.
--
-- ⚠ 배정 칸은 **건드리지 않는다.** «배정된거 내가 수정하는게아니면 절대 없어지면 안됨»
--   (2026-08-29 대표 지시, CLAUDE.md 절대 규칙). 자동으로 비우는 코드는 만들지 않는다.
--   여기서 하는 일은 **적어두는 것뿐**이다. 취소를 풀면 배정은 그대로 살아 있다.
--
-- ⚠ 경보는 그대로 울린다. 2026-09-11 대표 «아니 울리게 하자» —
--   대표가 직접 한 일이라도 배정 수가 줄면 울리는 게 맞다. 이 이력은 울린 뒤
--   「왜 줄었나」 를 바로 알게 해주는 것이지, 경보를 끄는 것이 아니다.

/* ===== 취소·취소해제를 배정이력에 남긴다 =====
   ⚠ 남기는 대상은 **바뀐 뒤에도 그 줄에 붙어 있는 작가**(new.*)다.
     같은 UPDATE 에서 배정까지 함께 뺐다면 그건 trg_assignment_audit_upd 가
     이미 'clear' 로 남긴다 — 여기서 또 남기면 한 가지 일이 두 줄이 된다. */
create or replace function private.log_booking_cancel_assignment()
returns trigger language plpgsql security definer
set search_path to 'private', 'public', 'pg_temp' as $fn$
declare
  act text;
  nm text := coalesce(new.contractor_name, old.contractor_name);
  wd date := coalesce(new.wedding_date, old.wedding_date);
begin
  if new.status = '취소' and old.status is distinct from '취소' then
    act := 'booking_cancelled';
  elsif old.status = '취소' and new.status is distinct from '취소' then
    act := 'booking_restored';
  else
    return new;
  end if;

  if new.assignee_id is not null then
    insert into public.assignment_audit (booking_id, contractor_name, wedding_date, field, action,
      old_staff_id, old_staff_name, new_staff_id, new_staff_name)
    -- 취소는 «있던 사람이 빠진다» → old 칸에, 취소 해제는 «되돌아온다» → new 칸에 적는다.
    -- 화면(admin.js 의 who)이 그 규칙으로 이름을 고른다
    values (new.id, nm, wd, 'assignee_id', act,
      case when act = 'booking_cancelled' then new.assignee_id end,
      case when act = 'booking_cancelled' then (select name from public.staff where id = new.assignee_id) end,
      case when act = 'booking_restored' then new.assignee_id end,
      case when act = 'booking_restored' then (select name from public.staff where id = new.assignee_id) end);
  end if;

  if new.sub_assignee_id is not null then
    insert into public.assignment_audit (booking_id, contractor_name, wedding_date, field, action,
      old_staff_id, old_staff_name, new_staff_id, new_staff_name)
    values (new.id, nm, wd, 'sub_assignee_id', act,
      case when act = 'booking_cancelled' then new.sub_assignee_id end,
      case when act = 'booking_cancelled' then (select name from public.staff where id = new.sub_assignee_id) end,
      case when act = 'booking_restored' then new.sub_assignee_id end,
      case when act = 'booking_restored' then (select name from public.staff where id = new.sub_assignee_id) end);
  end if;

  return new;
end$fn$;
revoke all on function private.log_booking_cancel_assignment() from public, anon, authenticated;

/* ⚠ update of status 로 좁힌다. bookings 는 칸 하나만 고쳐도 트리거가 다 도는 표라
     (trg_booking_change_notify 가 그렇다) 조건을 트리거 쪽에 두어 헛도는 것을 줄인다 */
drop trigger if exists trg_assignment_audit_cancel on public.bookings;
create trigger trg_assignment_audit_cancel
  after update of status on public.bookings
  for each row execute function private.log_booking_cancel_assignment();

/* ===== 이미 취소된 것 메우기 =====
   지금 「취소인데 배정이 남아 있는」 예약이 다섯 건 있다. 그중 셋은 취소될 때
   작가에게 나간 알림(public.staff_notice kind='cancel')이 남아 있어 **취소한 시각을 안다.**
   그 시각 그대로 이력에 넣는다.
   ⚠ 나머지 둘은 알림 표가 생기기(2026-08-27) 전에 취소된 것이라 시각을 모른다.
     모르는 시각을 지어내 넣지 않는다 — 감사 기록에 거짓을 넣는 것이 된다. 그냥 둔다.
   ⚠ 두 번 돌려도 늘지 않게 이미 있는 줄은 건너뛴다. */
insert into public.assignment_audit (at, booking_id, contractor_name, wedding_date, field, action,
  old_staff_id, old_staff_name)
select n.at, b.id, b.contractor_name, b.wedding_date, f.field, 'booking_cancelled',
       f.staff_id, (select name from public.staff where id = f.staff_id)
from public.bookings b
join lateral (
  select max(sn.created_at) as at from public.staff_notice sn
   where sn.booking_id = b.id and sn.kind = 'cancel') n on n.at is not null
join lateral (
  select 'assignee_id'::text as field, b.assignee_id as staff_id where b.assignee_id is not null
  union all
  select 'sub_assignee_id', b.sub_assignee_id where b.sub_assignee_id is not null) f on true
where b.status = '취소'
  and not exists (select 1 from public.assignment_audit a
                   where a.booking_id = b.id and a.field = f.field and a.action = 'booking_cancelled');
