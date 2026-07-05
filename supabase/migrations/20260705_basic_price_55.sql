-- ============================================
-- 베이직(데이터형) 기본가 55만원으로 환원 (49 → 55)
-- 2026-06-24 55→49만원 인하했으나, 다시 55만원으로 환원.
-- 인하기간(2026-06-24 ~ 2026-07-05)에 접수한 예약(5건)은 49만원 그대로 유지.
-- 포털 표시용 booking_options_struct 의 베이직 단가 분기에 상한 추가.
-- (프론트: index.html / main.js / admin.js 는 코드에서 별도 수정)
-- ============================================
create or replace function public.booking_options_struct(p_id uuid)
returns jsonb language plpgsql stable set search_path=public, pg_temp as $$
declare b public.bookings; base int; items jsonb := '[]'::jsonb; co jsonb;
begin
  select * into b from public.bookings where id = p_id; if not found then return '[]'::jsonb; end if;
  -- 가격 개정 분기(접수일 기준): 베이직 상시 55(2026-06-24~07-05 인하기간만 49). 앨범 5만원. 각 예약은 접수 당시 단가 유지.
  base := case
            when b.package = '베이직(구)' then 50
            when b.package = '스페셜' then 55
            when b.created_at >= timestamptz '2026-06-24 01:00:00+00'
                 and b.created_at <  timestamptz '2026-07-05 10:50:00+00' then 49
            else 55
          end;
  if b.package is not null then
    items := items || jsonb_build_object('group','상품','name', replace(b.package,'(데이터형)',''), 'price', base);
  end if;
  if b.travel_fee then items := items || jsonb_build_object('group','상품','name','출장비','price', case when b.photographer = '2인 촬영' then 10 else 5 end); end if;
  if b.option_album then items := items || jsonb_build_object('group','옵션','name','앨범 1권 추가','price', 5); end if;
  if b.option_reception then items := items || jsonb_build_object('group','옵션','name','연회장 인사촬영','price',5); end if;
  if b.option_pyebaek then items := items || jsonb_build_object('group','옵션','name','폐백촬영','price',10); end if;
  if b.option_part2 then items := items || jsonb_build_object('group','옵션','name','2부 촬영','price',10); end if;
  for co in select value from jsonb_array_elements(coalesce(b.custom_options, '[]'::jsonb)) loop
    items := items || jsonb_build_object('group','옵션','name', co->>'name', 'price', coalesce((co->>'price')::int, 0));
  end loop;
  if b.photographer = '2인 촬영' then items := items || jsonb_build_object('group','옵션','name','2인 촬영','price',25); end if;
  if b.rep_designation then items := items || jsonb_build_object('group','옵션','name','대표지정','price',35); end if;
  return items;
end$$;
revoke all on function public.booking_options_struct(uuid) from public;
grant execute on function public.booking_options_struct(uuid) to anon, authenticated;
