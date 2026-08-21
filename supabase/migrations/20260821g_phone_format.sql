-- 전화번호에 하이픈이 자동으로 들어가게. (대표 요청)
--
-- 작가 한 명(장길희)이 01071334012 처럼 하이픈 없이 저장돼 있었다. 지금은 문제가 없지만
-- 작가 자동 카톡이 나가기 시작하면 이런 게 조용히 어긋날 자리가 된다.
-- 화면에서 고쳐 넣게 하는 것보다, 들어올 때 한 번 다듬는 쪽이 확실하다.
-- 관리자 화면·손님 폼·SQL 어디로 들어와도 같은 모양이 된다.
--
-- 모르는 모양(국제번호, 자릿수가 안 맞는 것)은 손대지 않는다.
-- 실제로 groom_phone 에 017657758751(12자리) 짜리가 하나 있는데, 그건 오타로 보이고
-- 규칙으로 고칠 수 없다. 함부로 자르지 않고 그대로 둔다.

create or replace function private.fmt_phone(p text)
returns text language sql immutable as $fn$
  select case
    when p is null or btrim(p) = '' then p
    -- 휴대폰
    when d ~ '^01[016789][0-9]{7}$' then substr(d,1,3) || '-' || substr(d,4,3) || '-' || substr(d,7,4)
    when d ~ '^01[016789][0-9]{8}$' then substr(d,1,3) || '-' || substr(d,4,4) || '-' || substr(d,8,4)
    -- 서울
    when d ~ '^02[0-9]{7}$' then '02-' || substr(d,3,3) || '-' || substr(d,6,4)
    when d ~ '^02[0-9]{8}$' then '02-' || substr(d,3,4) || '-' || substr(d,7,4)
    -- 그 밖의 지역번호
    when d ~ '^0[3-6][0-9]{8}$' then substr(d,1,3) || '-' || substr(d,4,3) || '-' || substr(d,7,4)
    when d ~ '^0[3-6][0-9]{9}$' then substr(d,1,3) || '-' || substr(d,4,4) || '-' || substr(d,8,4)
    -- 1588 같은 대표번호
    when d ~ '^1[0-9]{7}$' then substr(d,1,4) || '-' || substr(d,5,4)
    else p                                   -- 모르는 모양은 그대로
  end
  from (select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') d) x;
$fn$;

create or replace function private.tg_fmt_phone()
returns trigger language plpgsql security definer set search_path = private, public, pg_temp as $fn$
begin
  if tg_table_name = 'staff' then
    new.phone := private.fmt_phone(new.phone);
  else
    new.contractor_phone := private.fmt_phone(new.contractor_phone);
    new.groom_phone      := private.fmt_phone(new.groom_phone);
    new.bride_phone      := private.fmt_phone(new.bride_phone);
  end if;
  return new;
end$fn$;
revoke all on function private.tg_fmt_phone() from public, anon, authenticated;

-- 이름을 'a_' 로 시작하게 둔다 — 같은 BEFORE 트리거는 이름순으로 돌아서,
-- 다른 트리거가 번호를 보기 전에 모양이 정리되어 있게 된다.
drop trigger if exists a_fmt_phone on public.staff;
create trigger a_fmt_phone before insert or update on public.staff
  for each row execute function private.tg_fmt_phone();

drop trigger if exists a_fmt_phone on public.bookings;
create trigger a_fmt_phone before insert or update on public.bookings
  for each row execute function private.tg_fmt_phone();

-- 이미 들어 있는 것도 한 번 정리
update public.staff    set phone = private.fmt_phone(phone)
 where phone is distinct from private.fmt_phone(phone);
update public.bookings set contractor_phone = private.fmt_phone(contractor_phone),
                           groom_phone      = private.fmt_phone(groom_phone),
                           bride_phone      = private.fmt_phone(bride_phone)
 where contractor_phone is distinct from private.fmt_phone(contractor_phone)
    or groom_phone      is distinct from private.fmt_phone(groom_phone)
    or bride_phone      is distinct from private.fmt_phone(bride_phone);
