-- 「다음 촬영」이 이틀 앞까지 보여준다 (대표 2026-08-29
-- «저게 지금 팝업이 2틀전부터 떴는데 내일껀 아직 안뜨고 있는건 좀 그렇네?»
--  «2틀전스케줄부터 보여주면 될거 같아»)
--
-- 지금까지는 «가장 가까운 하루» 만 냈다. 그래서 토요일 예식이 떠 있는 동안 바로 다음 날인
-- 일요일 예식은 자정이 지나야 보였다. 토·일이 붙은 주가 많은데 하루씩만 보이니 답답하다.
--
-- 새 규칙 — 예식은 **이틀 전부터** 「다음 촬영」에 뜬다.
--   보여줄 날 = 가장 가까운 예식 날(nd) ~ greatest(nd, 오늘+2) 사이의 모든 예식 날
--   · nd 가 오늘이면  → 오늘·내일·모레 것이 다 뜬다
--   · nd 가 7일 뒤면  → 그날 하나만 (그 뒤 이틀 안에 다른 날이 없다)
--   왜 greatest 인가 — 이틀 안에 예식이 없는 분은 칸이 비어버린다.
--   지금처럼 «가장 가까운 날 하나» 는 언제나 보여야 한다.
--
-- ⚠ 모양은 그대로다. next 는 예전처럼 «첫째 날» 이고, 뒤에 오는 날들은 next.more 에 담는다.
--   next 를 쓰던 자리는 손댈 필요가 없다.
-- ⚠ 이 파일은 살아 있는 정의를 떠와서 고친 것이다. 손으로 옮겨 적지 말 것 —
--   option_reception·group_id·g_from 같은 칸이 조용히 빠진다.

-- ===== 하루치 예식 목록 =====
-- next 와 more 가 같은 모양이어야 한다. 두 군데에 따로 쓰면 곧 어긋난다.
create or replace function private.shoot_items(p_staff_id uuid, p_day date)
returns jsonb language sql stable security definer set search_path = public, pg_temp as $fn$
  select jsonb_agg(jsonb_build_object(
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
          and b.status <> '취소' and b.wedding_date = p_day
$fn$;
revoke all on function private.shoot_items(uuid, date) from public, anon, authenticated;

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
end$function$;

revoke all on function public.staff_calendar(uuid, date, date) from public;
grant execute on function public.staff_calendar(uuid, date, date) to anon, authenticated;
