-- ============================================
-- 상품·가격 2단계: 손님용 새 옵션 추가/삭제
-- is_core: 폼에 하드코딩된 기본 항목(true) vs 관리자가 추가한 손님용 옵션(false).
-- 추가 옵션은 예약폼에 동적 체크박스로 노출 → 선택 시 custom_options + line_items 스냅샷에 저장.
-- ============================================
alter table public.pricing add column if not exists is_core boolean not null default false;
update public.pricing set is_core = true
  where code in ('basic','travel','album','reception','pyebaek','part2','photographer_2p','rep','special','basic_old');

-- pricing_public 에 is_core 포함
create or replace function public.pricing_public()
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'code',code,'kind',kind,'name',name,'price',price,'active',active,'is_core',is_core) order by sort), '[]'::jsonb)
  from public.pricing;
$$;

-- 관리자: 손님용 새 옵션 추가 (kind=option, is_core=false)
create or replace function public.admin_pricing_add(p_name text, p_price int)
returns public.pricing language plpgsql security definer set search_path=public,pg_temp as $$
declare r public.pricing; c text; nx int;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if nullif(trim(p_name),'') is null then raise exception '이름을 입력하세요'; end if;
  c := 'x_' || substr(replace(gen_random_uuid()::text,'-',''),1,10);
  select coalesce(max(sort),0)+1 into nx from public.pricing;
  insert into public.pricing(code, kind, name, price, active, editable, is_core, sort)
    values (c, 'option', trim(p_name), coalesce(p_price,0), true, true, false, nx)
  returning * into r;
  return r;
end$$;
revoke all on function public.admin_pricing_add(text,int) from public, anon;
grant execute on function public.admin_pricing_add(text,int) to authenticated;

-- 관리자: 옵션 삭제 (손님용 extra만; 기본 항목은 노출 끄기만 가능)
create or replace function public.admin_pricing_delete(p_code text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  delete from public.pricing where code = p_code and is_core = false;
  if not found then raise exception '삭제할 수 없는 항목입니다 (기본 항목은 노출 끄기만 가능).'; end if;
end$$;
revoke all on function public.admin_pricing_delete(text) from public, anon;
grant execute on function public.admin_pricing_delete(text) to authenticated;

-- submit_booking: 손님이 고른 추가 옵션(custom_options)도 저장하도록 보강
create or replace function public.submit_booking(payload jsonb)
returns uuid language plpgsql security definer set search_path = public, pg_temp
as $$
declare new_id uuid; li jsonb; tot int;
begin
  li := coalesce(payload->'line_items', '[]'::jsonb);
  tot := coalesce(
    (select sum((it->>'price')::int) from jsonb_array_elements(li) it),
    nullif(payload->>'total_price','')::int);
  insert into public.bookings (
    agree_available, agree_terms,
    contractor_name, contractor_phone, contractor_email,
    wedding_date, wedding_time, wedding_venue,
    groom_name, groom_phone, bride_name, bride_phone,
    package, travel_fee,
    option_album, option_reception, option_pyebaek, option_part2,
    photographer, rep_designation, photo_usage_agree, total_price, line_items, custom_options
  ) values (
    coalesce((payload->>'agree_available')::boolean, false),
    coalesce((payload->>'agree_terms')::boolean, false),
    nullif(payload->>'contractor_name',''), nullif(payload->>'contractor_phone',''), nullif(payload->>'contractor_email',''),
    nullif(payload->>'wedding_date','')::date, nullif(payload->>'wedding_time',''), nullif(payload->>'wedding_venue',''),
    nullif(payload->>'groom_name',''), nullif(payload->>'groom_phone',''), nullif(payload->>'bride_name',''), nullif(payload->>'bride_phone',''),
    case when coalesce((payload->>'basic')::boolean, true) then '베이직(데이터형)' else null end,
    coalesce((payload->>'travel_fee')::boolean, false),
    coalesce((payload->>'option_album')::boolean, false),
    coalesce((payload->>'option_reception')::boolean, false),
    coalesce((payload->>'option_pyebaek')::boolean, false),
    coalesce((payload->>'option_part2')::boolean, false),
    coalesce(nullif(payload->>'photographer',''), '기본'),
    coalesce((payload->>'rep_designation')::boolean, false),
    coalesce((payload->>'photo_usage_agree')::boolean, false),
    tot,
    case when jsonb_array_length(li) > 0 then li else null end,
    coalesce(payload->'custom_options', '[]'::jsonb)
  ) returning id into new_id;
  perform private.otb_push('🔔 신규 예약',
    coalesce(nullif(payload->>'contractor_name',''),'')
    || coalesce(' · ' || nullif(payload->>'wedding_date',''), '')
    || coalesce(' · ' || nullif(payload->>'wedding_venue',''), ''),
    '/admin');
  return new_id;
end;
$$;
revoke all on function public.submit_booking(jsonb) from public;
grant execute on function public.submit_booking(jsonb) to anon, authenticated;
