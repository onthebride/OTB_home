-- ============================================
-- 앨범 1권 추가 옵션 단가 환원: 10만원 → 5만원
-- 2026-06-25 5→10만원 개정했으나 해당 기간 앨범 예약 0건 → 다시 5만원으로 환원.
-- 포털 표시용 booking_options_struct 의 앨범 단가 분기를 제거(항상 5).
-- (프론트: index.html / main.js / admin.js 는 코드에서 별도 수정)
-- ============================================
create or replace function public.booking_options_struct(p_id uuid)
returns jsonb language plpgsql stable set search_path=public, pg_temp as $$
declare b public.bookings; base int; items jsonb := '[]'::jsonb; co jsonb;
begin
  select * into b from public.bookings where id = p_id; if not found then return '[]'::jsonb; end if;
  -- 가격 개정 분기(접수일 기준): 베이직 55→49(2026-06-24~). 앨범은 5만원(2026-06-25~07-04 잠시 10만원, 해당기간 예약 0건 → 환원). 기존 예약은 유지.
  base := case
            when b.package = '베이직(구)' then 50
            when b.package = '스페셜' then 55
            when b.created_at >= timestamptz '2026-06-24 01:00:00+00' then 49
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
