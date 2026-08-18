-- 작가 링크는 '이번에 확인할 주'의 예식만 보여준다.
-- 대표 운영 규칙: 월요일에 그 주 목요일 ~ 다음 주 수요일(월요일 기준 +3 ~ +9) 스케줄 체크를 요청.
-- 그래서 창을 '가장 최근 월요일(오늘이 월요일이면 오늘) + 3 ~ +9' 로 잡으면
-- 톡을 받은 주 내내(월~일) 같은 목록이 보이고, 다음 월요일에 다음 주 것으로 넘어간다.
-- 이미 지난 예식은 뺀다(체크할 이유가 없음).
create or replace function public.staff_schedule(p_staff_id uuid)
returns jsonb language plpgsql security definer set search_path=public, pg_temp
as $fn$
declare st public.staff; arr jsonb; mon date;
begin
  select * into st from public.staff where id = p_staff_id;
  if not found then return null; end if;
  mon := current_date - ((extract(dow from current_date)::int + 6) % 7);   -- 가장 최근 월요일
  select coalesce(jsonb_agg(x order by (x->>'wedding_date'), (x->>'wedding_time')), '[]'::jsonb) into arr
  from (
    select jsonb_build_object(
      'booking_id', b.id,
      'role', case when b.assignee_id = p_staff_id then '메인' else '서브' end,
      'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time, 'wedding_venue', b.wedding_venue,
      'bride_name', b.bride_name, 'bride_phone', b.bride_phone,
      'groom_name', b.groom_name, 'groom_phone', b.groom_phone,
      'option_reception', b.option_reception, 'option_pyebaek', b.option_pyebaek, 'option_part2', b.option_part2,
      'option_album', b.option_album, 'photographer', b.photographer, 'rep_designation', b.rep_designation, 'custom_options', b.custom_options,
      'package', b.package,
      'sub_name',  (select s2.name  from public.staff s2 where s2.id = b.sub_assignee_id and b.assignee_id = p_staff_id and b.photographer = '2인 촬영'),
      'sub_phone', (select s2.phone from public.staff s2 where s2.id = b.sub_assignee_id and b.assignee_id = p_staff_id and b.photographer = '2인 촬영'),
      'chk', (select jsonb_build_object('attend', c.attend, 'arrival', c.arrival, 'options', c.options, 'note', c.note, 'checked_at', c.checked_at)
              from public.assignment_checks c where c.booking_id = b.id and c.staff_id = p_staff_id)
    ) as x
    from public.bookings b
    where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
      and b.status <> '취소'
      and b.wedding_date >= current_date
      and b.wedding_date between mon + 3 and mon + 9
  ) t;
  return jsonb_build_object('staff_name', st.name, 'schedule', arr,
                            'week_from', mon + 3, 'week_to', mon + 9);
end; $fn$;
revoke all on function public.staff_schedule(uuid) from public;
grant execute on function public.staff_schedule(uuid) to anon, authenticated;
