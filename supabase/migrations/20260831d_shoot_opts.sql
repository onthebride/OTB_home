-- 작가 캘린더 예식 카드에 상품과 촬영 옵션을 더한다 (대표 2026-08-31)
--
--   «캘린더로 그 내용을 확인할 수 있게 통합하고 싶어»
--   «옵션은 촬영옵션만 보이게 되어 있을텐데? 앨범 플러스 같은거 빼고
--     연회장 2부 폐백 2인촬영 옵션들은 보여»
--
-- 대표가 카톡에 붙이시던 글과 캘린더를 견줘보니, 캘린더에 없는 것이 이 둘뿐이었다.
-- (시간·장소·신랑신부 성함·연락처는 이미 있다)
--
-- ⚠ 옵션은 **촬영에 관계된 넷만**. 앨범·출장·대표지정·직접 넣은 옵션은 작가가 할 일이
--   아니다 — 그날 판이 달라지지 않는다. 작가 체크 페이지(staff-schedule.js 의 opts)와
--   같은 넷이라야 한다: 연회장 인사촬영 · 폐백촬영 · 2부 촬영 · 2인 촬영.
--
-- ⚠ 서브작가에게는 상품을 「서브촬영」으로 보여준다 — 체크 페이지가 그렇게 하고 있다.
--   서브는 상품과 무관하게 하는 일이 같다.

create or replace function private.shoot_items(p_staff_id uuid, p_day date)
returns jsonb language sql stable security definer
set search_path to 'public', 'pg_temp' as $function$
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
          order by b.wedding_time)
        from public.bookings b
        where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
          and b.status <> '취소' and b.wedding_date = p_day
$function$;
revoke all on function private.shoot_items(uuid, date) from public, anon, authenticated;
