-- 감시 장치 헛경보 — 한 예약을 여러 번 만진 것을 「여러 건」으로 세고 있었다
--
-- 2026-08-31 18시께, 대표가 배정 알림이 가는지 보시려고 한 예약(11/14 김○)에
-- 배정을 붙였다 뗐다 세 번 하셨다. 그러자 감시 장치가 이렇게 울릴 참이었다.
--
--   🚨 배정 데이터 이상 · 최근 1시간 배정 해제·삭제 3건
--
-- 이 규칙이 노리는 것은 **여러 예식의 배정이 한꺼번에 풀리는 사고**다.
-- 한 예약을 세 번 토글한 것은 그 사고가 아니다. 줄 수가 아니라 **예약 수**를 세야 한다.
--
-- ⚠ CLAUDE.md 「헛경보를 그냥 두지 않는다 — 헛경보가 반복되면 진짜 경보를 안 믿게 된다.
--   원인을 찾아 그날 고친다.」 2026-08-30 에 이어 두 번째다.
--
-- 고친 뒤:
--   · 한 예약을 열 번 토글해도 1건 — 안 울린다
--   · 서로 다른 예약 셋의 배정이 풀리면 3건 — 울린다 (노리던 그 사고)

create or replace function private.assignment_health_check()
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'extensions', 'pg_temp'
as $function$
declare cur record; prev record; msgs text[] := '{}'; cleared int;
begin
  select
    (select count(*) from public.bookings where status <> '취소' and wedding_date >= current_date) as upcoming_total,
    (select count(*) from public.bookings where status <> '취소' and wedding_date >= current_date and assignee_id is not null) as upcoming_assigned,
    (select count(*) from public.bookings where status <> '취소' and wedding_date >= current_date and sub_assignee_id is not null) as sub_assigned,
    -- ⚠ 경보는 이 둘로만 본다. 날짜·취소와 무관해서 시간이 지나도 안 줄어든다
    (select count(*) from public.bookings where assignee_id is not null) as assigned_all,
    (select count(*) from public.bookings where sub_assignee_id is not null) as sub_all,
    (select count(*) from public.staff where active) as staff_active,
    (select count(*) from public.assignment_checks) as checks_total
  into cur;

  -- 칸이 새로 생긴 뒤의 것만 견준다. 옛 줄에는 assigned_all 이 비어 있어 못 견준다
  select * into prev from private.health_snapshot
   where assigned_all is not null order by at desc limit 1;

  if prev is not null then
    if cur.assigned_all < prev.assigned_all then
      msgs := msgs || ('작가 배정 ' || (prev.assigned_all - cur.assigned_all) || '건 줄어듦 ('
                       || prev.assigned_all || '→' || cur.assigned_all || ')');
    end if;
    if cur.sub_all < prev.sub_all then
      msgs := msgs || ('서브 배정 ' || (prev.sub_all - cur.sub_all) || '건 줄어듦');
    end if;
    if cur.staff_active < prev.staff_active then
      msgs := msgs || ('활성 작가 ' || (prev.staff_active - cur.staff_active) || '명 줄어듦');
    end if;
    if cur.checks_total < prev.checks_total then
      msgs := msgs || ('작가 확인기록 ' || (prev.checks_total - cur.checks_total) || '건 줄어듦');
    end if;
  end if;

  /* 짧은 시간에 배정이 여러 건 풀린 경우(사고 신호). 한 건씩 재배정하는 정상 작업과 구분.
     ⚠ **예약 수**를 센다(distinct booking_id). 줄 수를 세면 한 예약을 붙였다 뗐다 하신
       것만으로 울린다 — 2026-08-31 에 실제로 그럴 뻔했다.
       지금도 배정이 남아 있는 예약은 빼지 않는다. 풀렸다가 다시 붙은 것도 봐야 하지만,
       그 사이에 알림이 나갔을 수 있어 «있었던 일» 로 세는 것이 맞다 */
  select count(distinct booking_id) into cleared from public.assignment_audit
   where action in ('clear', 'booking_deleted') and at > now() - interval '1 hour';
  if cleared >= 3 then
    msgs := msgs || ('최근 1시간 배정이 풀린 예식 ' || cleared || '건');
  end if;

  insert into private.health_snapshot
    (upcoming_total, upcoming_assigned, sub_assigned, assigned_all, sub_all, staff_active, checks_total)
  values (cur.upcoming_total, cur.upcoming_assigned, cur.sub_assigned,
          cur.assigned_all, cur.sub_all, cur.staff_active, cur.checks_total);

  if array_length(msgs, 1) > 0 then
    perform private.otb_push('🚨 배정 데이터 이상', array_to_string(msgs, ' · ') || ' — 관리자에서 확인하세요.', '/admin');
  end if;

  return jsonb_build_object('ok', array_length(msgs, 1) is null, 'warnings', to_jsonb(msgs),
                            'assigned_all', cur.assigned_all,
                            'upcoming_assigned', cur.upcoming_assigned, 'staff_active', cur.staff_active);
end$function$;
revoke all on function private.assignment_health_check() from public, anon, authenticated;
