/* 신랑신부 연락처 — 예식 2주 전부터 「예식 뒤 한 달까지」 (대표 2026-11-02 «지난것도 한달은 보여주게»)

   작가 캘린더에서 지난 날도 눌러 볼 수 있게 했다(작가 문의 → 대표 «작가 캘린더 이렇게 수정해줘»).
   그 전에도 서버는 지난 예식 번호를 계속 내주고 있었다 — 「2주 전부터」 만 있고 끝이 없었다.
   화면이 지난 칸을 막아 두어 안 보였을 뿐이다.

   두 곳이 같은 자를 쓴다 — staff_calendar(달력 상세) · survey_view(설문 보기).
   ⚠ shoot_items(「다음 촬영」)는 오늘 이후만 다루므로 그대로 둔다.
   ⚠ 이름은 그대로 낸다. 같이 가는 작가 번호(peer_of)는 이 빗장을 안 탄다.
   ⚠ 관리자는 다른 함수를 쓴다. 대표는 언제든 다 보신다.

   이 파일은 살아 있는 정의를 읽어와 정해진 자리만 갈아 끼운 것이다 (.backups/tests/pgrun/_phone_month_patch.mjs). */

CREATE OR REPLACE FUNCTION public.staff_calendar(p_staff_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  st public.staff; res jsonb; nd date;
  today date := (now() at time zone 'Asia/Seoul')::date;
  upto  date;   -- 어디까지 보여줄까 (아래 설명)
begin
  select * into st from public.staff where id = p_staff_id;
  if not found then return null; end if;
  if p_to < p_from or p_to > p_from + 400 then raise exception 'bad range'; end if;

  -- 가장 가까운 「날」
  select min(b.wedding_date) into nd from public.bookings b
   where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
     and b.status <> '취소'
     and b.wedding_date >= today;

  -- 예식은 «이틀 전부터» 보인다. 다만 이틀 안에 아무것도 없는 분도 있으니
  -- 가장 가까운 날 하나는 언제나 나오게 둔다 (그래서 greatest 다)
  upto := greatest(nd, today + 2);

  select jsonb_build_object(
    'staff_name', st.name,
    'staff_photo', st.photo_url,
    'from', p_from, 'to', p_to,
    -- 다음 촬영 — 첫째 날은 그대로, 그 뒤 이틀 안의 날은 more 에. 보고 있는 달과는 무관하다
    'next', case when nd is null then null else jsonb_build_object(
      'wedding_date', nd,
      'days', (nd - today),
      'items', private.shoot_items(p_staff_id, nd),
      -- 첫째 날 다음으로 오는 날들 (오늘+2 까지). 없으면 빈 목록
      'more', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'wedding_date', dd.wd,
                 'days', (dd.wd - today),
                 'items', private.shoot_items(p_staff_id, dd.wd)) order by dd.wd)
        from (select distinct b2.wedding_date as wd
              from public.bookings b2
              where (b2.assignee_id = p_staff_id or b2.sub_assignee_id = p_staff_id)
                and b2.status <> '취소'
                and b2.wedding_date > nd and b2.wedding_date <= upto) dd), '[]'::jsonb)) end,
    'bookings', coalesce((select jsonb_agg(x order by x->>'wedding_date', x->>'wedding_time') from (
        select jsonb_build_object(
          'booking_id', b.id, 'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time,
          'wedding_venue', b.wedding_venue,
          'role', case when b.assignee_id = p_staff_id then '메인' else '서브' end,
          'bride_name', b.bride_name, 'groom_name', b.groom_name,
          -- 연락처는 예식 2주 전부터 예식 뒤 한 달까지 (대표 2026-11-02 «지난것도 한달은 보여주게»). survey_view 와 같은 자
          'bride_phone', case when b.wedding_date <= current_date + 14 and b.wedding_date >= (current_date - interval '1 month')::date then b.bride_phone end,
          'groom_phone', case when b.wedding_date <= current_date + 14 and b.wedding_date >= (current_date - interval '1 month')::date then b.groom_phone end,
          /* 신부님이 나를 지정하신 촬영인가 (대표 2026-09-19).
             ⚠ pick_pin 은 언제나 메인이다 — 서브로 들어가신 분께는 안 붙는다.
             ⚠ 받으실 돈은 서버가 셈해서 보낸다. 화면에서 다시 셈하면 수수료를
               다시 떼기로 하실 때 두 군데를 고쳐야 하고 한쪽이 남는다 */
          'pick_mine', (b.pick_pin is not null and b.pick_pin = p_staff_id),
          'pick_pay_won', case when b.pick_pin = p_staff_id
                               then private.pick_staff_pay(b.pick_fee_won) end,
          'option_reception', b.option_reception, 'option_pyebaek', b.option_pyebaek,
          'option_part2', b.option_part2, 'photographer', b.photographer, 'rep_designation', b.rep_designation,
          -- 신부가 촬영 설문을 냈는지. 냈으면 캘린더에서 바로 열 수 있게 한다
          'has_survey', exists(select 1 from public.surveys s where s.booking_id = b.id),
          'photo_usage_agree', coalesce(b.photo_usage_agree, false)
        ) || private.peer_of(b, p_staff_id) as x
        from public.bookings b
        where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
          and b.status <> '취소' and b.wedding_date between p_from and p_to) t), '[]'::jsonb),
    'busy', coalesce((select jsonb_agg(jsonb_build_object(
          'id', sb.id, 'the_date', sb.the_date, 'kind', sb.kind,
          'at_time', sb.at_time, 'end_time', sb.end_time, 'place', sb.place, 'note', sb.note,
          'title', sb.title, 'all_day', sb.all_day, 'group_id', sb.group_id, 'span', sb.span,
          -- 묶음이면 전체가 언제부터 언제까지인지 (달력 범위 밖까지 포함해서 센다)
          'g_from', g.g_from, 'g_to', g.g_to, 'g_n', g.g_n,
          -- 쭉 이어지는 묶음이면 첫날 시작·마지막날 종료 (화면이 한 줄로 그린다)
          'g_at', g.g_at, 'g_end', g.g_end)
          order by sb.the_date, sb.all_day desc, sb.at_time)
        from public.staff_busy sb
        left join lateral (
          select min(o.the_date) g_from, max(o.the_date) g_to, count(*)::int g_n,
                 (array_agg(o.at_time order by o.the_date) filter (where o.at_time is not null))[1] g_at,
                 (array_agg(o.end_time order by o.the_date desc) filter (where o.end_time is not null))[1] g_end
          from public.staff_busy o
          where o.group_id = sb.group_id and o.staff_id = sb.staff_id
        ) g on sb.group_id is not null
        where sb.staff_id = p_staff_id and sb.the_date between p_from and p_to), '[]'::jsonb)
  ) into res;
  return res;
end$function$
;

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
    /* 연락처는 **예식 2주 전부터 예식 뒤 한 달까지** (대표 2026-09-18 «맞추자» · 2026-11-02 «지난것도 한달은 보여주게»).
       staff_calendar 와 같은 자를 쓴다 — 같은 자료를 두 화면이 다른 규칙으로 내주면
       한쪽을 막아도 다른 쪽이 열려 있다. 이름은 그대로 낸다 */
    'bride_name', b.bride_name,
    'bride_phone', case when b.wedding_date <= current_date + 14 and b.wedding_date >= (current_date - interval '1 month')::date then b.bride_phone end,
    'groom_name', b.groom_name,
    'groom_phone', case when b.wedding_date <= current_date + 14 and b.wedding_date >= (current_date - interval '1 month')::date then b.groom_phone end,
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

grant execute on function public.staff_calendar(uuid, date, date) to anon, authenticated;
grant execute on function public.survey_view(uuid, uuid) to anon, authenticated;
