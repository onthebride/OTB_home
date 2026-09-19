/* 작가 캘린더에 「신부님이 지정하신 촬영」 표시 (대표 2026-09-19
     «작가 캘린더에 지정된 촬영은 표시가 있어야하는데? 있나?» — 없었다)

   작가님 입장에서 지정 촬영은 다른 촬영과 다르다. 신부님이 나를 골라 돈을 더 내신 자리이고
   그만큼 페이도 더 나간다. 그런데 캘린더에는 아무 표시가 없어 여느 촬영과 똑같이 보였다.

   ⚠ 받으실 돈은 **서버가 셈해서 보낸다**(private.pick_staff_pay).
     화면에서 다시 셈하면 수수료를 다시 떼기로 하실 때 두 군데를 고쳐야 하고, 한쪽이 남는다.
   ⚠ pick_pin 은 언제나 메인이다 — 서브로 들어가신 분께는 안 붙는다.
   ⚠ 우선순위(pick_wish)는 **안 보낸다.** 그건 약속이 아니고 대표가 참고하시는 것이라,
     작가님께 「내가 1순위였다」를 알릴 자리가 아니다.

   이 파일은 살아 있는 정의를 읽어와 한 군데만 갈아 끼운 것이다 (_pickmine_patch.mjs). */
/* 지정비 중 **작가님이 받으실 돈**. 한 자리에서만 셈한다.
   ⚠ 지금은 회사가 한 푼도 안 뗀다 (cut_pct·cut_max 가 0). 그래도 길은 살려 둔다 —
     다시 떼기로 하시면 private.pick_rules() 두 줄만 고치면 여기가 따라온다.
   ⚠ 0 밑으로는 안 내려간다. */
create or replace function private.pick_staff_pay(p_fee int)
returns int language sql stable
set search_path to 'private', 'public', 'pg_temp'
as $fn$
  select greatest(
    coalesce(p_fee, 0) - least(
      floor(coalesce(p_fee, 0) * (private.pick_rules()->>'cut_pct')::numeric / 100)::int,
      (private.pick_rules()->>'cut_max')::int),
    0);
$fn$;

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
$function$
;

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
          /* 신부님이 나를 지정하신 촬영인가 (대표 2026-09-19).
             ⚠ pick_pin 은 언제나 메인이다 — 서브로 들어가신 분께는 안 붙는다.
             ⚠ 받으실 돈은 서버가 셈해서 보낸다. 화면에서 다시 셈하면 수수료를
               다시 떼기로 하실 때 두 군데를 고쳐야 하고 한쪽이 남는다 */
          'pick_mine', (b.pick_pin is not null and b.pick_pin = p_staff_id),
          'pick_pay_won', case when b.pick_pin = p_staff_id
                               then private.pick_staff_pay(b.pick_fee_won) end,
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
end$function$
;
