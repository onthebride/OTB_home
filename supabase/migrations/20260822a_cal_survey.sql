-- 작가 캘린더에서 신부가 낸 촬영 설문을 바로 열 수 있게. (대표 요청 2026-08-22)
--
-- 보기 화면(/survey-view?b=…)은 이미 있다. 캘린더가 그 링크를 걸 수 있게
-- 예약마다 «설문이 들어왔는지»만 한 칸 더 얹는다.
--
-- 새로 내주는 값은 has_survey 하나뿐이다. 나머지는 그대로 두어
-- 지금 화면이 쓰는 칸이 하나도 바뀌지 않게 했다.
-- 전화번호를 예식 14일 전부터만 주는 규칙도 그대로다.

create or replace function public.staff_calendar(p_staff_id uuid, p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare st public.staff; res jsonb;
begin
  select * into st from public.staff where id = p_staff_id;
  if not found then return null; end if;
  if p_to < p_from or p_to > p_from + 400 then raise exception 'bad range'; end if;

  select jsonb_build_object(
    'staff_name', st.name,
    'from', p_from, 'to', p_to,
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
          'has_survey', exists(select 1 from public.surveys s where s.booking_id = b.id)
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
end$fn$;
