-- 2인 촬영이면 메인 작가 화면에 함께 가는 서브 작가 이름·연락처를 내려준다.
-- (현장에서 서로 연락할 수 있어야 해서 대표 요청) 서브 작가 화면에는 넣지 않는다.
create or replace function public.staff_schedule(p_staff_id uuid)
returns jsonb language plpgsql security definer set search_path=public, pg_temp
as $fn$
declare st public.staff; arr jsonb;
begin
  select * into st from public.staff where id = p_staff_id;
  if not found then return null; end if;
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
      -- 내가 메인이고 2인 촬영이면 서브 작가 정보
      'sub_name',  (select s2.name  from public.staff s2 where s2.id = b.sub_assignee_id and b.assignee_id = p_staff_id and b.photographer = '2인 촬영'),
      'sub_phone', (select s2.phone from public.staff s2 where s2.id = b.sub_assignee_id and b.assignee_id = p_staff_id and b.photographer = '2인 촬영'),
      'chk', (select jsonb_build_object('attend', c.attend, 'arrival', c.arrival, 'options', c.options, 'note', c.note, 'checked_at', c.checked_at)
              from public.assignment_checks c where c.booking_id = b.id and c.staff_id = p_staff_id)
    ) as x
    from public.bookings b
    where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
      and b.status <> '취소' and b.wedding_date >= current_date
  ) t;
  return jsonb_build_object('staff_name', st.name, 'schedule', arr);
end; $fn$;
revoke all on function public.staff_schedule(uuid) from public;
grant execute on function public.staff_schedule(uuid) to anon, authenticated;

create or replace function public.staff_one(p_booking_id uuid, p_staff_id uuid)
returns jsonb language plpgsql security definer set search_path=public, pg_temp
as $fn$
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
    'sub_name',  (select s2.name  from public.staff s2 where s2.id = b.sub_assignee_id and b.assignee_id = p_staff_id and b.photographer = '2인 촬영'),
    'sub_phone', (select s2.phone from public.staff s2 where s2.id = b.sub_assignee_id and b.assignee_id = p_staff_id and b.photographer = '2인 촬영'),
    'chk', (select jsonb_build_object('attend', c.attend, 'arrival', c.arrival, 'options', c.options, 'note', c.note, 'checked_at', c.checked_at)
            from public.assignment_checks c where c.booking_id = b.id and c.staff_id = p_staff_id)
  )));
end; $fn$;
revoke all on function public.staff_one(uuid, uuid) from public;
grant execute on function public.staff_one(uuid, uuid) to anon, authenticated;
