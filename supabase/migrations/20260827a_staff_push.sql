-- 작가에게도 폰 알림을 보낸다. 대표 요청 2026-08-27:
--   「작가들 캘린더로 홈추가해서 알림가게 할 수 있지?
--    스케줄 장소나 시간 변동이나 취소있으면 알람 가게」
--
-- 지금 푸시는 **대표 폰 전용**이다. push_subscriptions 에 누구 것인지 구분이 없고,
-- 엣지 함수(otb-push)가 등록된 것 전부에 보낸다. 작가 것을 그냥 넣으면
-- 대표에게 가는 알림이 작가에게도 다 간다 — 절대 안 된다.
--
-- 그래서 «누구 것인지» 를 붙인다. staff_id 가 비어 있으면 대표(관리자) 것이다.
-- 엣지 함수도 staff_id 로 걸러 보내게 고쳐야 한다 (supabase/functions/otb-push/index.ts).

alter table public.push_subscriptions add column if not exists staff_id uuid;
do $$ begin
  alter table public.push_subscriptions add constraint push_subscriptions_staff_id_fkey
    foreign key (staff_id) references public.staff(id) on delete cascade;
exception when duplicate_object then null; end $$;
create index if not exists push_subs_staff_idx on public.push_subscriptions (staff_id);

comment on column public.push_subscriptions.staff_id is
  '이 구독이 누구 폰인지. 비어 있으면 대표(관리자) 것';


-- ===== 구독 등록 =====
-- 작가는 로그인이 없다. 캘린더와 같이 «링크(작가ID)를 아는 사람» 을 본인으로 본다.
-- 관리자는 예전처럼 로그인이 있어야 한다
create or replace function public.save_push_subscription(
  p_endpoint text, p_p256dh text, p_auth text, p_staff_id uuid default null)
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if p_endpoint is null or p_p256dh is null or p_auth is null then raise exception 'bad subscription'; end if;
  if p_staff_id is null then
    -- 관리자 것
    if auth.uid() is null then raise exception 'unauthorized'; end if;
  else
    -- 작가 것 — 있는 작가인지만 본다 (작가 캘린더와 같은 잣대)
    if not exists (select 1 from public.staff where id = p_staff_id and coalesce(active, false)) then
      raise exception 'staff not found';
    end if;
  end if;
  insert into public.push_subscriptions (endpoint, p256dh, auth, staff_id)
    values (p_endpoint, p_p256dh, p_auth, p_staff_id)
  on conflict (endpoint) do update
    set p256dh = excluded.p256dh, auth = excluded.auth, staff_id = excluded.staff_id;
end$$;

grant execute on function public.save_push_subscription(text, text, text, uuid) to anon, authenticated;

-- 알림 끄기 — 작가가 끄고 싶을 때
create or replace function public.drop_push_subscription(p_endpoint text)
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  delete from public.push_subscriptions where endpoint = p_endpoint;
end$$;
grant execute on function public.drop_push_subscription(text) to anon, authenticated;


-- ===== 보내기 =====
-- p_staff_id 를 주면 그 작가 폰에만, 안 주면 예전처럼 대표에게만 간다.
-- 엣지 함수가 이 값을 보고 걸러야 한다 — 안 고치면 작가 알림이 대표에게도 간다.
--
-- ⚠ 옛 세 칸짜리를 반드시 지운다. 그냥 두면 넉 칸짜리와 나란히 살아남아
-- 세 칸으로 부르는 곳(설문·알림톡 등)이 «어느 쪽인지 모르겠다» 로 통째로 터진다.
-- create or replace 는 칸 수가 다르면 새 함수를 만드는 것이라 옛것이 안 지워진다
drop function if exists private.otb_push(text, text, text);

create or replace function private.otb_push(
  p_title text, p_body text, p_url text default '/admin', p_staff_id uuid default null)
returns bigint language plpgsql security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $$
declare sec text; url text; req bigint;
begin
  select val into sec from private.solapi where key = 'push_secret';
  select val into url from private.solapi where key = 'push_url';
  if sec is null or url is null then return null; end if;
  select net.http_post(
    url := url,
    body := jsonb_build_object(
      'title', p_title, 'body', coalesce(p_body, ''),
      'url', coalesce(p_url, '/admin'), 'tag', 'otb',
      -- 비어 있으면 대표에게. 있으면 그 작가에게만
      'staff_id', p_staff_id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', sec)
  ) into req;
  return req;
exception when others then return null;   -- 푸시 실패는 무시(호출측 보호)
end$$;


-- ===== 예약이 바뀌면 그 작가에게 알린다 =====
-- 대표가 말한 것: 장소·시간 변동, 취소.
-- 날짜도 같이 본다 (같은 갈래이고 제일 큰 변동이다).
-- 배정이 바뀌는 것도 알린다 — 새로 맡거나 빠지는 건 본인이 제일 먼저 알아야 한다
create or replace function private.booking_change_notify()
returns trigger language plpgsql security definer
set search_path to 'private', 'public', 'pg_temp'
as $$
declare
  changed text[] := '{}';
  msg text; who uuid; nm text;
  targets uuid[];
begin
  -- 지난 예식은 알릴 것이 없다
  if coalesce(new.wedding_date, old.wedding_date) < (now() at time zone 'Asia/Seoul')::date then
    return new;
  end if;

  if new.status = '취소' and old.status is distinct from '취소' then
    changed := changed || '취소되었습니다'::text;
  else
    if new.wedding_date is distinct from old.wedding_date then
      changed := changed || ('날짜 ' || to_char(old.wedding_date, 'MM/DD') || ' → '
                             || to_char(new.wedding_date, 'MM/DD'))::text;
    end if;
    if new.wedding_time is distinct from old.wedding_time then
      changed := changed || ('시간 ' || coalesce(public.fmt_ktime(old.wedding_time), '-') || ' → '
                             || coalesce(public.fmt_ktime(new.wedding_time), '-'))::text;
    end if;
    if coalesce(nullif(trim(new.wedding_venue), ''), '') is distinct from coalesce(nullif(trim(old.wedding_venue), ''), '') then
      changed := changed || ('장소 ' || coalesce(old.wedding_venue, '-') || ' → '
                             || coalesce(new.wedding_venue, '-'))::text;
    end if;
  end if;

  if array_length(changed, 1) is null then return new; end if;

  -- 바뀌기 전·후에 걸쳐 있는 작가 모두에게 (배정이 함께 바뀌었을 수도 있다)
  targets := array(select distinct x from unnest(array[
    old.assignee_id, old.sub_assignee_id, new.assignee_id, new.sub_assignee_id]) x
    where x is not null);

  foreach who in array targets loop
    select name into nm from public.staff where id = who and coalesce(active, false);
    if nm is null then continue; end if;
    msg := private.wedding_line(case when new.status = '취소' then old else new end)
           || E'\n' || array_to_string(changed, E'\n');
    perform private.otb_push(
      case when new.status = '취소' then '❌ 예식이 취소되었습니다' else '📅 예식 일정이 바뀌었습니다' end,
      msg, '/staff-calendar?s=' || who::text, who);
  end loop;
  return new;
end$$;

drop trigger if exists trg_booking_change_notify on public.bookings;
create trigger trg_booking_change_notify
  after update on public.bookings
  for each row execute function private.booking_change_notify();
