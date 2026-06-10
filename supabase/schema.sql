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
    package           = case when payload ? 'package' then nullif(payload->>'package','')
                             else (case when coalesce((payload->>'basic')::boolean, true) then '베이직(데이터형)' else null end) end,
    travel_fee        = coalesce((payload->>'travel_fee')::boolean, false),
    option_album      = coalesce((payload->>'option_album')::boolean, false),
    option_reception  = coalesce((payload->>'option_reception')::boolean, false),
    option_pyebaek    = coalesce((payload->>'option_pyebaek')::boolean, false),
    option_part2      = coalesce((payload->>'option_part2')::boolean, false),
    photographer      = coalesce(nullif(payload->>'photographer',''), '기본'),
    photo_usage_agree = coalesce((payload->>'photo_usage_agree')::boolean, false),
    agree_available   = coalesce((payload->>'agree_available')::boolean, false),
    agree_terms       = coalesce((payload->>'agree_terms')::boolean, false),
    total_price       = nullif(payload->>'total_price','')::int,
    deposit_paid      = coalesce((payload->>'deposit_paid')::boolean, deposit_paid),
    balance_paid      = coalesce((payload->>'balance_paid')::boolean, balance_paid),
    custom_options    = case when payload ? 'custom_options' then coalesce(payload->'custom_options','[]'::jsonb) else custom_options end,
    assignee_id       = case when payload ? 'assignee_id' then nullif(payload->>'assignee_id','')::uuid else assignee_id end,
    sub_assignee_id   = case when payload ? 'sub_assignee_id' then nullif(payload->>'sub_assignee_id','')::uuid else sub_assignee_id end
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

-- 대시보드: 다운로드 링크 저장 + 알림톡 발송 기록 컬럼
alter table public.bookings add column if not exists download_link text;
alter table public.bookings add column if not exists alimtalk_sent jsonb not null default '{}'::jsonb;
alter table public.bookings add column if not exists custom_options jsonb not null default '[]'::jsonb;
alter table public.bookings add column if not exists check_sent_at timestamptz;

create or replace function public.admin_set_download_link(p_id uuid, p_link text)
returns public.bookings language plpgsql security definer set search_path=public, pg_temp
as $$
declare r public.bookings;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.bookings set download_link = nullif(p_link,'') where id = p_id returning * into r;
  return r;
end; $$;
revoke all on function public.admin_set_download_link(uuid, text) from public, anon;
grant execute on function public.admin_set_download_link(uuid, text) to authenticated;

-- 알림톡 발송 기록 (실제 발송 시 호출) — alimtalk_sent에 {템플릿: 시각} 누적
create or replace function public.admin_mark_alimtalk(p_id uuid, p_template text)
returns public.bookings language plpgsql security definer set search_path=public, pg_temp
as $$
declare r public.bookings;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.bookings
     set alimtalk_sent = coalesce(alimtalk_sent,'{}'::jsonb) || jsonb_build_object(p_template, to_jsonb(now()))
   where id = p_id returning * into r;
  return r;
end; $$;
revoke all on function public.admin_mark_alimtalk(uuid, text) from public, anon;
grant execute on function public.admin_mark_alimtalk(uuid, text) to authenticated;

-- ============================================
-- 카카오 알림톡 발송 (솔라피) — 서버측(pg_net + pgcrypto HMAC)
-- 비밀키는 private.solapi 테이블에만 저장(깃허브/공개 미노출). 함수는 읽기만.
-- ============================================
create schema if not exists private;
create table if not exists private.solapi (key text primary key, val text not null);
alter table private.solapi enable row level security;  -- public 노출 차단

-- 예식시간 오전/오후 표기
create or replace function public.fmt_ktime(t text)
returns text language sql immutable as $$
  select case when t is null or t = '' then '' else
    (case when (split_part(t,':',1))::int < 12 then '오전 ' else '오후 ' end)
    || (case when (split_part(t,':',1))::int % 12 = 0 then 12 else (split_part(t,':',1))::int % 12 end)::text
    || ':' || lpad(split_part(t,':',2), 2, '0') end
$$;

-- 상품옵션 텍스트 ([기본상품]/[옵션1]/[옵션2])
create or replace function public.fmt_alimtalk_options(p_id uuid)
returns text language plpgsql stable set search_path=public, pg_temp as $$
declare b public.bookings; base int; g0 text[]; g1 text[]; g2 text[]; co jsonb; res text;
begin
  select * into b from public.bookings where id = p_id; if not found then return ''; end if;
  base := case when b.package = '베이직(구)' then 50 else 55 end;
  g0 := array[]::text[]; g1 := array[]::text[]; g2 := array[]::text[];
  if b.package is not null then g0 := array_append(g0, b.package || ' ' || base || '만원'); end if;
  if b.travel_fee then g0 := array_append(g0, '출장비 5만원'); end if;
  if b.option_album then g1 := array_append(g1, '앨범 1권 추가 5만원'); end if;
  if b.option_reception then g1 := array_append(g1, '연회장 인사촬영 5만원'); end if;
  if b.option_pyebaek then g1 := array_append(g1, '폐백촬영 10만원'); end if;
  if b.option_part2 then g1 := array_append(g1, '2부 촬영 10만원'); end if;
  for co in select value from jsonb_array_elements(coalesce(b.custom_options, '[]'::jsonb)) loop
    g1 := array_append(g1, (co->>'name') || ' ' || coalesce(co->>'price','0') || '만원');
  end loop;
  if b.photographer = '2인 촬영' then g2 := array_append(g2, '2인 촬영 25만원'); end if;
  if b.photographer = '대표지정' then g2 := array_append(g2, '대표지정 35만원'); end if;
  res := '[기본상품] ' || array_to_string(g0, ', ');
  if array_length(g1,1) is not null then res := res || E'\n[옵션1] ' || array_to_string(g1, ', '); end if;
  if array_length(g2,1) is not null then res := res || E'\n[옵션2] ' || array_to_string(g2, ', '); end if;
  return res;
end$$;

-- 솔라피 발송 (HMAC 인증 + pg_net)
create or replace function private.solapi_send(p_to text, p_template_key text, p_vars jsonb)
returns bigint language plpgsql security definer set search_path=private, public, extensions, pg_temp as $$
declare k text; s text; pf text; tpl text; dt text; salt text; sig text; hdr text; req bigint;
begin
  select val into k from private.solapi where key='api_key';
  select val into s from private.solapi where key='api_secret';
  select val into pf from private.solapi where key='pf_id';
  select val into tpl from private.solapi where key=p_template_key;
  if k is null or tpl is null then raise exception 'solapi not configured (%)', p_template_key; end if;
  dt := to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  salt := encode(gen_random_bytes(32), 'hex');
  sig := encode(hmac(dt || salt, s, 'sha256'), 'hex');
  hdr := 'HMAC-SHA256 apiKey=' || k || ', date=' || dt || ', salt=' || salt || ', signature=' || sig;
  select net.http_post(
    url := 'https://api.solapi.com/messages/v4/send',
    body := jsonb_build_object('message', jsonb_build_object(
      'to', regexp_replace(p_to, '[^0-9]', '', 'g'),
      'kakaoOptions', jsonb_build_object('pfId', pf, 'templateId', tpl, 'variables', p_vars))),
    headers := jsonb_build_object('Content-Type','application/json','Authorization',hdr)
  ) into req;
  return req;
end$$;

-- 관리자: 특정 예약에 알림톡 발송 + 발송 기록
create or replace function public.admin_send_alimtalk(p_booking_id uuid, p_template text)
returns jsonb language plpgsql security definer set search_path=public, private, extensions, pg_temp as $$
declare b public.bookings; vars jsonb; req bigint; total int; balance int; sname text; sphone text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select * into b from public.bookings where id = p_booking_id; if not found then raise exception 'booking not found'; end if;
  if b.contractor_phone is null then raise exception '연락처가 없습니다'; end if;
  total := coalesce(b.total_price,0); balance := total - 10;
  select s.name, s.phone into sname, sphone from public.staff s where s.id = b.assignee_id;

  if p_template = 'A' then
    vars := jsonb_build_object('#{고객명}',coalesce(b.contractor_name,''),'#{예식일}',coalesce(b.wedding_date::text,''),
      '#{예식시간}',public.fmt_ktime(b.wedding_time),'#{예식장소}',coalesce(b.wedding_venue,''),
      '#{상품옵션}',public.fmt_alimtalk_options(b.id),'#{총금액}',total::text,'#{계약금}','10');
  elsif p_template = 'B' then
    vars := jsonb_build_object('#{고객명}',coalesce(b.contractor_name,''),'#{예식일}',coalesce(b.wedding_date::text,''),
      '#{예식장소}',coalesce(b.wedding_venue,''),'#{예식시간}',public.fmt_ktime(b.wedding_time));
  elsif p_template = 'C' then
    vars := jsonb_build_object('#{예식일}',coalesce(b.wedding_date::text,''),'#{예식장소}',coalesce(b.wedding_venue,''),
      '#{예식시간}',public.fmt_ktime(b.wedding_time),'#{신부명}',coalesce(b.bride_name,''),'#{신부연락처}',coalesce(b.bride_phone,''),
      '#{신랑명}',coalesce(b.groom_name,''),'#{신랑연락처}',coalesce(b.groom_phone,''),'#{상품옵션}',public.fmt_alimtalk_options(b.id),
      '#{잔금}',balance::text,'#{담당작가}',coalesce(sname,'미정'),'#{담당작가연락처}',coalesce(sphone,''));
  elsif p_template = 'D' then
    vars := '{}'::jsonb;
  elsif p_template = 'E' then
    if b.download_link is null then raise exception '다운로드 링크를 먼저 입력하세요'; end if;
    vars := jsonb_build_object('#{다운로드링크}', b.download_link);
  else raise exception 'bad template'; end if;

  req := private.solapi_send(b.contractor_phone, 'tpl_' || p_template, vars);
  update public.bookings set alimtalk_sent = coalesce(alimtalk_sent,'{}'::jsonb) || jsonb_build_object(p_template, to_jsonb(now())) where id = p_booking_id;
  return jsonb_build_object('ok', true, 'req', req);
end$$;
revoke all on function public.admin_send_alimtalk(uuid, text) from public, anon;
grant execute on function public.admin_send_alimtalk(uuid, text) to authenticated;

-- ============================================
-- 담당자(작가) 명단 + 배정 + 입금확인
-- ============================================
create table if not exists public.staff (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  phone      text,
  active     boolean not null default true,
  is_rep     boolean not null default false,   -- 대표(대표지정 자동배정 대상)
  created_at timestamptz not null default now()
);
alter table public.staff enable row level security;
alter table public.staff add column if not exists is_rep boolean not null default false;

-- 대표지정 예약은 대표 작가로 자동 배정 (미배정일 때만)
create or replace function public.auto_assign_rep()
returns trigger language plpgsql security definer set search_path=public, pg_temp
as $$
declare rep uuid;
begin
  if new.photographer = '대표지정' and new.assignee_id is null then
    select id into rep from public.staff where is_rep = true and active = true order by created_at limit 1;
    if rep is not null then new.assignee_id := rep; end if;
  end if;
  return new;
end; $$;
drop trigger if exists trg_auto_rep on public.bookings;
create trigger trg_auto_rep before insert or update on public.bookings
for each row execute function public.auto_assign_rep();

alter table public.bookings add column if not exists deposit_paid boolean not null default false;
alter table public.bookings add column if not exists balance_paid boolean not null default false;
alter table public.bookings add column if not exists assignee_id uuid references public.staff(id) on delete set null;
alter table public.bookings add column if not exists sub_assignee_id uuid references public.staff(id) on delete set null;

create or replace function public.admin_staff_list()
returns setof public.staff language plpgsql security definer set search_path=public, pg_temp
as $$ begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  return query select * from public.staff order by active desc, name;
end; $$;

create or replace function public.admin_staff_add(p_name text, p_phone text)
returns public.staff language plpgsql security definer set search_path=public, pg_temp
as $$ declare r public.staff; begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  insert into public.staff (name, phone) values (nullif(p_name,''), nullif(p_phone,'')) returning * into r;
  return r;
end; $$;

drop function if exists public.admin_staff_update(uuid, text, text, boolean);
create or replace function public.admin_staff_update(p_id uuid, p_name text, p_phone text, p_active boolean, p_rep boolean)
returns public.staff language plpgsql security definer set search_path=public, pg_temp
as $$ declare r public.staff; begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if coalesce(p_rep,false) then
    update public.staff set is_rep = false where id <> p_id;  -- 대표는 1명만
  end if;
  update public.staff set name=nullif(p_name,''), phone=nullif(p_phone,''),
       active=coalesce(p_active,true), is_rep=coalesce(p_rep,false)
   where id=p_id returning * into r;
  return r;
end; $$;

create or replace function public.admin_staff_delete(p_id uuid)
returns void language plpgsql security definer set search_path=public, pg_temp
as $$ begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  delete from public.staff where id=p_id;
end; $$;

create or replace function public.admin_set_deposit(p_id uuid, p_paid boolean)
returns public.bookings language plpgsql security definer set search_path=public, pg_temp
as $$ declare r public.bookings; begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.bookings
     set deposit_paid = coalesce(p_paid,false),
         status = case
           when coalesce(p_paid,false) and status = '신규' then '확정'
           when not coalesce(p_paid,false) and status = '확정' then '신규'
           else status end
   where id=p_id returning * into r;
  return r;
end; $$;

create or replace function public.admin_set_balance(p_id uuid, p_paid boolean)
returns public.bookings language plpgsql security definer set search_path=public, pg_temp
as $$ declare r public.bookings; begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.bookings set balance_paid = coalesce(p_paid,false) where id=p_id returning * into r;
  return r;
end; $$;

create or replace function public.admin_delete_booking(p_id uuid)
returns void language plpgsql security definer set search_path=public, pg_temp
as $$ begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  delete from public.bookings where id = p_id;  -- surveys/survey_refs는 cascade 삭제
end; $$;

-- 알림톡 발송 표시 on/off (진행 추적용; 실제 발송 연동 시에도 사용)
create or replace function public.admin_set_alimtalk(p_id uuid, p_template text, p_on boolean)
returns public.bookings language plpgsql security definer set search_path=public, pg_temp
as $$ declare r public.bookings; begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if coalesce(p_on,true) then
    update public.bookings set alimtalk_sent = coalesce(alimtalk_sent,'{}'::jsonb) || jsonb_build_object(p_template, to_jsonb(now())) where id=p_id returning * into r;
  else
    update public.bookings set alimtalk_sent = coalesce(alimtalk_sent,'{}'::jsonb) - p_template where id=p_id returning * into r;
  end if;
  return r;
end; $$;

create or replace function public.admin_assign(p_ids uuid[], p_assignee uuid)
returns integer language plpgsql security definer set search_path=public, pg_temp
as $$ declare n integer; begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.bookings set assignee_id = p_assignee where id = any(p_ids);
  get diagnostics n = row_count;
  return n;
end; $$;

-- ============================================
-- 작가 예식 전 스케줄 체크 (작가가 직접 확인)
-- ============================================
create table if not exists public.assignment_checks (
  booking_id  uuid not null references public.bookings(id) on delete cascade,
  staff_id    uuid not null references public.staff(id) on delete cascade,
  attend      boolean not null default false,  -- 참석/스케줄 확정
  arrival     boolean not null default false,  -- 도착 시간 숙지
  options     boolean not null default false,  -- 옵션·요청사항 숙지
  note        text,
  checked_at  timestamptz not null default now(),
  primary key (booking_id, staff_id)
);
alter table public.assignment_checks enable row level security;

-- 작가용: 본인 배정 일정 + 체크 상태 (anon, staff_id 토큰)
create or replace function public.staff_schedule(p_staff_id uuid)
returns jsonb language plpgsql security definer set search_path=public, pg_temp
as $$
declare st public.staff; arr jsonb;
begin
  select * into st from public.staff where id = p_staff_id;
  if not found then return null; end if;
  select coalesce(jsonb_agg(x order by (x->>'wedding_date'), (x->>'wedding_time')), '[]'::jsonb) into arr
  from (
    select jsonb_build_object(
      'booking_id', b.id,
      'role', case when b.assignee_id = p_staff_id then '메인' else '서브' end,
      'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time, 'wedding_venue', b.wedding_venue,
      'bride_name', b.bride_name, 'bride_phone', b.bride_phone,
      'groom_name', b.groom_name, 'groom_phone', b.groom_phone,
      'option_reception', b.option_reception, 'option_pyebaek', b.option_pyebaek, 'option_part2', b.option_part2,
      'option_album', b.option_album, 'photographer', b.photographer, 'custom_options', b.custom_options,
      'chk', (select jsonb_build_object('attend', c.attend, 'arrival', c.arrival, 'options', c.options, 'note', c.note, 'checked_at', c.checked_at)
              from public.assignment_checks c where c.booking_id = b.id and c.staff_id = p_staff_id)
    ) as x
    from public.bookings b
    where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
      and b.status <> '취소' and b.wedding_date >= current_date
  ) t;
  return jsonb_build_object('staff_name', st.name, 'schedule', arr);
end; $$;
revoke all on function public.staff_schedule(uuid) from public;
grant execute on function public.staff_schedule(uuid) to anon, authenticated;

-- 단축 링크 (긴 UUID 링크 → 짧은 코드)
create table if not exists public.short_links (
  code        text primary key,
  target_type text not null,
  booking_id  uuid references public.bookings(id) on delete cascade,
  staff_id    uuid references public.staff(id) on delete cascade,
  created_at  timestamptz not null default now()
);
alter table public.short_links enable row level security;

create or replace function public.admin_make_check_link(p_booking_id uuid, p_staff_id uuid)
returns text language plpgsql security definer set search_path=public, pg_temp
as $$
declare c text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select code into c from public.short_links where booking_id = p_booking_id and staff_id = p_staff_id and target_type = 'check' limit 1;
  if c is not null then return c; end if;
  loop
    c := substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
    begin
      insert into public.short_links (code, target_type, booking_id, staff_id) values (c, 'check', p_booking_id, p_staff_id);
      return c;
    exception when unique_violation then end;
  end loop;
end; $$;
revoke all on function public.admin_make_check_link(uuid, uuid) from public, anon;
grant execute on function public.admin_make_check_link(uuid, uuid) to authenticated;

create or replace function public.resolve_link(p_code text)
returns jsonb language plpgsql security definer set search_path=public, pg_temp
as $$
declare res jsonb;
begin
  select jsonb_build_object('target_type', target_type, 'booking_id', booking_id, 'staff_id', staff_id)
    into res from public.short_links where code = p_code;
  return res;
end; $$;
revoke all on function public.resolve_link(text) from public;
grant execute on function public.resolve_link(text) to anon, authenticated;

-- 작가용: 단일 예식 (anon) — 그 예식 하나만 보여주기
create or replace function public.staff_one(p_booking_id uuid, p_staff_id uuid)
returns jsonb language plpgsql security definer set search_path=public, pg_temp
as $$
declare st public.staff; b public.bookings;
begin
  select * into st from public.staff where id = p_staff_id;
  if not found then return null; end if;
  select * into b from public.bookings
    where id = p_booking_id and (assignee_id = p_staff_id or sub_assignee_id = p_staff_id) and status <> '취소';
  if not found then return null; end if;
  return jsonb_build_object('staff_name', st.name, 'schedule', jsonb_build_array(jsonb_build_object(
    'booking_id', b.id,
    'role', case when b.assignee_id = p_staff_id then '메인' else '서브' end,
    'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time, 'wedding_venue', b.wedding_venue,
    'bride_name', b.bride_name, 'bride_phone', b.bride_phone,
    'groom_name', b.groom_name, 'groom_phone', b.groom_phone,
    'option_reception', b.option_reception, 'option_pyebaek', b.option_pyebaek, 'option_part2', b.option_part2,
    'option_album', b.option_album, 'photographer', b.photographer, 'custom_options', b.custom_options,
    'chk', (select jsonb_build_object('attend', c.attend, 'arrival', c.arrival, 'options', c.options, 'note', c.note, 'checked_at', c.checked_at)
            from public.assignment_checks c where c.booking_id = b.id and c.staff_id = p_staff_id)
  )));
end; $$;
revoke all on function public.staff_one(uuid, uuid) from public;
grant execute on function public.staff_one(uuid, uuid) to anon, authenticated;

-- 작가 체크 제출 (anon) — 본인 배정 예약만
create or replace function public.submit_assignment_check(payload jsonb)
returns void language plpgsql security definer set search_path=public, pg_temp
as $$
declare bid uuid; sid uuid;
begin
  bid := nullif(payload->>'booking_id','')::uuid;
  sid := nullif(payload->>'staff_id','')::uuid;
  if bid is null or sid is null then raise exception 'bad request'; end if;
  if not exists(select 1 from public.bookings where id = bid and (assignee_id = sid or sub_assignee_id = sid)) then
    raise exception 'not assigned';
  end if;
  insert into public.assignment_checks (booking_id, staff_id, attend, arrival, options, note, checked_at)
  values (bid, sid, coalesce((payload->>'attend')::boolean,false), coalesce((payload->>'arrival')::boolean,false),
          coalesce((payload->>'options')::boolean,false), nullif(payload->>'note',''), now())
  on conflict (booking_id, staff_id) do update set
    attend = excluded.attend, arrival = excluded.arrival, options = excluded.options, note = excluded.note, checked_at = now();
end; $$;
revoke all on function public.submit_assignment_check(jsonb) from public;
grant execute on function public.submit_assignment_check(jsonb) to anon, authenticated;

-- 관리자: 예약의 작가 확인 상태
create or replace function public.admin_booking_checks(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path=public, pg_temp
as $$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('staff', s.name, 'attend', c.attend, 'arrival', c.arrival, 'options', c.options, 'note', c.note, 'checked_at', c.checked_at)), '[]'::jsonb) into res
  from public.assignment_checks c join public.staff s on s.id = c.staff_id where c.booking_id = p_booking_id;
  return res;
end; $$;
revoke all on function public.admin_booking_checks(uuid) from public, anon;
grant execute on function public.admin_booking_checks(uuid) to authenticated;

-- 관리자: 작가 미확인 예약 (다가오는, 배정됐는데 모든 작가 확인 완료가 아님)
create or replace function public.admin_unconfirmed()
returns jsonb language plpgsql security definer set search_path=public, pg_temp
as $$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'booking_id', b.id, 'contractor_name', b.contractor_name,
    'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time, 'wedding_venue', b.wedding_venue,
    'assignee_id', b.assignee_id, 'sub_assignee_id', b.sub_assignee_id,
    'main_ok', exists(select 1 from public.assignment_checks c where c.booking_id=b.id and c.staff_id=b.assignee_id and c.attend and c.arrival and c.options),
    'sub_ok', (b.sub_assignee_id is null) or exists(select 1 from public.assignment_checks c where c.booking_id=b.id and c.staff_id=b.sub_assignee_id and c.attend and c.arrival and c.options)
  ) order by b.wedding_date, b.wedding_time), '[]'::jsonb) into res
  from public.bookings b
  where b.status <> '취소' and b.deposit_paid and b.assignee_id is not null
    and b.check_sent_at is not null
    and b.wedding_date >= current_date and b.wedding_date <= current_date + 30;
  return res;
end; $$;
revoke all on function public.admin_unconfirmed() from public, anon;

-- 작가 체크 링크 보냄 표시
create or replace function public.admin_mark_check_sent(p_id uuid, p_on boolean)
returns public.bookings language plpgsql security definer set search_path=public, pg_temp
as $$ declare r public.bookings; begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.bookings set check_sent_at = case when coalesce(p_on,true) then now() else null end
   where id = p_id returning * into r;
  return r;
end; $$;
revoke all on function public.admin_mark_check_sent(uuid, boolean) from public, anon;
grant execute on function public.admin_mark_check_sent(uuid, boolean) to authenticated;
grant execute on function public.admin_unconfirmed() to authenticated;

-- 메인/서브 작가 동시 설정 (예약 상세에서)
create or replace function public.admin_set_assignees(p_id uuid, p_main uuid, p_sub uuid)
returns public.bookings language plpgsql security definer set search_path=public, pg_temp
as $$ declare r public.bookings; begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.bookings set assignee_id = p_main, sub_assignee_id = p_sub where id = p_id returning * into r;
  return r;
end; $$;

revoke all on function public.admin_staff_list() from public, anon;
revoke all on function public.admin_staff_add(text, text) from public, anon;
revoke all on function public.admin_staff_update(uuid, text, text, boolean, boolean) from public, anon;
revoke all on function public.admin_staff_delete(uuid) from public, anon;
revoke all on function public.admin_set_deposit(uuid, boolean) from public, anon;
revoke all on function public.admin_set_balance(uuid, boolean) from public, anon;
revoke all on function public.admin_delete_booking(uuid) from public, anon;
revoke all on function public.admin_set_alimtalk(uuid, text, boolean) from public, anon;
revoke all on function public.admin_assign(uuid[], uuid) from public, anon;
revoke all on function public.admin_set_assignees(uuid, uuid, uuid) from public, anon;
grant execute on function public.admin_staff_list() to authenticated;
grant execute on function public.admin_staff_add(text, text) to authenticated;
grant execute on function public.admin_staff_update(uuid, text, text, boolean, boolean) to authenticated;
grant execute on function public.admin_staff_delete(uuid) to authenticated;
grant execute on function public.admin_set_deposit(uuid, boolean) to authenticated;
grant execute on function public.admin_set_balance(uuid, boolean) to authenticated;
grant execute on function public.admin_delete_booking(uuid) to authenticated;
grant execute on function public.admin_set_alimtalk(uuid, text, boolean) to authenticated;
grant execute on function public.admin_assign(uuid[], uuid) to authenticated;
grant execute on function public.admin_set_assignees(uuid, uuid, uuid) to authenticated;

-- ============================================
-- 갤러리 (자체 갤러리: Storage 업로드 + 태그 + 라이트박스)
-- ============================================
create table if not exists public.gallery (
  id          uuid primary key default gen_random_uuid(),
  image_path  text not null,
  image_url   text not null,
  venue       text,
  sort        integer default 0,
  created_at  timestamptz not null default now()
);
create index if not exists gallery_sort_idx on public.gallery (sort, created_at desc);
alter table public.gallery enable row level security;

create or replace function public.gallery_list()
returns setof public.gallery language sql security definer set search_path=public, pg_temp
as $$ select * from public.gallery order by sort asc, created_at desc $$;
revoke all on function public.gallery_list() from public;
grant execute on function public.gallery_list() to anon, authenticated;

create or replace function public.admin_gallery_add(payload jsonb)
returns public.gallery language plpgsql security definer set search_path=public, pg_temp
as $$
declare r public.gallery;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  insert into public.gallery (image_path, image_url, venue, sort)
  values (payload->>'image_path', payload->>'image_url', nullif(payload->>'venue',''), coalesce((payload->>'sort')::int,0))
  returning * into r;
  return r;
end; $$;
revoke all on function public.admin_gallery_add(jsonb) from public, anon;
grant execute on function public.admin_gallery_add(jsonb) to authenticated;

create or replace function public.admin_gallery_delete(p_id uuid)
returns text language plpgsql security definer set search_path=public, pg_temp
as $$
declare pth text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  delete from public.gallery where id = p_id returning image_path into pth;
  return pth;
end; $$;
revoke all on function public.admin_gallery_delete(uuid) from public, anon;
grant execute on function public.admin_gallery_delete(uuid) to authenticated;

-- Storage 버킷 'gallery' (public) + 정책: 공개읽기 / 인증사용자 업로드·삭제
-- insert into storage.buckets (id,name,public) values ('gallery','gallery',true) on conflict (id) do update set public=true;
-- create policy "gallery_public_read" on storage.objects for select using (bucket_id='gallery');
-- create policy "gallery_auth_insert" on storage.objects for insert to authenticated with check (bucket_id='gallery');
-- create policy "gallery_auth_delete" on storage.objects for delete to authenticated using (bucket_id='gallery');
-- 설문 레퍼런스: 익명 업로드 허용 (gallery 버킷의 refs/ 폴더 한정) — 설문 사진을 Storage에 저장(빠른 로딩)
-- create policy "refs_anon_insert" on storage.objects for insert to anon with check (bucket_id='gallery' and name like 'refs/%');

create or replace function public.admin_gallery_update(p_id uuid, p_venue text)
returns public.gallery language plpgsql security definer set search_path=public, pg_temp
as $$
declare r public.gallery;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.gallery set venue = nullif(p_venue,'') where id = p_id returning * into r;
  return r;
end; $$;
revoke all on function public.admin_gallery_update(uuid, text) from public, anon;
grant execute on function public.admin_gallery_update(uuid, text) to authenticated;

-- ============================================
-- 예식 전 설문 (survey)
-- 고객이 카톡 링크(?b=예약ID)로 접속해 작성 → 관리자 예약 상세에서 확인.
-- 레퍼런스 사진은 SECURITY DEFINER 경로 보장을 위해 base64로 DB 저장.
-- ============================================
create table if not exists public.surveys (
  booking_id     uuid primary key references public.bookings(id) on delete cascade,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  agree_check    boolean default false,
  name           text,
  wedding_date   date,
  wedding_venue  text,
  email          text,
  priority       text,                          -- 촬영 우선순위 (단일)
  prop_ring      boolean default false,         -- 반지/청첩장 소품촬영
  bride_room_req text,                           -- 신부대기실 특별요청
  prog_items     jsonb default '[]'::jsonb,      -- 본식 진행항목 (복수)
  bridal_focus   text,                           -- 본식 중 신경쓸 부분
  wonpan_first   boolean default false,          -- 원판 선진행
  wonpan_light   text,                           -- 사용 / 미사용
  extra_req      text,
  etc_req        text
);
alter table public.surveys enable row level security;

create table if not exists public.survey_refs (
  id          uuid primary key default gen_random_uuid(),
  booking_id  uuid not null references public.bookings(id) on delete cascade,
  data_url    text not null,
  sort        integer default 0,
  created_at  timestamptz not null default now()
);
create index if not exists survey_refs_booking_idx on public.survey_refs (booking_id, sort);
alter table public.survey_refs enable row level security;

-- 설문용: 예약 기본정보 조회 (anon) — 프리필/본인확인용, 민감정보 제외
create or replace function public.survey_booking_info(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path=public, pg_temp
as $$
declare b public.bookings; has_s boolean;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found then return null; end if;
  select exists(select 1 from public.surveys where booking_id = p_booking_id) into has_s;
  return jsonb_build_object(
    'contractor_name', b.contractor_name,
    'wedding_date',     b.wedding_date,
    'wedding_venue',    b.wedding_venue,
    'contractor_email', b.contractor_email,
    'already',          has_s
  );
end; $$;
revoke all on function public.survey_booking_info(uuid) from public;
grant execute on function public.survey_booking_info(uuid) to anon, authenticated;

-- 설문 제출 (anon) — booking_id 기준 upsert + 레퍼런스 교체(최대 5장)
create or replace function public.submit_survey(payload jsonb)
returns uuid language plpgsql security definer set search_path=public, pg_temp
as $$
declare bid uuid; el jsonb; i int := 0;
begin
  bid := nullif(payload->>'booking_id','')::uuid;
  if bid is null then raise exception 'booking_id required'; end if;
  if not exists(select 1 from public.bookings where id = bid) then
    raise exception 'booking not found';
  end if;

  insert into public.surveys (
    booking_id, agree_check, name, wedding_date, wedding_venue, email,
    priority, prop_ring, bride_room_req, prog_items, bridal_focus,
    wonpan_first, wonpan_light, extra_req, etc_req, updated_at
  ) values (
    bid,
    coalesce((payload->>'agree_check')::boolean,false),
    nullif(payload->>'name',''),
    nullif(payload->>'wedding_date','')::date,
    nullif(payload->>'wedding_venue',''),
    nullif(payload->>'email',''),
    nullif(payload->>'priority',''),
    coalesce((payload->>'prop_ring')::boolean,false),
    nullif(payload->>'bride_room_req',''),
    coalesce(payload->'prog_items','[]'::jsonb),
    nullif(payload->>'bridal_focus',''),
    coalesce((payload->>'wonpan_first')::boolean,false),
    nullif(payload->>'wonpan_light',''),
    nullif(payload->>'extra_req',''),
    nullif(payload->>'etc_req',''),
    now()
  )
  on conflict (booking_id) do update set
    agree_check=excluded.agree_check, name=excluded.name,
    wedding_date=excluded.wedding_date, wedding_venue=excluded.wedding_venue,
    email=excluded.email, priority=excluded.priority, prop_ring=excluded.prop_ring,
    bride_room_req=excluded.bride_room_req, prog_items=excluded.prog_items,
    bridal_focus=excluded.bridal_focus, wonpan_first=excluded.wonpan_first,
    wonpan_light=excluded.wonpan_light, extra_req=excluded.extra_req,
    etc_req=excluded.etc_req, updated_at=now();

  -- 레퍼런스 교체
  delete from public.survey_refs where booking_id = bid;
  if jsonb_typeof(payload->'refs') = 'array' then
    for el in select * from jsonb_array_elements(payload->'refs') loop
      exit when i >= 5;
      if jsonb_typeof(el) = 'string' and length(el #>> '{}') > 0 then
        insert into public.survey_refs (booking_id, data_url, sort)
        values (bid, el #>> '{}', i);
        i := i + 1;
      end if;
    end loop;
  end if;

  return bid;
end; $$;
revoke all on function public.submit_survey(jsonb) from public;
grant execute on function public.submit_survey(jsonb) to anon, authenticated;

-- 관리자: 특정 예약의 설문 + 레퍼런스 조회
create or replace function public.admin_survey_get(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path=public, pg_temp
as $$
declare s public.surveys; refs jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select * into s from public.surveys where booking_id = p_booking_id;
  if not found then return null; end if;
  select coalesce(jsonb_agg(data_url order by sort), '[]'::jsonb) into refs
    from public.survey_refs where booking_id = p_booking_id;
  return to_jsonb(s) || jsonb_build_object('refs', refs);
end; $$;
revoke all on function public.admin_survey_get(uuid) from public, anon;
grant execute on function public.admin_survey_get(uuid) to authenticated;

-- 관리자: 설문이 제출된 예약 ID 목록 (목록에 배지 표시용)
create or replace function public.admin_survey_ids()
returns jsonb language plpgsql security definer set search_path=public, pg_temp
as $$
declare ids jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(booking_id), '[]'::jsonb) into ids from public.surveys;
  return ids;
end; $$;
revoke all on function public.admin_survey_ids() from public, anon;
grant execute on function public.admin_survey_ids() to authenticated;

-- 작가 공유용: 예약ID(토큰)로 설문 + 촬영 핵심정보 읽기 (anon, 연락처/이메일 제외)
create or replace function public.survey_view(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path=public, pg_temp
as $$
declare b public.bookings; s public.surveys; refs jsonb;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found then return null; end if;
  select * into s from public.surveys where booking_id = p_booking_id;
  if not found then
    return jsonb_build_object(
      'has_survey', false,
      'contractor_name', b.contractor_name,
      'bride_name', b.bride_name, 'bride_phone', b.bride_phone,
      'groom_name', b.groom_name, 'groom_phone', b.groom_phone,
      'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time, 'wedding_venue', b.wedding_venue,
      'option_reception', b.option_reception, 'option_pyebaek', b.option_pyebaek,
      'option_part2', b.option_part2, 'option_album', b.option_album,
      'travel_fee', b.travel_fee, 'photographer', b.photographer);
  end if;
  select coalesce(jsonb_agg(data_url order by sort), '[]'::jsonb) into refs
    from public.survey_refs where booking_id = p_booking_id;
  return jsonb_build_object(
    'has_survey', true,
    'contractor_name', b.contractor_name,
    'bride_name', b.bride_name, 'bride_phone', b.bride_phone,
    'groom_name', b.groom_name, 'groom_phone', b.groom_phone,
    'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time, 'wedding_venue', b.wedding_venue,
    'option_reception', b.option_reception, 'option_pyebaek', b.option_pyebaek,
    'option_part2', b.option_part2, 'option_album', b.option_album,
    'travel_fee', b.travel_fee, 'photographer', b.photographer,
    'priority', s.priority, 'prop_ring', s.prop_ring, 'bride_room_req', s.bride_room_req,
    'prog_items', s.prog_items, 'bridal_focus', s.bridal_focus,
    'wonpan_first', s.wonpan_first, 'wonpan_light', s.wonpan_light,
    'extra_req', s.extra_req, 'etc_req', s.etc_req,
    'updated_at', s.updated_at, 'refs', refs);
end; $$;
revoke all on function public.survey_view(uuid) from public;
grant execute on function public.survey_view(uuid) to anon, authenticated;
