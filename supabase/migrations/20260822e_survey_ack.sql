-- 신부 설문 확인을 배정 체크에서 떼어내 따로 둔다. (대표 요청 2026-08-22)
--
-- 앞서 배정 확인에 넷째 칸으로 붙였는데, 대표 말이 두 일은 시점이 다르다.
--   배정 확인 : 배정받은 직후. 갈 수 있는지, 몇 시까지 가는지, 옵션이 뭔지
--   설문 확인 : 예식 하루 전. 그때 대표가 설문을 보내면 작가가 보고 누른다
-- 그래서 체크 셋은 그대로 두고, 설문은 «언제 확인했는지» 를 따로 적는다.
--
--   [ ] 참석 / 스케줄 확정
--   [ ] 도착 시간 숙지
--   [ ] 촬영 옵션 확인        ← «옵션 · 요청사항 숙지» 에서 이름만 바꿈
--   (설문 확인은 여기 없음 — /survey-view 화면에서 따로 누른다)

-- 오늘 넣었던 넷째 칸을 시각 기록으로 바꾼다
alter table public.assignment_checks drop column if exists survey;
alter table public.assignment_checks
  add column if not exists survey_ack_at timestamptz;

-- 배정 확인 완료 판정은 다시 셋만 본다
create or replace function public.check_done(p_booking_id uuid, p_staff_id uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $fn$
  select exists(
    select 1 from public.assignment_checks c
     where c.booking_id = p_booking_id and c.staff_id = p_staff_id
       and c.attend and c.arrival and c.options);
$fn$;
revoke all on function public.check_done(uuid, uuid) from public;
grant execute on function public.check_done(uuid, uuid) to anon, authenticated;

create or replace function public.submit_assignment_check(payload jsonb)
returns void language plpgsql security definer set search_path = public, pg_temp as $fn$
declare bid uuid; sid uuid;
begin
  bid := nullif(payload->>'booking_id','')::uuid;
  sid := nullif(payload->>'staff_id','')::uuid;
  if bid is null or sid is null then raise exception 'bad request'; end if;
  if not exists(select 1 from public.bookings where id = bid and (assignee_id = sid or sub_assignee_id = sid)) then
    raise exception 'not assigned';
  end if;
  insert into public.assignment_checks (booking_id, staff_id, attend, arrival, options, note, checked_at)
  values (bid, sid, coalesce((payload->>'attend')::boolean,false), coalesce((payload->>'arrival')::boolean,false),
          coalesce((payload->>'options')::boolean,false), nullif(payload->>'note',''), now())
  on conflict (booking_id, staff_id) do update set
    attend = excluded.attend, arrival = excluded.arrival, options = excluded.options,
    note = excluded.note, checked_at = now();
  -- survey_ack_at 은 건드리지 않는다. 설문 확인은 다른 화면에서 따로 눌러 남긴다
end$fn$;

-- ── 설문을 봤다고 누르는 곳 ─────────────────────────────────
-- 작가는 로그인을 안 한다. 설문 링크에 실린 작가 번호로 본인을 가린다.
-- 그 예식에 배정된 작가만 남길 수 있다.
create or replace function public.survey_ack(p_booking_id uuid, p_staff_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
begin
  if p_booking_id is null or p_staff_id is null then raise exception 'bad request'; end if;
  if not exists(select 1 from public.bookings
                 where id = p_booking_id and status <> '취소'
                   and (assignee_id = p_staff_id or sub_assignee_id = p_staff_id)) then
    raise exception 'not assigned';
  end if;
  insert into public.assignment_checks (booking_id, staff_id, survey_ack_at)
  values (p_booking_id, p_staff_id, now())
  on conflict (booking_id, staff_id) do update set survey_ack_at = now();
  return jsonb_build_object('ok', true, 'at', now());
end$fn$;
revoke all on function public.survey_ack(uuid, uuid) from public;
grant execute on function public.survey_ack(uuid, uuid) to anon, authenticated;

-- ── 설문 화면이 «누가 보는지» 를 알고 열리게 ────────────────
-- 작가 번호를 함께 받으면 그 작가가 언제 확인했는지도 같이 준다.
-- 번호 없이 열면(대표가 그냥 열어볼 때) 확인 단추는 안 나온다.
drop function if exists public.survey_view(uuid);
create or replace function public.survey_view(p_booking_id uuid, p_staff_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
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
    'bride_name', b.bride_name, 'bride_phone', b.bride_phone,
    'groom_name', b.groom_name, 'groom_phone', b.groom_phone,
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
    'priority', s.priority, 'prop_ring', s.prop_ring, 'bride_room_req', s.bride_room_req,
    'prog_items', s.prog_items, 'bridal_focus', s.bridal_focus,
    'wonpan_first', s.wonpan_first, 'wonpan_light', s.wonpan_light,
    'extra_req', s.extra_req, 'etc_req', s.etc_req,
    'updated_at', s.updated_at, 'refs', refs);
end$fn$;
revoke all on function public.survey_view(uuid, uuid) from public;
grant execute on function public.survey_view(uuid, uuid) to anon, authenticated;

-- ── 대표 화면: 설문을 봤는지 따로 보여준다 ──────────────────
create or replace function public.admin_booking_checks(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'staff', s.name, 'attend', c.attend, 'arrival', c.arrival, 'options', c.options,
    'note', c.note, 'checked_at', c.checked_at,
    'survey_ack_at', c.survey_ack_at,
    'done', public.check_done(c.booking_id, c.staff_id))), '[]'::jsonb) into res
  from public.assignment_checks c
  join public.staff s on s.id = c.staff_id
  where c.booking_id = p_booking_id;
  return res;
end$fn$;
revoke all on function public.admin_booking_checks(uuid) from public, anon;
grant execute on function public.admin_booking_checks(uuid) to authenticated;

-- 작가 화면 둘: chk 에서 survey 를 빼고 survey_ack_at 을 담는다
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
                                        'note', c.note, 'checked_at', c.checked_at,
                                        'survey_ack_at', c.survey_ack_at,
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
                                      'note', c.note, 'checked_at', c.checked_at,
                                      'survey_ack_at', c.survey_ack_at,
                                      'done', public.check_done(b.id, p_staff_id))
            from public.assignment_checks c where c.booking_id = b.id and c.staff_id = p_staff_id)
  )));
end$fn$;
