/* 예식 전날 안내에도 폰 알림 (대표 2026-09-28 «예식전에도 알림톡과 캘린더 알림 가게해줘»)

   ── 그동안 어땠나
   private.staff_survey_send_daily() 는 알림톡(T·작가 설문안내)만 보냈다.
   월요일 체크(S)는 오늘 폰 알림을 붙였는데, 정작 **예식 하루 전 안내**가 카톡으로만 갔다.

   ── 무엇을 더하나
   알림톡을 보낸 바로 뒤에 폰 알림도 울린다. 누르면 작가 캘린더로 간다
   (월요일 체크와 같은 자리다 — 확인 칸에 그 예식의 「설문 보기 · 확인했어요」 가 있다).

   ⚠⚠ 잠금화면에 **신부님 성함을 싣지 않는다.**
     알림톡 본문(private.wedding_line)에는 「10월 3일(토) 오후 2:00 · 아펠가모 · 신부 홍길동」
     처럼 성함이 들어간다. 카톡은 본인만 여는 자리라 괜찮지만, 폰 알림은 **잠금화면에 그대로
     뜬다.** 옆 사람이 본다. 그래서 푸시에는 시각·예식장까지만 싣는다 —
     미리 알림(staff_remind_send)에서 정한 것과 같은 규칙이다.

   ⚠ 알림함(staff_notice) 줄은 안 만든다. 확인 칸에 이미 그 예식의 설문 줄이 있다
     (staff_todo 의 survey 갈래). 줄을 더하면 누를 것이 둘이 된다. 월요일 체크와 같은 까닭이다.

   ⚠ 설문이 아직이면 그렇게 적는다. 「보세요」 라고만 하면 열었을 때 빈 화면이라 헛걸음이다.

   ── 안 바뀌는 것
   알림톡은 그대로다. 누가 받는지, 한 번만 가는지(alimtalk_sent 의 T:<작가ID>)도 그대로다.

   ── 대표께 알려드릴 것
   「하루 전」 미리 알림을 켜두신 분은 그날 아침에 두 통을 받으신다.
     07:00 📅 내일 일정이 있어요        (미리 알림 · 폰만)
     10:02 📋 내일 예식 · 확인 부탁드려요 (설문 안내 · 알림톡 + 폰)
   하는 일이 다르다(앞은 알려주기, 뒤는 설문 확인 부탁). 겹치는 게 싫으시면 한 줄로 끈다. */


CREATE OR REPLACE FUNCTION private.staff_survey_send_daily(p_dry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'private', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  d0 date := (now() at time zone 'Asia/Seoul')::date;        -- 오늘(보내는 날)
  d1 date := (now() at time zone 'Asia/Seoul')::date + 1;    -- 내일 예식
  r record; n int := 0; vars jsonb; line text; has_sv boolean; out_rows jsonb := '[]'::jsonb;
begin
  -- 대표가 오늘은 안 보내기로 했으면 여기서 끝낸다 (다음 날은 다시 나간다)
  if not p_dry and exists (select 1 from private.send_hold h where h.kind = 'T' and h.on_date = d0) then
    return jsonb_build_object('ok', true, 'held', true, 'for_date', d1, 'n', 0);
  end if;

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
    has_sv := exists (select 1 from public.surveys sv where sv.booking_id = (r.bk).id);
    line := private.wedding_line(r.bk) || case when has_sv then '' else ' (설문 미작성)' end;
    out_rows := out_rows || jsonb_build_object(
      'staff', r.staff_name, 'phone', right(r.staff_phone, 4), 'line', line,
      'link', '/survey-view?b=' || (r.bk).id::text || '&s=' || r.staff_id::text);
    if not p_dry then
      vars := jsonb_build_object(
        '#{작가명}', coalesce(r.staff_name, ''),
        '#{예식정보}', line,
        -- 여기에 «&s=<작가ID>» 를 같이 실어야 열었을 때 확인 단추가 뜬다 (위 설명 참고)
        '#{예약ID}', (r.bk).id::text || '&s=' || r.staff_id::text);
      perform private.alimtalk_dispatch((r.bk).id, 'T', r.staff_phone, vars);
      update public.bookings
         set alimtalk_sent = coalesce(alimtalk_sent, '{}'::jsonb)
             || jsonb_build_object('T:' || r.staff_id::text, to_jsonb(now()))
       where id = (r.bk).id;
      /* 폰 알림도 같이 (대표 2026-09-28 «예식전에도 알림톡과 캘린더 알림 가게해줘»).
         ⚠⚠ 잠금화면에 **신부님 성함을 싣지 않는다.** line 에는 들어 있지만
           폰 알림은 옆 사람도 본다 — 시각·예식장까지만 (미리 알림과 같은 규칙).
         ⚠ 알림함 줄은 안 만든다 — 확인 칸에 그 예식의 설문 줄이 이미 있다 */
      perform private.otb_push(
        '📋 내일 예식 · 확인 부탁드려요',
        coalesce(public.fmt_ktime((r.bk).wedding_time), '시간 미정')
          || coalesce(' · ' || nullif((r.bk).wedding_venue, ''), '')
          || case when has_sv then ' · 캘린더 「확인」 칸에서 신부님 설문을 보실 수 있어요'
                  else ' · 신부님 설문은 아직이에요' end,
        '/staff-calendar?s=' || r.staff_id::text, r.staff_id);
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'dry', p_dry, 'held', false, 'for_date', d1, 'n', n, 'rows', out_rows);
end$function$
;
