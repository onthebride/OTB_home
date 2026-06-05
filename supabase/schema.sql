-- ============================================
-- 온더브라이드 예약 시스템 — Supabase 스키마 (최종)
-- 쓰기는 SECURITY DEFINER 함수 submit_booking()로만.
-- 직접 테이블 접근은 RLS로 차단(읽기/쓰기 모두). 관리자는 service_role로 접근.
-- ============================================

create table if not exists public.bookings (
  id                uuid primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),
  status            text not null default '신규',          -- 신규 / 확인 / 전송완료

  agree_available   boolean default false,
  agree_terms       boolean default false,

  contractor_name   text,
  contractor_phone  text,
  contractor_email  text,

  wedding_date      date,
  wedding_time      text,
  wedding_venue     text,

  groom_name        text,
  groom_phone       text,
  bride_name        text,
  bride_phone       text,

  package           text default '베이직(데이터형)',
  travel_fee        boolean default false,
  option_album      boolean default false,
  option_reception  boolean default false,
  option_pyebaek    boolean default false,
  option_part2      boolean default false,
  photographer      text default '기본',
  photo_usage_agree boolean default false,
  total_price       integer,

  admin_note        text,
  sent_at           timestamptz
);

create index if not exists bookings_created_at_idx on public.bookings (created_at desc);
create index if not exists bookings_status_idx on public.bookings (status);

-- RLS: 직접 접근 전면 차단 (정책 없음 = anon/authenticated 모두 불가).
-- 관리자 페이지는 service_role 키로 접근 → RLS 우회.
alter table public.bookings enable row level security;

-- ============================================
-- 공개 예약 접수 함수 (anon이 호출 가능, 정의자 권한으로 RLS 우회 삽입)
-- ============================================
create or replace function public.submit_booking(payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare new_id uuid;
begin
  insert into public.bookings (
    agree_available, agree_terms,
    contractor_name, contractor_phone, contractor_email,
    wedding_date, wedding_time, wedding_venue,
    groom_name, groom_phone, bride_name, bride_phone,
    package, travel_fee,
    option_album, option_reception, option_pyebaek, option_part2,
    photographer, photo_usage_agree, total_price
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
    coalesce((payload->>'photo_usage_agree')::boolean, false),
    nullif(payload->>'total_price','')::int
  ) returning id into new_id;
  return new_id;
end;
$$;

revoke all on function public.submit_booking(jsonb) from public;
grant execute on function public.submit_booking(jsonb) to anon, authenticated;

-- ============================================
-- 관리자(로그인 사용자) 전용 함수
-- ============================================
create or replace function public.admin_list_bookings()
returns setof public.bookings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'unauthorized';
  end if;
  return query select * from public.bookings order by created_at desc;
end;
$$;

create or replace function public.admin_update_booking(p_id uuid, p_status text default null, p_note text default null)
returns public.bookings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r public.bookings;
begin
  if auth.uid() is null then
    raise exception 'unauthorized';
  end if;
  update public.bookings
     set status = coalesce(p_status, status),
         admin_note = coalesce(p_note, admin_note)
   where id = p_id
   returning * into r;
  return r;
end;
$$;

-- 관리자 전용: 예약 건 전체 수정 (옵션/동의/날짜/시간/가격 등)
create or replace function public.admin_save_booking(p_id uuid, payload jsonb)
returns public.bookings
language plpgsql
security definer
set search_path = public, pg_temp
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
    package           = case when coalesce((payload->>'basic')::boolean, true) then '베이직(데이터형)' else null end,
    travel_fee        = coalesce((payload->>'travel_fee')::boolean, false),
    option_album      = coalesce((payload->>'option_album')::boolean, false),
    option_reception  = coalesce((payload->>'option_reception')::boolean, false),
    option_pyebaek    = coalesce((payload->>'option_pyebaek')::boolean, false),
    option_part2      = coalesce((payload->>'option_part2')::boolean, false),
    photographer      = coalesce(nullif(payload->>'photographer',''), '기본'),
    photo_usage_agree = coalesce((payload->>'photo_usage_agree')::boolean, false),
    agree_available   = coalesce((payload->>'agree_available')::boolean, false),
    agree_terms       = coalesce((payload->>'agree_terms')::boolean, false),
    total_price       = nullif(payload->>'total_price','')::int
  where id = p_id
  returning * into r;
  return r;
end;
$$;

revoke all on function public.admin_list_bookings() from public, anon;
revoke all on function public.admin_update_booking(uuid, text, text) from public, anon;
revoke all on function public.admin_save_booking(uuid, jsonb) from public, anon;
grant execute on function public.admin_list_bookings() to authenticated;
grant execute on function public.admin_update_booking(uuid, text, text) to authenticated;
grant execute on function public.admin_save_booking(uuid, jsonb) to authenticated;
