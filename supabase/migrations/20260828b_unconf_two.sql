-- 대표 홈의 「작가 미확인」을 둘로 나눈다 (대표 요청 2026-08-28
-- «홈에 작가 미확인을 두개로 나눠서 / 월요일체크 여부랑 / 설문 체크 여부 보여줘»)
--
--   ① 월요일 체크 — 배정받고 누르는 참석·도착·옵션 (check_done)
--   ② 설문 확인   — 예식 하루 전 설문 톡을 받고 그 화면에서 누르는 것 (survey_ack_at)
--
-- ⚠ 「보낸 사람만」 센다. 안 보낸 건까지 미확인으로 세면 다음 달 예식이 전부 벌겋게 뜬다.
--   월요일 체크는 check_sent_at / sub_check_sent_at,
--   설문은 alimtalk_sent 의 «T:<작가ID>» 열쇠 (private.staff_survey_send_daily 와 같은 열쇠).
-- 칸(인자)은 그대로라 몸통만 바꾼다.

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
    'has_survey', exists(select 1 from public.surveys sv where sv.booking_id = b.id)
  ) order by b.wedding_date, b.wedding_time), '[]'::jsonb) into res
  from public.bookings b
  where b.status <> '취소' and b.deposit_paid and b.assignee_id is not null
    and b.wedding_date >= current_date and b.wedding_date <= current_date + 30
    -- 둘 중 **하나라도** 보낸 건만 (전엔 월요일 체크만 봤다)
    and (b.check_sent_at is not null or b.sub_check_sent_at is not null
         or (coalesce(b.alimtalk_sent, '{}'::jsonb) -> ('T:' || b.assignee_id::text)) is not null
         or (b.sub_assignee_id is not null
             and (coalesce(b.alimtalk_sent, '{}'::jsonb) -> ('T:' || b.sub_assignee_id::text)) is not null));
  return res;
end$fn$;
revoke all on function public.admin_unconfirmed() from public, anon;
grant execute on function public.admin_unconfirmed() to authenticated;
