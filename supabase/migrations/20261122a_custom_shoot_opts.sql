-- 커스텀 옵션 중 「작가에게도 보이기」를 켠 것만 작가 화면에 싣는다
-- (대표 2026-11-22 «○월 ○일 ○○○ 내가 커스텀 옵션 넣은게 작가 캘린더에는 안가네» — 얼리스타트 30분)
--
-- 8/31 에 정하신 대로 작가에게는 촬영 옵션 넷(연회장·폐백·2부·2인 촬영)만 보였다.
-- 앨범·플러스·출장비·할인 같은 직접 넣은 옵션은 작가가 할 일이 아니라서 일부러 뺐다.
-- 그런데 「얼리스타트 30분」처럼 작가가 **알아야 하는** 직접 넣은 옵션이 생겼다.
-- 이름만으로 갈라낼 수는 없다(플러스·할인도 직접 넣은 옵션이다) → 옵션마다 대표가 고른다.
--
--   custom_options 의 한 줄:  {"name": "얼리스타트 30분", "price": 5, "staff": true}
--   staff 가 true 인 줄만, **이름만** 작가에게 간다. 값(가격)은 안 간다.
--
-- ⚠ 작가에게 옵션 이름을 보여 주는 자리는 여럿이다. 한 곳만 고치면 한쪽에서만 보인다.
--   그래서 셈을 private.custom_shoot 하나로 두고 모두가 같이 부른다.
--     다음 촬영 카드(shoot_items) · 달력 상세(staff_calendar) · 월요일 확인(staff_schedule·staff_one)
--     · 캘린더 구독(staff_cal_feed) · 설문 보기(survey_view)
-- ⚠ 이전 줄(staff 가 없는 줄)은 그대로 안 보인다. 대표가 켜기 전에는 달라지는 것이 없다.
-- ⚠ 새 함수를 만들 뿐 나머지는 create or replace — 권한·본문은 지금 운영 판에 이 한 줄만 더했다.

/* ── 작가에게 보일 커스텀 옵션 이름들 ──
   ⚠ staff 가 진짜 true(불리언)일 때만. 글자 "true" 나 1 은 켠 것이 아니다.
   ⚠ 이름이 비었으면 빼고, 너무 길면 40자에서 자른다. 값(price)은 어디에도 안 나간다.
   ⚠ 없으면 빈 목록을 준다. null 을 주면 || 로 붙일 때 통째로 null 이 된다 */
create or replace function private.custom_shoot(b public.bookings)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select coalesce(jsonb_agg(to_jsonb(left(btrim(o.v->>'name'), 40)) order by o.n), '[]'::jsonb)
    from jsonb_array_elements(case when jsonb_typeof(b.custom_options) = 'array'
                                   then b.custom_options else '[]'::jsonb end)
         with ordinality as o(v, n)
   where jsonb_typeof(o.v) = 'object'
     and o.v->'staff' = 'true'::jsonb
     and nullif(btrim(o.v->>'name'), '') is not null
$$;
revoke all on function private.custom_shoot(public.bookings) from public, anon, authenticated;

/* ── ① 다음 촬영 카드 ── (opts 끝에 붙인다) */
CREATE OR REPLACE FUNCTION private.shoot_items(p_staff_id uuid, p_day date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_agg(jsonb_build_object(
          'booking_id', b.id, 'wedding_time', b.wedding_time, 'wedding_venue', b.wedding_venue,
          'role', case when b.assignee_id = p_staff_id then '메인' else '서브' end,
          'bride_name', b.bride_name, 'groom_name', b.groom_name,
          -- ⚠ 연락처는 예식 2주 전부터만. 날짜 칸과 같은 규칙이라야 한다
          'bride_phone', case when b.wedding_date <= current_date + 14 then b.bride_phone end,
          'groom_phone', case when b.wedding_date <= current_date + 14 then b.groom_phone end,
          -- 상품 (대표 2026-08-31). 서브는 상품과 무관하게 하는 일이 같다
          'product', case when b.assignee_id = p_staff_id
                          then coalesce(nullif(regexp_replace(coalesce(b.package,''), '\s*\(.*\)\s*', '', 'g'), ''), '베이직')
                          else '서브촬영' end,
          /* 신부님이 나를 지정하신 촬영인가 (대표 2026-09-19).
             ⚠ pick_pin 은 언제나 메인이다 — 서브로 들어가신 분께는 안 붙는다.
             ⚠ 받으실 돈은 서버가 셈해서 보낸다. 화면에서 다시 셈하면 수수료를
               다시 떼기로 하실 때 두 군데를 고쳐야 하고 한쪽이 남는다 */
          'pick_mine', (b.pick_pin is not null and b.pick_pin = p_staff_id),
          'pick_pay_won', case when b.pick_pin = p_staff_id
                               then private.pick_staff_pay(b.pick_fee_won) end,
          -- 촬영 옵션만. 앨범·출장·대표지정은 넣지 않는다.
          -- 다만 대표가 「작가에게도 보이기」를 켠 커스텀 옵션(얼리스타트 같은)은 뒤에 붙는다 (2026-11-22)
          'opts', (select coalesce(jsonb_agg(x), '[]'::jsonb) from unnest(array_remove(array[
                     case when coalesce(b.option_reception, false) then '연회장 인사촬영' end,
                     case when coalesce(b.option_pyebaek, false) then '폐백촬영' end,
                     case when coalesce(b.option_part2, false) then '2부 촬영' end,
                     case when b.photographer = '2인 촬영' then '2인 촬영' end], null)) x)
                   || private.custom_shoot(b),
          -- 설문을 냈으면 카드에서 바로 열 수 있게 (대표 «오른쪽에 설문보는 버튼도 넣어줘»)
          'has_survey', exists(select 1 from public.surveys sv where sv.booking_id = b.id),
          -- 블로그·SNS 에 올려도 되는지 (대표 요청 2026-08-28)
          'photo_usage_agree', coalesce(b.photo_usage_agree, false))
          -- 같이 가는 작가 (대표 2026-09-05). 없으면 아무 칸도 안 붙는다
          || private.peer_of(b, p_staff_id)
          order by b.wedding_time)
        from public.bookings b
        where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
          and b.status <> '취소' and b.wedding_date = p_day
$function$;

/* ── ② 달력 상세 ── ('custom_shoot' 한 줄) */
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
          -- 대표가 「작가에게도 보이기」를 켠 커스텀 옵션 이름 (2026-11-22)
          'custom_shoot', private.custom_shoot(b),
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
end$function$;

/* ── ③ 월요일 확인 페이지 둘 ── ('custom_shoot' 한 줄씩) */
CREATE OR REPLACE FUNCTION public.staff_schedule(p_staff_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
      'custom_shoot', private.custom_shoot(b),
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
end$function$;

CREATE OR REPLACE FUNCTION public.staff_one(p_booking_id uuid, p_staff_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    'custom_shoot', private.custom_shoot(b),
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
end$function$;

/* ── ④ 캘린더 구독 ── ('extra' 한 줄. 이름만 — 값은 안 싣는다) */
CREATE OR REPLACE FUNCTION public.staff_cal_feed(p_token text, p_client text DEFAULT 'other'::text, p_ua text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sid uuid;
  today date := (now() at time zone 'Asia/Seoul')::date;
  cl text;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{32}$' then return null; end if;
  select f.staff_id into sid from private.staff_cal_feed f where f.token = p_token;
  if sid is null then return null; end if;

  cl := case when p_client in ('google', 'apple', 'naver') then p_client else 'other' end;
  insert into private.staff_cal_fetch as x (staff_id, client, last_ua) values (sid, cl, left(p_ua, 200))
  on conflict (staff_id, client) do update set last_at = now(), n = x.n + 1, last_ua = left(p_ua, 200);

  return jsonb_build_object('events', coalesce((
    select jsonb_agg(jsonb_build_object(
             /* 일정 번호 — 예약 번호를 그대로 쓰지 않는다. 예약 번호는 신부님 포털 열쇠다.
                구독한 일정은 구글·애플·네이버 서버에 남으므로 거기 열쇠가 남으면 안 된다.
                늘 같은 값이라야 시각이 바뀐 일정이 새 일정이 아니라 같은 일정으로 잡힌다 */
             'id', md5('otb-cal:' || b.id::text),
             'date', b.wedding_date,
             'time', b.wedding_time,
             'venue', b.wedding_venue,
             'role', case when b.assignee_id = sid then '메인' else '서브' end,
             'reception', coalesce(b.option_reception, false),
             'pyebaek', coalesce(b.option_pyebaek, false),
             'part2', coalesce(b.option_part2, false),
             'two', coalesce(b.photographer = '2인 촬영', false),
             -- 대표가 「작가에게도 보이기」를 켠 커스텀 옵션 이름 (2026-11-22)
             'extra', private.custom_shoot(b),
             'pick', coalesce(b.pick_pin = sid, false),
             'rep', coalesce(b.rep_designation, false),
             'peer_role', pr.peer->>'peer_role',
             'peer_name', pr.peer->>'peer_name',
             -- 신랑신부 이름 (대표 2026-11-02 «신랑신부 이름 넣어»). 연락처는 여전히 안 싣는다
             'groom', nullif(trim(b.groom_name), ''),
             'bride', nullif(trim(b.bride_name), ''))
           order by b.wedding_date, b.wedding_time)
    from public.bookings b
    cross join lateral (select private.peer_of(b, sid) as peer) pr
    where (b.assignee_id = sid or b.sub_assignee_id = sid)
      and b.status <> '취소'
      and b.wedding_date >= today - 60), '[]'::jsonb));
end$function$;

/* ── ⑤ 설문 보기 ── ('custom_shoot' 한 줄) */
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
    'travel_fee', b.travel_fee, 'photographer', b.photographer, 'rep_designation', b.rep_designation,
    -- 대표가 「작가에게도 보이기」를 켠 커스텀 옵션 이름 (2026-11-22)
    'custom_shoot', private.custom_shoot(b));

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
end$function$;
