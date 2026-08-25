-- 예식 전날 톡(T)의 「설문 확인하기」 버튼에 «확인했습니다» 단추가 안 떴다. 대표 신고 2026-08-25.
--
-- 무슨 일이었나 — public.survey_view(p_booking_id, p_staff_id) 는 p_staff_id 가 있을 때만
-- can_ack 를 켠다. 누가 열었는지 알아야 그 작가 몫으로 확인을 적을 수 있기 때문이다.
-- 그런데 승인된 카카오 템플릿의 버튼 링크가 «/survey-view?b=#{예약ID}» 라 s 가 없다.
-- 그래서 설문은 보이는데 확인 단추가 안 뜬다 —
-- 대표가 말한 «예식 전날에는 스케줄 재확인과 함께 설문 확인 체크» 가 반쪽이 된다.
--
-- 고치는 법 — 템플릿을 다시 올려 승인받지 않고, #{예약ID} 변수에 뒤 꼬리까지 실어 보낸다.
--   변수값 «<예약ID>&s=<작가ID>» → 최종 링크 «/survey-view?b=<예약ID>&s=<작가ID>»
-- 솔라피가 변수를 그대로 끼워 넣는 것(& 를 안 바꾸는 것)을 실제 발송으로 확인했다.
-- 링크는 여전히 승인받은 주소·경로 그대로다.
-- #{예약ID} 는 본문에는 안 쓰이고 버튼 링크에만 쓰이므로 글에는 아무 영향이 없다.
-- (언젠가 템플릿을 다시 올릴 일이 있으면 «?b=#{예약ID}&s=#{작가ID}» 로 바꿔 두는 게 깔끔하다)


-- ===== 자동: 예식 전날 =====
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
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'dry', p_dry, 'for_date', d1, 'n', n, 'rows', out_rows);
end$$;

revoke all on function private.staff_survey_send_daily(boolean) from public, anon, authenticated;


-- ===== 손 버튼: 관리자 「설문 안내 발송」 =====
-- 자동과 같은 링크가 나가야 한다. 한쪽만 고치면 손으로 보낸 작가만 확인 단추가 없다
create or replace function public.admin_send_staff_survey(p_booking_id uuid, p_staff_id uuid)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'extensions', 'pg_temp'
as $$
declare b public.bookings; st public.staff; vars jsonb; req bigint; line text; has_sv boolean;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select * into b from public.bookings where id = p_booking_id;
  if not found then raise exception 'booking not found'; end if;
  select * into st from public.staff where id = p_staff_id;
  if not found then raise exception 'staff not found'; end if;
  if st.phone is null or st.phone = '' then raise exception '작가 연락처가 없습니다'; end if;
  if b.assignee_id is distinct from p_staff_id and b.sub_assignee_id is distinct from p_staff_id then
    raise exception '이 예식에 배정된 작가가 아닙니다';
  end if;

  select exists(select 1 from public.surveys sv where sv.booking_id = b.id) into has_sv;
  line := private.wedding_line(b) || case when has_sv then '' else ' (설문 미작성)' end;

  vars := jsonb_build_object('#{작가명}', coalesce(st.name,''), '#{예식정보}', line,
                             -- 자동 발송과 같은 이유로 «&s=» 를 같이 싣는다
                             '#{예약ID}', b.id::text || '&s=' || p_staff_id::text);
  req := private.alimtalk_dispatch(b.id, 'T', st.phone, vars);
  update public.bookings
     set alimtalk_sent = coalesce(alimtalk_sent,'{}'::jsonb) || jsonb_build_object('T:' || p_staff_id::text, to_jsonb(now()))
   where id = b.id;
  return jsonb_build_object('ok', true, 'req', req, 'staff', st.name, 'line', line);
end$$;
