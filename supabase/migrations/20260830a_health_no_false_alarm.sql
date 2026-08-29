-- 배정 감시가 날마다 헛경보를 울리던 것을 고친다 (대표 2026-08-30 «이건뭐지?»)
--
-- 무슨 일이 있었나. 2026-08-30 0시 7분(한국)에 이런 푸시가 갔다.
--   🚨 배정 데이터 이상 — 작가 배정 5건 줄어듦 (106→101) · 서브 배정 1건 줄어듦
--
-- 없어진 것은 하나도 없었다. 감시가 세던 것이 「**앞으로** 예식 중 배정된 건」
-- (wedding_date >= current_date) 이라서, 자정을 넘기면 어제 예식이 그 창에서 빠진다.
--   · 8월 29일 예식 5건(그중 서브 1건)이 어제 있었다 → 정확히 그만큼 줄었다
--   · assignment_audit(배정 해제·삭제 기록)에는 한 줄도 없다
--   · 예약 총수는 251건 그대로
--
-- 즉 **예식이 있는 날마다** 그다음 0시에 헛경보가 울린다. 주말마다 울린 셈이다.
-- 헛경보는 진짜 경보를 못 믿게 만든다. 이게 제일 나쁘다.
--
-- 고치는 법 — 시간이 지나도 안 줄어드는 것으로 센다.
--   assigned_all = 취소든 아니든, 지난 예식이든 아니든 **작가가 박혀 있는 예약 수**
-- 이 수는 이런 때만 줄어든다.
--   · 배정을 실제로 풀었다   · 예약을 지웠다
-- 둘 다 진짜 봐야 할 일이다. 예식이 지나거나 예약이 취소되는 것으로는 안 줄어든다.
-- (취소해도 assignee_id 는 그대로 남는다 — 그래서 취소를 사고로 오해하지 않는다)
--
-- 「앞으로」 수는 그대로 남겨 기록한다. 다만 그걸로는 경보를 울리지 않는다.

alter table private.health_snapshot add column if not exists assigned_all int;
alter table private.health_snapshot add column if not exists sub_all int;
comment on column private.health_snapshot.assigned_all is
  '작가가 박혀 있는 예약 수 (취소·지난 것 포함). 시간이 지나도 안 줄어든다 — 경보는 이걸로 본다';

create or replace function private.assignment_health_check()
returns jsonb language plpgsql security definer
set search_path = public, private, extensions, pg_temp as $fn$
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

  -- 짧은 시간에 배정이 여러 건 풀린 경우(사고 신호). 한 건씩 재배정하는 정상 작업과 구분.
  select count(*) into cleared from public.assignment_audit
   where action in ('clear', 'booking_deleted') and at > now() - interval '1 hour';
  if cleared >= 3 then
    msgs := msgs || ('최근 1시간 배정 해제·삭제 ' || cleared || '건');
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
end$fn$;
revoke all on function private.assignment_health_check() from public, anon, authenticated;

-- 지금 값을 한 줄 넣어 둔다. 다음 시간에 이것과 견주므로, 안 넣으면 첫 비교가 한 시간 늦는다
select private.assignment_health_check();
