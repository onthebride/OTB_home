-- ============================================
-- 상품·옵션 카탈로그 (관리자 직접 가격/이름/노출 관리) + 예약 단가 스냅샷
-- 1) public.pricing        : 상품·옵션 현재 단가/노출 (관리자 편집)
-- 2) bookings.line_items   : 예약 시점 단가 스냅샷 → 이후 가격 변경돼도 기존 예약 보존
-- 3) booking_options_struct: 스냅샷 우선, 없으면 계산(과거 예약 폴백)
-- ============================================

-- 1) 카탈로그 -----------------------------------
create table if not exists public.pricing (
  code       text primary key,          -- 안정 키
  kind       text not null,             -- product | option | photographer
  name       text not null,
  price      int  not null default 0,
  active     boolean not null default true,   -- 예약폼 노출 여부
  editable   boolean not null default true,   -- 관리자 편집 가능 여부(구상품=false)
  sort       int  not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.pricing enable row level security;

-- 현재 단가 시드 (재적용해도 편집값 보존: do nothing)
insert into public.pricing (code, kind, name, price, active, editable, sort) values
  ('basic',          'product',      '베이직 (데이터형)', 55, true,  true,  10),
  ('travel',         'option',       '출장비',            5,  true,  true,  20),
  ('album',          'option',       '앨범 1권 추가',     5,  true,  true,  30),
  ('reception',      'option',       '연회장 인사촬영',   5,  true,  true,  40),
  ('pyebaek',        'option',       '폐백촬영',          10, true,  true,  50),
  ('part2',          'option',       '2부 촬영',          10, true,  true,  60),
  ('photographer_2p','photographer', '2인 촬영',          25, true,  true,  70),
  ('rep',            'option',       '대표지정',          35, true,  true,  80),
  ('special',        'product',      '스페셜 (구상품)',   55, false, false, 90),
  ('basic_old',      'product',      '베이직(구)',        50, false, false, 91)
on conflict (code) do nothing;

-- 공개: 예약폼·홈·포털용 (anon)
create or replace function public.pricing_public()
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'code',code,'kind',kind,'name',name,'price',price,'active',active) order by sort), '[]'::jsonb)
  from public.pricing;
$$;
revoke all on function public.pricing_public() from public;
grant execute on function public.pricing_public() to anon, authenticated;

-- 관리자: 전체 목록
create or replace function public.admin_pricing_list()
returns setof public.pricing language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  return query select * from public.pricing order by sort, name;
end$$;
revoke all on function public.admin_pricing_list() from public, anon;
grant execute on function public.admin_pricing_list() to authenticated;

-- 관리자: 가격/이름/노출 수정 (editable 항목만)
create or replace function public.admin_pricing_update(p_code text, p_name text, p_price int, p_active boolean)
returns public.pricing language plpgsql security definer set search_path=public,pg_temp as $$
declare r public.pricing;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.pricing set
    name   = coalesce(nullif(p_name,''), name),
    price  = coalesce(p_price, price),
    active = coalesce(p_active, active),
    updated_at = now()
  where code = p_code and editable
  returning * into r;
  if not found then raise exception '수정할 수 없는 항목입니다'; end if;
  return r;
end$$;
revoke all on function public.admin_pricing_update(text,text,int,boolean) from public, anon;
grant execute on function public.admin_pricing_update(text,text,int,boolean) to authenticated;

-- 2) 스냅샷 -----------------------------------
alter table public.bookings add column if not exists line_items jsonb;

-- 계산(폴백): 타입 컬럼 + 접수일 분기 (스냅샷 없는 과거 예약용)
create or replace function public.booking_options_computed(b public.bookings)
returns jsonb language plpgsql stable set search_path=public,pg_temp as $$
declare base int; items jsonb := '[]'::jsonb; co jsonb;
begin
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

-- 표시용: 스냅샷 우선, 없으면 계산
create or replace function public.booking_options_struct(p_id uuid)
returns jsonb language plpgsql stable set search_path=public, pg_temp as $$
declare b public.bookings;
begin
  select * into b from public.bookings where id = p_id; if not found then return '[]'::jsonb; end if;
  if b.line_items is not null and jsonb_array_length(b.line_items) > 0 then return b.line_items; end if;
  return public.booking_options_computed(b);
end$$;
revoke all on function public.booking_options_struct(uuid) from public;
grant execute on function public.booking_options_struct(uuid) to anon, authenticated;

-- 기존 예약 백필: 현재 계산값을 스냅샷으로 고정 (표시 변화 없음)
update public.bookings as b set line_items = public.booking_options_computed(b) where b.line_items is null;

-- 3) 예약 접수/수정 시 스냅샷 저장 -----------------------------------
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
    photographer, rep_designation, photo_usage_agree, total_price, line_items
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
    case when jsonb_array_length(li) > 0 then li else null end
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

create or replace function public.admin_save_booking(p_id uuid, payload jsonb)
returns public.bookings language plpgsql security definer set search_path = public, pg_temp
as $$
declare r public.bookings;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.bookings set
    status            = coalesce(payload->>'status', status),
    admin_note        = payload->>'admin_note',
    contractor_name   = nullif(payload->>'contractor_name',''),
    contractor_phone  = nullif(payload->>'contractor_phone',''),
    contractor_email  = nullif(payload->>'contractor_email',''),
    wedding_date      = nullif(payload->>'wedding_date','')::date,
    wedding_time      = nullif(payload->>'wedding_time',''),
    wedding_venue     = nullif(payload->>'wedding_venue',''),
    groom_name        = nullif(payload->>'groom_name',''),
    groom_phone       = nullif(payload->>'groom_phone',''),
    bride_name        = nullif(payload->>'bride_name',''),
    bride_phone       = nullif(payload->>'bride_phone',''),
    package           = case when payload ? 'package' then nullif(payload->>'package','')
                             else (case when coalesce((payload->>'basic')::boolean, true) then '베이직(데이터형)' else null end) end,
    travel_fee        = coalesce((payload->>'travel_fee')::boolean, false),
    option_album      = coalesce((payload->>'option_album')::boolean, false),
    option_reception  = coalesce((payload->>'option_reception')::boolean, false),
    option_pyebaek    = coalesce((payload->>'option_pyebaek')::boolean, false),
    option_part2      = coalesce((payload->>'option_part2')::boolean, false),
    photographer      = coalesce(nullif(payload->>'photographer',''), '기본'),
    rep_designation   = coalesce((payload->>'rep_designation')::boolean, false),
    photo_usage_agree = coalesce((payload->>'photo_usage_agree')::boolean, false),
    agree_available   = coalesce((payload->>'agree_available')::boolean, false),
    agree_terms       = coalesce((payload->>'agree_terms')::boolean, false),
    total_price       = nullif(payload->>'total_price','')::int,
    deposit_paid      = coalesce((payload->>'deposit_paid')::boolean, deposit_paid),
    balance_paid      = coalesce((payload->>'balance_paid')::boolean, balance_paid),
    custom_options    = case when payload ? 'custom_options' then coalesce(payload->'custom_options','[]'::jsonb) else custom_options end,
    line_items        = case when payload ? 'line_items' then (case when jsonb_array_length(coalesce(payload->'line_items','[]'::jsonb)) > 0 then payload->'line_items' else null end) else line_items end,
    assignee_id       = case when payload ? 'assignee_id' then nullif(payload->>'assignee_id','')::uuid else assignee_id end,
    sub_assignee_id   = case when payload ? 'sub_assignee_id' then nullif(payload->>'sub_assignee_id','')::uuid else sub_assignee_id end
  where id = p_id
  returning * into r;
  return r;
end;
$$;
revoke all on function public.admin_save_booking(uuid, jsonb) from public, anon;
grant execute on function public.admin_save_booking(uuid, jsonb) to authenticated;
