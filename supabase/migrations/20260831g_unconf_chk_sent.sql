-- 월요일 체크를 보낸 적 없는 예식이 「월요일 체크」 미확인에 뜬다 (대표 2026-08-31)
--
--   «저거 한효림이 왜 월요일체크에 들어가 있나?»
--
-- 내가 만든 구멍이다. 오늘 「스케줄 확인」을 더하면서(20260831e) 배정 알림도
-- «보낸 것» 으로 쳤다. 그러자 배정만 되고 월요일 체크는 안 나간 예식이 목록에 들어왔고,
-- 화면의 월요일 체크 묶음은 «보냈나» 를 안 보고 «했나(main_ok)» 만 보고 있어서 그대로 떴다.
--
--   한효림 · 10월 10일 — 오늘 배정만 했다. 월요일 체크는 나간 적이 없다.
--   그런데 「월요일 체크 미확인」으로 보였다. 작가님이 안 한 게 아니라 받은 적이 없다.
--
-- ⚠ 세 묶음 다 **「보낸 것만 센다」** 라야 한다. 설문 쪽은 처음부터 그랬고(main_sv_sent),
--   배정 쪽도 그렇게 만들었다(main_as_sent). 월요일 체크만 그 칸이 없었다 —
--   바깥 where 가 대신 막아주고 있었는데, 오늘 그 울타리가 넓어지면서 뚫렸다.
--   울타리에 기대지 말고 묶음마다 제 칸을 갖게 한다.

create or replace function public.admin_unconfirmed()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'booking_id', b.id, 'contractor_name', b.contractor_name,
    'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time, 'wedding_venue', b.wedding_venue,
    'assignee_id', b.assignee_id, 'sub_assignee_id', b.sub_assignee_id,
    -- ① 월요일 체크 — ⚠ 보낸 것만 센다 (2026-08-31 에 이 두 칸을 더했다)
    'main_chk_sent', b.check_sent_at is not null,
    'sub_chk_sent', b.sub_assignee_id is not null and b.sub_check_sent_at is not null,
    'main_ok', public.check_done(b.id, b.assignee_id),
    'sub_ok', (b.sub_assignee_id is null) or public.check_done(b.id, b.sub_assignee_id),
    -- ② 설문 확인 — 설문 톡을 보낸 사람만 «미확인» 으로 셀 수 있다
    'main_sv_sent', (coalesce(b.alimtalk_sent, '{}'::jsonb) -> ('T:' || b.assignee_id::text)) is not null,
    'sub_sv_sent', b.sub_assignee_id is not null
      and (coalesce(b.alimtalk_sent, '{}'::jsonb) -> ('T:' || b.sub_assignee_id::text)) is not null,
    'main_sv_ok', exists(select 1 from public.assignment_checks c
                          where c.booking_id = b.id and c.staff_id = b.assignee_id
                            and c.survey_ack_at is not null),
    'sub_sv_ok', (b.sub_assignee_id is null) or exists(select 1 from public.assignment_checks c
                          where c.booking_id = b.id and c.staff_id = b.sub_assignee_id
                            and c.survey_ack_at is not null),
    -- ③ 스케줄 확인 — 배정 알림을 읽었나. 알림이 간 사람만 센다
    'main_as_sent', exists(select 1 from public.staff_notice n
                            where n.booking_id = b.id and n.staff_id = b.assignee_id and n.kind = 'assign'),
    'main_as_ok', exists(select 1 from public.staff_notice n
                            where n.booking_id = b.id and n.staff_id = b.assignee_id and n.kind = 'assign'
                              and n.read_at is not null),
    'sub_as_sent', b.sub_assignee_id is not null and exists(select 1 from public.staff_notice n
                            where n.booking_id = b.id and n.staff_id = b.sub_assignee_id and n.kind = 'assign'),
    'sub_as_ok', exists(select 1 from public.staff_notice n
                            where n.booking_id = b.id and n.staff_id = b.sub_assignee_id and n.kind = 'assign'
                              and n.read_at is not null),
    'has_survey', exists(select 1 from public.surveys sv where sv.booking_id = b.id)
  ) order by b.wedding_date, b.wedding_time), '[]'::jsonb) into res
  from public.bookings b
  where b.status <> '취소' and b.deposit_paid and b.assignee_id is not null
    /* 앞날 전부를 본다 — 배정은 몇 달 앞서 하신다.
       넓혀도 늘어나지 않는다: 아래 «하나라도 보낸 건만» 이 막아준다 */
    and b.wedding_date >= current_date
    -- 셋 중 **하나라도** 보낸 건만
    and (b.check_sent_at is not null or b.sub_check_sent_at is not null
         or (coalesce(b.alimtalk_sent, '{}'::jsonb) -> ('T:' || b.assignee_id::text)) is not null
         or (b.sub_assignee_id is not null
             and (coalesce(b.alimtalk_sent, '{}'::jsonb) -> ('T:' || b.sub_assignee_id::text)) is not null)
         or exists(select 1 from public.staff_notice n
                    where n.booking_id = b.id and n.kind = 'assign'));
  return res;
end$fn$;
revoke all on function public.admin_unconfirmed() from public, anon;
grant execute on function public.admin_unconfirmed() to authenticated;
