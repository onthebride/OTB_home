-- 넷째 체크(신부 설문 확인)를 읽는 쪽 세 곳을 한 기준(check_done)으로 맞춘다.
--   · admin_unconfirmed     — 대표 홈의 미확인 목록
--   · admin_booking_checks  — 예약 상세의 «작가 확인» 표
--   · staff_schedule/one    — 작가 화면의 chk
-- 판정을 여기저기 손으로 적어두면 나중에 한 곳만 고치고 넘어가게 된다.

create or replace function public.admin_unconfirmed()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'booking_id', b.id, 'contractor_name', b.contractor_name,
    'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time, 'wedding_venue', b.wedding_venue,
    'assignee_id', b.assignee_id, 'sub_assignee_id', b.sub_assignee_id,
    'main_ok', public.check_done(b.id, b.assignee_id),
    'sub_ok', (b.sub_assignee_id is null) or public.check_done(b.id, b.sub_assignee_id)
  ) order by b.wedding_date, b.wedding_time), '[]'::jsonb) into res
  from public.bookings b
  where b.status <> '취소' and b.deposit_paid and b.assignee_id is not null
    and (b.check_sent_at is not null or b.sub_check_sent_at is not null)
    and b.wedding_date >= current_date and b.wedding_date <= current_date + 30;
  return res;
end$fn$;

create or replace function public.admin_booking_checks(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'staff', s.name, 'attend', c.attend, 'arrival', c.arrival, 'options', c.options,
    'survey', c.survey, 'note', c.note, 'checked_at', c.checked_at,
    'done', public.check_done(c.booking_id, c.staff_id))), '[]'::jsonb) into res
  from public.assignment_checks c
  join public.staff s on s.id = c.staff_id
  where c.booking_id = p_booking_id;
  return res;
end$fn$;
revoke all on function public.admin_booking_checks(uuid) from public, anon;
grant execute on function public.admin_booking_checks(uuid) to authenticated;

-- 작가 화면 둘. chk 에 survey 를 함께 담고, 완료 여부는 check_done 으로 준다
-- (has_survey 는 어제 넣은 «설문 보기» 버튼이 쓴다)
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
      'chk', (select jsonb_build_object('attend', c.attend, 'arrival', c.arrival, 'options', c.options,
                                        'survey', c.survey, 'note', c.note, 'checked_at', c.checked_at,
                                        'done', public.check_done(b.id, p_staff_id))
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
    'chk', (select jsonb_build_object('attend', c.attend, 'arrival', c.arrival, 'options', c.options,
                                      'survey', c.survey, 'note', c.note, 'checked_at', c.checked_at,
                                      'done', public.check_done(b.id, p_staff_id))
            from public.assignment_checks c where c.booking_id = b.id and c.staff_id = p_staff_id)
  )));
end$fn$;
