-- 작가에게 나가는 알림톡 두 가지를 자동으로 보낸다. 대표 요청 2026-08-25 (템플릿 승인 완료).
--
-- 지금까지는 자동 발송이 아예 없었다. private.alimtalk_send_scheduled 은 B·C·D·G 만 보내는데
-- 그건 전부 «신부에게» 가는 것이다(contractor_phone). 작가에게 가는 S·T 는 관리자 화면의
-- 손 버튼이 유일한 길이었다. 템플릿이 승인됐으니 이제 자동으로 내보낸다.
--
--   S = 월요일 스케줄 체크   — 작가 단위. 이번 주에 예식이 있는 작가에게 한 통.
--                              «이번 주 촬영 일정 확인 부탁드립니다» + [일정 확인하기]
--                              변수: #{작가명} #{작가ID} → /staff-schedule?s=
--   T = 예식 전날 최종 체크  — 예약 단위. 내일 예식의 담당 작가에게.
--                              «내일 촬영 일정 안내» + [설문 확인하기]
--                              변수: #{작가명} #{예식정보} #{예약ID} → /survey-view?b=
--
-- 두 함수 다 p_dry 를 주면 «누구에게 무엇이 갈지» 만 돌려주고 실제로는 안 보낸다.
-- 사람에게 나가는 것이라 켜기 전에 눈으로 보고 확인한다.


-- ===== S : 월요일 스케줄 체크 =====
create or replace function private.staff_check_send_weekly(p_dry boolean default false)
returns jsonb language plpgsql security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $$
declare
  d0 date := date_trunc('week', (now() at time zone 'Asia/Seoul')::date)::date;  -- 이번 주 월요일
  r record; n int := 0; vars jsonb; out_rows jsonb := '[]'::jsonb;
begin
  for r in
    -- 메인·서브 가릴 것 없이 «이번 주에 나갈 사람» 이면 받는다.
    -- 한 작가가 이번 주에 세 건이어도 한 통만 간다 (버튼을 누르면 다 보인다)
    select st.id, st.name, st.phone, count(*) as n_wed, min(b.wedding_date) as first_wed
    from public.bookings b
    join public.staff st on st.id in (b.assignee_id, b.sub_assignee_id)
    where b.status <> '취소'
      and b.wedding_date >= d0 and b.wedding_date < d0 + 7
      and coalesce(st.active, false)
      and coalesce(st.phone, '') <> ''
      -- 대표도 받는다 (대표 요청 2026-08-25 «나한테도 톡 주고»).
      -- 본인도 찍으러 나가니 이번 주 일정을 같은 방식으로 받는 게 맞다
      -- 이번 주에 이미 보냈으면 다시 안 보낸다 (크론이 두 번 돌아도 안전하게)
      and not exists (
        select 1 from private.alimtalk_outbox o
        where o.template = 'S' and o.phone = st.phone
          and o.created_at >= (d0::timestamp at time zone 'Asia/Seoul'))
    group by st.id, st.name, st.phone
    order by st.name
  loop
    out_rows := out_rows || jsonb_build_object(
      'staff', r.name, 'phone', right(r.phone, 4), 'weddings', r.n_wed, 'first', r.first_wed);
    if not p_dry then
      vars := jsonb_build_object('#{작가명}', coalesce(r.name, ''), '#{작가ID}', r.id::text);
      perform private.alimtalk_dispatch(null, 'S', r.phone, vars);
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'dry', p_dry, 'week_of', d0, 'n', n, 'rows', out_rows);
end$$;


-- ===== T : 예식 전날 최종 체크 =====
create or replace function private.staff_survey_send_daily(p_dry boolean default false)
returns jsonb language plpgsql security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $$
declare
  d1 date := (now() at time zone 'Asia/Seoul')::date + 1;   -- 내일 예식
  r record; n int := 0; vars jsonb; line text; out_rows jsonb := '[]'::jsonb;
begin
  for r in
    -- 메인과 서브에게 각각 간다. 두 분이 가는 예식이면 둘 다 신부 설문을 봐야 한다.
    -- 보냈다는 표시는 «T:<작가ID>» 로 남긴다 — 손 버튼(admin_send_staff_survey)과 같은 열쇠라
    -- 손으로 먼저 보냈으면 자동으로 또 가지 않는다.
    -- 예약은 b.* 로 풀지 말고 «b» 통째로 들고 다닌다 — private.wedding_line 이 bookings 형을
    -- 받는데, 다른 칸과 섞어 편 record 는 그 형으로 못 바꾼다 (coerce_record_to_complex)
    select b as bk, st.id as staff_id, st.name as staff_name, st.phone as staff_phone
    from public.bookings b
    join public.staff st on st.id in (b.assignee_id, b.sub_assignee_id)
    where b.status <> '취소'
      and b.wedding_date = d1
      and coalesce(st.phone, '') <> ''
      and (coalesce(b.alimtalk_sent, '{}'::jsonb) -> ('T:' || st.id::text)) is null
    order by st.name
  loop
    -- 설문이 아직이면 그렇다고 적어 보낸다 (손 버튼과 같은 문장)
    line := private.wedding_line(r.bk)
      || case when exists (select 1 from public.surveys sv where sv.booking_id = (r.bk).id)
              then '' else ' (설문 미작성)' end;
    out_rows := out_rows || jsonb_build_object(
      'staff', r.staff_name, 'phone', right(r.staff_phone, 4), 'line', line);
    if not p_dry then
      vars := jsonb_build_object('#{작가명}', coalesce(r.staff_name, ''),
                                 '#{예식정보}', line, '#{예약ID}', (r.bk).id::text);
      perform private.alimtalk_dispatch((r.bk).id, 'T', r.staff_phone, vars);
      update public.bookings
         set alimtalk_sent = coalesce(alimtalk_sent, '{}'::jsonb)
             || jsonb_build_object('T:' || r.staff_id::text, to_jsonb(now()))
       where id = (r.bk).id;
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'dry', p_dry, 'for_date', d1, 'n', n, 'rows', out_rows);
end$$;

revoke all on function private.staff_check_send_weekly(boolean) from public, anon, authenticated;
revoke all on function private.staff_survey_send_daily(boolean) from public, anon, authenticated;

-- ===== 크론 (실제 적용은 2026-08-25, 대표 승인 후) =====
-- pg_cron 은 DB 시간대가 아니라 cron.timezone 을 본다. 지금 GMT 이므로
-- 한국 오전 10시는 «1시» 로 적는다. 신부 톡(0 1)과 같은 분에 겹치지 않게 2분 뒤로 둔다.
--   select cron.schedule('otb-staff-monday', '0 1 * * 1', 'select private.staff_check_send_weekly();');
--   select cron.schedule('otb-staff-eve',    '2 1 * * *', 'select private.staff_survey_send_daily();');
