-- 작가 캘린더 카드에도 「포스팅 가능 여부」 (대표 요청 2026-08-28
-- «그리고 작가 캘린더카드에서 보이게 해줘»).
--
-- 예약의 촬영본 사용동의(bookings.photo_usage_agree) 를 그대로 내려준다.
-- ⚠ 「다음 촬영」과 「날짜 칸」 **두 군데 다** 실어야 한다 — 화면은 shootRow() 하나로 그린다.
--   한쪽만 실으면 같은 줄이 화면에 따라 달라 보인다.
create or replace function public.staff_calendar(p_staff_id uuid, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path=public, pg_temp as $$
declare st public.staff; res jsonb; nd date;
begin
  select * into st from public.staff where id = p_staff_id;
  if not found then return null; end if;
  if p_to < p_from or p_to > p_from + 400 then raise exception 'bad range'; end if;

  -- 가장 가까운 「날」
  select min(b.wedding_date) into nd from public.bookings b
   where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
     and b.status <> '취소'
     and b.wedding_date >= (now() at time zone 'Asia/Seoul')::date;

  select jsonb_build_object(
    'staff_name', st.name,
    'staff_photo', st.photo_url,
    'from', p_from, 'to', p_to,
    -- 다음 촬영 — 그날 것을 전부. 보고 있는 달과는 무관하다
    'next', case when nd is null then null else jsonb_build_object(
      'wedding_date', nd,
      'days', (nd - (now() at time zone 'Asia/Seoul')::date),
      'items', (select jsonb_agg(jsonb_build_object(
          'booking_id', b.id, 'wedding_time', b.wedding_time, 'wedding_venue', b.wedding_venue,
          'role', case when b.assignee_id = p_staff_id then '메인' else '서브' end,
          'bride_name', b.bride_name, 'groom_name', b.groom_name,
          -- ⚠ 연락처는 예식 2주 전부터만. 날짜 칸과 같은 규칙이라야 한다
          'bride_phone', case when b.wedding_date <= current_date + 14 then b.bride_phone end,
          'groom_phone', case when b.wedding_date <= current_date + 14 then b.groom_phone end,
          -- 설문을 냈으면 카드에서 바로 열 수 있게 (대표 «오른쪽에 설문보는 버튼도 넣어줘»)
          'has_survey', exists(select 1 from public.surveys sv where sv.booking_id = b.id),
          -- 블로그·SNS 에 올려도 되는지 (대표 요청 2026-08-28)
          'photo_usage_agree', coalesce(b.photo_usage_agree, false))
          order by b.wedding_time)
        from public.bookings b
        where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
          and b.status <> '취소' and b.wedding_date = nd)) end,
    'bookings', coalesce((select jsonb_agg(x order by x->>'wedding_date', x->>'wedding_time') from (
        select jsonb_build_object(
          'booking_id', b.id, 'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time,
          'wedding_venue', b.wedding_venue,
          'role', case when b.assignee_id = p_staff_id then '메인' else '서브' end,
          'bride_name', b.bride_name, 'groom_name', b.groom_name,
          'bride_phone', case when b.wedding_date <= current_date + 14 then b.bride_phone end,
          'groom_phone', case when b.wedding_date <= current_date + 14 then b.groom_phone end,
          'option_reception', b.option_reception, 'option_pyebaek', b.option_pyebaek,
          'option_part2', b.option_part2, 'photographer', b.photographer, 'rep_designation', b.rep_designation,
          -- 신부가 촬영 설문을 냈는지. 냈으면 캘린더에서 바로 열 수 있게 한다
          'has_survey', exists(select 1 from public.surveys s where s.booking_id = b.id),
          'photo_usage_agree', coalesce(b.photo_usage_agree, false)
        ) as x
        from public.bookings b
        where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
          and b.status <> '취소' and b.wedding_date between p_from and p_to) t), '[]'::jsonb),
    'busy', coalesce((select jsonb_agg(jsonb_build_object(
          'id', sb.id, 'the_date', sb.the_date, 'kind', sb.kind,
          'at_time', sb.at_time, 'place', sb.place, 'note', sb.note,
          'title', sb.title, 'all_day', sb.all_day, 'group_id', sb.group_id,
          -- 묶음이면 전체가 언제부터 언제까지인지 (달력 범위 밖까지 포함해서 센다)
          'g_from', g.g_from, 'g_to', g.g_to, 'g_n', g.g_n)
          order by sb.the_date, sb.all_day desc, sb.at_time)
        from public.staff_busy sb
        left join lateral (
          select min(o.the_date) g_from, max(o.the_date) g_to, count(*)::int g_n
          from public.staff_busy o
          where o.group_id = sb.group_id and o.staff_id = sb.staff_id
        ) g on sb.group_id is not null
        where sb.staff_id = p_staff_id and sb.the_date between p_from and p_to), '[]'::jsonb)
  ) into res;
  return res;
end$$;
