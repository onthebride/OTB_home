-- 작가 캘린더에 「확인할 것」 (대표 요청 2026-08-27
-- «알림이 안갈수도 있으니까 노티를 해줬으면 하는데 확인할거 따로 모아서»)
--
-- 폰 알림은 못 갈 수 있다 — 알림을 안 켰거나, 껐거나, 등록이 죽었거나, 폰이 꺼져 있었거나.
-- 그래서 **보낸 것을 남겨두고** 작가가 캘린더를 열면 그 자리에서 보이게 한다.
-- 알림이 갔든 안 갔든 캘린더만 열면 놓치지 않는다.
--
-- ⚠ 폰 알림과 **같은 자리에서** 만든다. 따로 만들면 한쪽만 나가는 날이 온다.

create table if not exists public.staff_notice (
  id         bigserial primary key,
  staff_id   uuid not null references public.staff(id) on delete cascade,
  booking_id uuid references public.bookings(id) on delete cascade,
  kind       text not null,                 -- 'change' | 'cancel'
  title      text not null,
  body       text not null,
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists staff_notice_who on public.staff_notice(staff_id, read_at, created_at desc);
alter table public.staff_notice enable row level security;
revoke all on table public.staff_notice from anon, authenticated;
revoke all on sequence public.staff_notice_id_seq from anon, authenticated;

-- 예식이 바뀌면 폰으로도 보내고, 여기에도 남긴다.
-- (몸통은 20260827a 와 같고 «남기는 줄» 하나가 늘었다)
create or replace function private.booking_change_notify()
returns trigger language plpgsql security definer
set search_path to 'private', 'public', 'pg_temp'
as $$
declare
  changed text[] := '{}';
  msg text; who uuid; nm text; ttl text;
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

  ttl := case when new.status = '취소' then '❌ 예식이 취소되었습니다'
              else '📅 예식 일정이 바뀌었습니다' end;

  foreach who in array targets loop
    select name into nm from public.staff where id = who and coalesce(active, false);
    if nm is null then continue; end if;
    msg := private.wedding_line(case when new.status = '취소' then old else new end)
           || E'\n' || array_to_string(changed, E'\n');

    -- ① 캘린더에 남긴다 — 폰 알림이 못 가도 이건 남는다
    insert into public.staff_notice(staff_id, booking_id, kind, title, body)
    values (who, new.id, case when new.status = '취소' then 'cancel' else 'change' end, ttl, msg);

    -- ② 폰으로도 보낸다
    perform private.otb_push(ttl, msg, '/staff-calendar?s=' || who::text, who);
  end loop;

  return new;
end$$;

/* ===== 작가가 보는 「확인할 것」 =====
   작가는 로그인이 없다. 캘린더와 같이 **링크(작가ID)를 아는 사람을 본인으로 본다.** */
drop function if exists public.staff_notices(uuid);
create or replace function public.staff_notices(p_staff_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public, pg_temp as $$
declare rows_ jsonb;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and coalesce(active,false)) then
    raise exception 'staff not found';
  end if;

  -- 안 읽은 것 + 최근 읽은 것 몇 개. 오래된 것까지 다 보여줄 자리가 아니다
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'title', title, 'body', body,
    'at', to_char(created_at at time zone 'Asia/Seoul', 'MM/DD HH24:MI'),
    -- ⚠ 한 트랜잭션 안에서 여러 건이 생기면 now() 가 같다(거래 시각 고정).
    --   id 로 한 번 더 갈라야 차례가 흔들리지 않는다
    'unread', read_at is null) order by created_at desc, id desc), '[]'::jsonb) into rows_
  from (
    select * from public.staff_notice
    where staff_id = p_staff_id
      and (read_at is null or created_at > now() - interval '14 days')
    order by created_at desc, id desc limit 30
  ) t;

  return jsonb_build_object(
    'rows', rows_,
    'unread', (select count(*)::int from public.staff_notice
               where staff_id = p_staff_id and read_at is null));
end$$;
revoke all on function public.staff_notices(uuid) from public;
grant execute on function public.staff_notices(uuid) to anon, authenticated;

-- 확인 표시. p_id 를 주면 그것만, 안 주면 전부
drop function if exists public.staff_notice_read(uuid, bigint);
create or replace function public.staff_notice_read(p_staff_id uuid, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
begin
  if not exists (select 1 from public.staff where id = p_staff_id and coalesce(active,false)) then
    raise exception 'staff not found';
  end if;
  -- ⚠ staff_id 를 반드시 함께 건다 — 안 걸면 번호만 알면 남의 것을 읽음 처리할 수 있다
  update public.staff_notice set read_at = now()
   where staff_id = p_staff_id and read_at is null
     and (p_id is null or id = p_id);
  return public.staff_notices(p_staff_id);
end$$;
revoke all on function public.staff_notice_read(uuid, bigint) from public;
grant execute on function public.staff_notice_read(uuid, bigint) to anon, authenticated;
