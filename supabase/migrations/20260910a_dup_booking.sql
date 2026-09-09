-- 같은 사람이 같은 예식일로 두 번 신청하는 것을 막는다 (대표 2026-09-10
--   «사용자가 모르고 두번을 눌렀거나 새벽에 예약신청하고 내가 응답이 없어서
--     다시 예약신청하는 경우 있는데 이거 막을 수 없나?»)
--
-- 9/9 이건우 님이 21:28 · 21:38 두 번 들어왔다. 앞단은 보내는 동안 단추를 잠그고
-- 성공하면 「카카오톡 채팅 열기」로 바꾸지만, 페이지를 다시 열면 폼이 처음으로 돌아가
-- 10분 뒤 다시 넣는 것은 못 막는다. 그래서 서버에서 막는다 — 기기·브라우저가 달라도 걸린다.
-- (예약 265건 중 이런 중복은 이 한 건뿐이다. 자주 나는 일은 아니지만, 나면 대표가 손으로 푼다)
--
-- ⚠ 옛 submit_booking 은 그대로 둔다. 손님 브라우저에 이미 받아둔 옛 main.js 가 그걸 부른다.
--   지우면 그 사람들 신청이 조용히 안 된다.
-- ⚠ 반환이 uuid → jsonb 라 이름을 새로 판다(_v2). 같은 이름은 반환형만 바꿔서는 못 고친다.
-- ⚠ 번호는 저장할 때 트리거(a_fmt_phone)가 private.fmt_phone 으로 다듬는다.
--   들어온 payload 는 아직 안 다듬어졌으니 여기서 같은 함수를 통과시켜 견준다
--   («01088712996» 로 넣어도 «010-8871-2996» 과 같은 것으로 본다).
-- ⚠ 취소·미입금은 세지 않는다. 취소하고 다시 넣는 것, 계약 의사가 없다고 접어둔 건이
--   나중에 다시 오는 것은 막을 일이 아니라 진짜 새 신청이다.
-- ⚠ 빠져나갈 길을 둔다 (대표 «빠져나갈길 두자») — payload 에 force:true 가 오면 검사하지 않는다.
--   화면의 「그래도 새로 신청하기」가 이걸 보낸다. 대표가 시험 삼아 넣어보실 때도 이 길로 지난다.

create or replace function public.submit_booking_v2(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $fn$
declare new_id uuid; li jsonb; tot int; ph text; wd date; dup_at timestamptz;
begin
  -- ① 이미 들어온 것이 있나
  ph := private.fmt_phone(nullif(payload->>'contractor_phone',''));
  wd := nullif(payload->>'wedding_date','')::date;
  if not coalesce((payload->>'force')::boolean, false) and ph is not null and wd is not null then
    select b.created_at into dup_at from public.bookings b
     where b.contractor_phone = ph and b.wedding_date = wd
       and b.status in ('신규','확정')
     order by b.created_at limit 1;
    if dup_at is not null then
      return jsonb_build_object(
        'ok', false, 'reason', 'dup',
        'at', to_char(dup_at at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI'),
        'at_txt', to_char(dup_at at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI'));
    end if;
  end if;

  -- ② 없으면 그대로 접수한다 (submit_booking 과 같은 몸통)
  li := coalesce(payload->'line_items', '[]'::jsonb);
  tot := coalesce(
    (select sum((it->>'price')::int) from jsonb_array_elements(li) it),
    nullif(payload->>'total_price','')::int);
  insert into public.bookings (
    agree_available, agree_terms,
    contractor_name, contractor_phone, contractor_email,
    wedding_date, wedding_time, wedding_venue,
    groom_name, groom_phone, bride_name, bride_phone,
    package, travel_fee,
    option_album, option_reception, option_pyebaek, option_part2,
    photographer, rep_designation, photo_usage_agree, total_price, line_items, custom_options
  ) values (
    coalesce((payload->>'agree_available')::boolean, false),
    coalesce((payload->>'agree_terms')::boolean, false),
    nullif(payload->>'contractor_name',''), nullif(payload->>'contractor_phone',''), nullif(payload->>'contractor_email',''),
    nullif(payload->>'wedding_date','')::date, nullif(payload->>'wedding_time',''), nullif(payload->>'wedding_venue',''),
    nullif(payload->>'groom_name',''), nullif(payload->>'groom_phone',''), nullif(payload->>'bride_name',''), nullif(payload->>'bride_phone',''),
    case when coalesce((payload->>'basic')::boolean, true) then '베이직(데이터형)' else null end,
    coalesce((payload->>'travel_fee')::boolean, false),
    coalesce((payload->>'option_album')::boolean, false),
    coalesce((payload->>'option_reception')::boolean, false),
    coalesce((payload->>'option_pyebaek')::boolean, false),
    coalesce((payload->>'option_part2')::boolean, false),
    coalesce(nullif(payload->>'photographer',''), '기본'),
    coalesce((payload->>'rep_designation')::boolean, false),
    coalesce((payload->>'photo_usage_agree')::boolean, false),
    tot,
    case when jsonb_array_length(li) > 0 then li else null end,
    coalesce(payload->'custom_options', '[]'::jsonb)
  ) returning id into new_id;

  perform private.otb_push('🔔 신규 예약',
    coalesce(nullif(payload->>'contractor_name',''),'')
    || coalesce(' · ' || nullif(payload->>'wedding_date',''), '')
    || coalesce(' · ' || nullif(payload->>'wedding_venue',''), '')
    || case when coalesce((payload->>'force')::boolean, false) then E'\n(같은 번호·같은 예식일로 이미 있는데 그래도 넣으신 것)' else '' end,
    '/admin');
  return jsonb_build_object('ok', true, 'id', new_id);
end;
$fn$;
revoke all on function public.submit_booking_v2(jsonb) from public;
grant execute on function public.submit_booking_v2(jsonb) to anon, authenticated;
