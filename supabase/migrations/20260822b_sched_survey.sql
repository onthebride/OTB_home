-- 배정 안내 화면(/c?k=… · /staff-schedule)에서도 신부 설문을 열 수 있게.
--
-- 이 화면에는 작가가 체크하는 칸이 셋 있다.
--   [ ] 참석 / 스케줄 확정
--   [ ] 도착 시간 숙지
--   [ ] 옵션 · 요청사항 숙지      ← 정작 «요청사항»을 볼 길이 없었다
-- 신부가 낸 촬영 설문이 바로 그 요청사항인데, 지금까지는 대표가 관리자에서
-- 링크를 복사해 따로 보내줘야 했다. 캘린더와 같은 방식으로 여기에도 붙인다.
--
-- 두 함수 모두 has_survey 한 칸만 더 낸다. 나머지는 글자 하나 안 바꿨다.

create or replace function public.staff_schedule(p_staff_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
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
      'has_survey', exists(select 1 from public.surveys s where s.booking_id = b.id),
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
end$fn$;

create or replace function public.staff_one(p_booking_id uuid, p_staff_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare st public.staff; b public.bookings;
begin
  select * into st from public.staff where id = p_staff_id;
  if not found then return null; end if;
  select * into b from public.bookings
    where id = p_booking_id and (assignee_id = p_staff_id or sub_assignee_id = p_staff_id) and status <> '취소';
  if not found then return null; end if;
  return jsonb_build_object('staff_name', st.name, 'schedule', jsonb_build_array(jsonb_build_object(
    'booking_id', b.id,
    'role', case when b.assignee_id = p_staff_id then '메인' else '서브' end,
    'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time, 'wedding_venue', b.wedding_venue,
    'bride_name', b.bride_name, 'bride_phone', b.bride_phone,
    'groom_name', b.groom_name, 'groom_phone', b.groom_phone,
    'option_reception', b.option_reception, 'option_pyebaek', b.option_pyebaek, 'option_part2', b.option_part2,
    'option_album', b.option_album, 'photographer', b.photographer, 'rep_designation', b.rep_designation, 'custom_options', b.custom_options,
    'package', b.package,
    'has_survey', exists(select 1 from public.surveys s where s.booking_id = b.id),
    'sub_name',  (select s2.name  from public.staff s2 where s2.id = b.sub_assignee_id and b.assignee_id = p_staff_id and b.photographer = '2인 촬영'),
    'sub_phone', (select s2.phone from public.staff s2 where s2.id = b.sub_assignee_id and b.assignee_id = p_staff_id and b.photographer = '2인 촬영'),
    'chk', (select jsonb_build_object('attend', c.attend, 'arrival', c.arrival, 'options', c.options, 'note', c.note, 'checked_at', c.checked_at)
            from public.assignment_checks c where c.booking_id = b.id and c.staff_id = p_staff_id)
  )));
end$fn$;
