-- 2인 촬영이면 같이 가는 작가의 연락처를 서로 보여준다 (대표 2026-09-05
--   «2인촬영인경우 작가들캘린더에서 서브인경우 메인연락처 메인은 서브연락처 기재해줘»)
--
-- 지금까지는 **메인만** 서브 이름·연락처를 봤다 (staff_schedule 의 sub_name·sub_phone).
-- 서브는 자기가 누구와 가는지도 몰랐다. 예식 날 만나서 처음 인사하는 셈이다.
--
-- ⚠ 「상대」로 적는다. 내가 메인이면 상대는 서브, 내가 서브면 상대는 메인이다.
--   한쪽만 놓고 만들면 반대쪽에서 또 빠진다 — 그래서 sub_* 를 늘리지 않고 peer_* 로 새로 둔다.
-- ⚠ 신부·신랑 연락처는 예식 2주 전부터만 보인다(손님 사생활). 같이 가는 작가는 다르다 —
--   동료끼리 미리 맞출 일이 있어 배정되면 바로 보인다.
-- ⚠ 2인 촬영이면서 **둘 다 배정된 것**만. 한쪽이 비면 보여줄 상대가 없다.
-- ⚠ 두 군데(다음 촬영 카드 · 달력 상세)가 같은 것을 그린다. 한 곳만 고치면 한쪽에서만 보인다.
--   그래서 셈을 함수 하나로 두고 둘이 같이 부른다.

/* ── 같이 가는 작가가 누구인가 ──
   ⚠ 없으면 빈 것을 준다. null 을 주면 || 로 붙일 때 통째로 null 이 된다 */
create or replace function private.peer_of(b public.bookings, p_staff_id uuid)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select case
    when b.photographer <> '2인 촬영' then '{}'::jsonb
    when b.assignee_id is null or b.sub_assignee_id is null then '{}'::jsonb
    when b.assignee_id = p_staff_id then
      coalesce((select jsonb_build_object('peer_role', '서브', 'peer_name', s.name, 'peer_phone', s.phone)
                  from public.staff s where s.id = b.sub_assignee_id), '{}'::jsonb)
    when b.sub_assignee_id = p_staff_id then
      coalesce((select jsonb_build_object('peer_role', '메인', 'peer_name', s.name, 'peer_phone', s.phone)
                  from public.staff s where s.id = b.assignee_id), '{}'::jsonb)
    else '{}'::jsonb
  end;
$$;
revoke all on function private.peer_of(public.bookings, uuid) from public, anon, authenticated;

/* ── ① 다음 촬영 카드 ── */
create or replace function private.shoot_items(p_staff_id uuid, p_day date)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $$
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
          -- 촬영 옵션만. 앨범·출장·대표지정은 넣지 않는다
          'opts', (select coalesce(jsonb_agg(x), '[]'::jsonb) from unnest(array_remove(array[
                     case when coalesce(b.option_reception, false) then '연회장 인사촬영' end,
                     case when coalesce(b.option_pyebaek, false) then '폐백촬영' end,
                     case when coalesce(b.option_part2, false) then '2부 촬영' end,
                     case when b.photographer = '2인 촬영' then '2인 촬영' end], null)) x),
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
$$;
revoke all on function private.shoot_items(uuid, date) from public, anon, authenticated;

/* ── ② 달력 상세 ── */
create or replace function public.staff_calendar(p_staff_id uuid, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $$
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
          'bride_phone', case when b.wedding_date <= current_date + 14 then b.bride_phone end,
          'groom_phone', case when b.wedding_date <= current_date + 14 then b.groom_phone end,
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
revoke all on function public.staff_calendar(uuid, date, date) from public;
grant execute on function public.staff_calendar(uuid, date, date) to anon, authenticated;
