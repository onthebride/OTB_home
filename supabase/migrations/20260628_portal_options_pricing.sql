-- 포털/알림톡 상품·옵션 내역 단가를 접수일 기준 개정가로 분기.
-- 베이직 55→49(2026-06-24~), 앨범 5→10(2026-06-25~). 기존 예약은 단가 유지.
create or replace function public.booking_options_struct(p_id uuid)
returns jsonb language plpgsql stable set search_path=public, pg_temp as $$
declare b public.bookings; base int; items jsonb := '[]'::jsonb; co jsonb;
begin
  select * into b from public.bookings where id = p_id; if not found then return '[]'::jsonb; end if;
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
  if b.option_album then items := items || jsonb_build_object('group','옵션','name','앨범 1권 추가','price', case when b.created_at >= timestamptz '2026-06-25 03:15:00+00' then 10 else 5 end); end if;
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
