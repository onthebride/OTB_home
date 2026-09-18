/* 설문 화면의 연락처도 「예식 2주 전부터」로 맞춘다 (대표 2026-09-18 «맞추자»)

   staff_calendar 는 `wedding_date <= current_date + 14` 일 때만 연락처를 냈는데
   survey_view 는 예약 번호만 있으면 언제든 냈다. 같은 자료인데 규칙이 둘이었다.
   신부님이 설문 링크를 누군가에게 넘기면 그분도 두 연락처를 볼 수 있었다.

   ⚠ 신부님 설문 폼(survey.js)은 연락처를 안 쓴다. 쓰는 곳은 작가 화면(survey-view.js)뿐이고,
     작가 설문안내(T)는 예식 하루 전에 나가므로 2주면 넉넉하다.
   ⚠ 이름(bride_name·groom_name)은 그대로 낸다 — 작가가 누구 예식인지는 알아야 한다.
   ⚠ 관리자는 다른 함수(admin_survey_get)를 쓴다. 대표는 언제든 다 보신다.

   이 파일은 살아 있는 정의를 읽어와 한 군데만 갈아 끼운 것이다 (_svphone_patch.mjs). */
CREATE OR REPLACE FUNCTION public.survey_view(p_booking_id uuid, p_staff_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare b public.bookings; s public.surveys; refs jsonb; base jsonb; mine jsonb := '{}'::jsonb;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found then return null; end if;

  -- 배정된 작가가 열었으면 확인 단추를 붙일 수 있게 알려준다
  if p_staff_id is not null
     and exists(select 1 from public.bookings x where x.id = p_booking_id and x.status <> '취소'
                  and (x.assignee_id = p_staff_id or x.sub_assignee_id = p_staff_id)) then
    mine := jsonb_build_object(
      'can_ack', true,
      'staff_name', (select name from public.staff where id = p_staff_id),
      'ack_at', (select c.survey_ack_at from public.assignment_checks c
                  where c.booking_id = p_booking_id and c.staff_id = p_staff_id));
  end if;

  base := jsonb_build_object(
    'contractor_name', b.contractor_name,
    /* 연락처는 **예식 2주 전부터만** (대표 2026-09-18 «맞추자»).
       staff_calendar 와 같은 자를 쓴다 — 같은 자료를 두 화면이 다른 규칙으로 내주면
       한쪽을 막아도 다른 쪽이 열려 있다. 이름은 그대로 낸다 */
    'bride_name', b.bride_name,
    'bride_phone', case when b.wedding_date <= current_date + 14 then b.bride_phone end,
    'groom_name', b.groom_name,
    'groom_phone', case when b.wedding_date <= current_date + 14 then b.groom_phone end,
    'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time, 'wedding_venue', b.wedding_venue,
    'option_reception', b.option_reception, 'option_pyebaek', b.option_pyebaek,
    'option_part2', b.option_part2, 'option_album', b.option_album,
    'travel_fee', b.travel_fee, 'photographer', b.photographer, 'rep_designation', b.rep_designation);

  select * into s from public.surveys where booking_id = p_booking_id;
  if not found then
    return base || jsonb_build_object('has_survey', false) || mine;
  end if;
  select coalesce(jsonb_agg(data_url order by sort), '[]'::jsonb) into refs
    from public.survey_refs where booking_id = p_booking_id;
  return base || mine || jsonb_build_object(
    'has_survey', true,
    'agree_check', s.agree_check,
    'priority', s.priority, 'prop_ring', s.prop_ring, 'bride_room_req', s.bride_room_req,
    'prog_items', s.prog_items, 'bridal_focus', s.bridal_focus,
    'wonpan_first', s.wonpan_first, 'wonpan_light', s.wonpan_light,
    'extra_req', s.extra_req, 'etc_req', s.etc_req,
    'updated_at', s.updated_at, 'refs', refs);
end$function$
;

grant execute on function public.survey_view(uuid, uuid) to anon, authenticated;
