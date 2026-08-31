-- 「작가 미확인」에 스케줄 확인을 더한다 (대표 2026-08-31)
--
--   «이거 배정을 작가가 확인했다는 사실을 나는 어디서 알 수 있나?»
--   «홈에 작가 미확인 박스에 스케줄확인넣어줘»
--
-- 배정 알림을 보내기 시작했는데(20260831c), 작가가 그걸 봤는지를 대표가 볼 데가 없었다.
-- 기록은 남고 있었다 — staff_notice.read_at. 화면에 안 붙였을 뿐이다.
--
-- ⚠ **「읽음」과 「확인 완료」는 다르다.**
--   · 스케줄 확인(여기) = 배정 알림을 **봤다**. 「확인했어요」를 누른 것뿐이다
--   · 월요일 체크      = 참석·도착·옵션 셋을 눌러 **하겠다**고 한 것
--   둘을 같은 것으로 보면 «알림만 읽고 월요일에 체크 안 한» 사람을 놓친다.
--   그래서 묶음을 따로 둔다.
--
-- ⚠ 「보낸 것」만 센다. 배정 알림이 안 나간 옛 예약까지 세면 다음 달이 전부 벌겋게 뜬다.
--   (배정 알림은 2026-08-31 부터 난다 — 그 전 배정은 알림 자체가 없다)

create or replace function public.admin_unconfirmed()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'booking_id', b.id, 'contractor_name', b.contractor_name,
    'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time, 'wedding_venue', b.wedding_venue,
    'assignee_id', b.assignee_id, 'sub_assignee_id', b.sub_assignee_id,
    -- ① 월요일 체크
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
    /* ③ 스케줄 확인 — 배정 알림을 읽었나 (대표 2026-08-31).
         ⚠ 알림이 **간 사람만** 센다. 안 간 건 «미확인» 이 아니라 «해당 없음» 이다 */
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
    /* ⚠ 앞으로 30일만 보던 것을 **앞날 전부**로 넓혔다 (2026-08-31).
         배정은 몇 달 앞서 하신다 — 10월 예식을 8월에 배정하시면 30일 창에 안 잡혀서
         「스케줄 확인」이 늘 비어 보인다. 실제로 10/10 건이 그래서 안 떴다.
       넓혀도 늘어나지 않는다: 아래 «하나라도 보낸 건만» 이 막아준다.
         월요일 체크·설문 톡은 예식 며칠 전에야 나가므로 먼 예식은 애초에 안 걸린다 */
    and b.wedding_date >= current_date
    -- 셋 중 **하나라도** 보낸 건만 (전엔 월요일 체크만 봤다)
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
