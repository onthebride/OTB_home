/* 작가 캘린더 → 작가가 쓰는 캘린더(아이폰·구글·네이버) 구독 주소 — 대표 2026-10-28
   「우리 작가 캘린더에 구글캘린더나 네이버 캘린더 연동되게 하면 좋을거 같아」 → «1번 해볼까?»
   (1번 = 우리 → 작가 쪽 한 방향. 작가 캘린더에서 지우거나 옮겨도 우리 배정은 그대로다)

   ⚠ 구독 주소에는 작가 번호(?s=)를 쓰지 않는다. 따로 만든 열쇠를 쓴다.
     구독 주소는 구글·네이버·애플 서버에 맡겨지는 것이라 새어도 작가 캘린더 전체가 열리면 안 된다.
   ⚠ 일정에는 신랑신부 이름·연락처를 싣지 않는다 (대표께 말씀드린 대로 — 이름은 보여드린 뒤 정하신다).
     날짜·시각·예식장·메인/서브·옵션·함께 가는 작가 이름까지만.
   ⚠ 받아 가는 쪽(구글·애플·네이버·그 밖)마다 처음·마지막으로 받아 간 때를 적는다 —
     작가님들이 실제로 넣으셨는지 셀 길이다. 고객 자료는 없다 */

create table if not exists private.staff_cal_feed (
  staff_id   uuid primary key references public.staff(id) on delete cascade,
  token      text not null unique check (token ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now()
);
revoke all on table private.staff_cal_feed from public, anon, authenticated;

create table if not exists private.staff_cal_fetch (
  staff_id uuid not null references public.staff(id) on delete cascade,
  client   text not null check (client in ('google', 'apple', 'naver', 'other')),
  first_at timestamptz not null default now(),
  last_at  timestamptz not null default now(),
  n        int not null default 1,
  last_ua  text,                    -- 받아 간 쪽이 스스로 밝힌 이름 (네이버가 뭐라고 오는지 아직 모른다)
  primary key (staff_id, client)
);
revoke all on table private.staff_cal_fetch from public, anon, authenticated;

/* 작가 캘린더가 부른다 — 「내 폰 캘린더에 넣기」를 누를 때. 없으면 만들고, 있으면 그대로 준다.
   작가 번호를 아는 사람만 부를 수 있다 (staff_calendar 와 같은 문) */
create or replace function public.staff_cal_link(p_staff_id uuid)
returns text language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare tok text;
begin
  if p_staff_id is null or not exists (select 1 from public.staff where id = p_staff_id) then
    return null;
  end if;
  select f.token into tok from private.staff_cal_feed f where f.staff_id = p_staff_id;
  if tok is null then
    insert into private.staff_cal_feed (staff_id, token)
    values (p_staff_id, replace(gen_random_uuid()::text, '-', ''))
    on conflict (staff_id) do nothing;
    select f.token into tok from private.staff_cal_feed f where f.staff_id = p_staff_id;
  end if;
  return tok;
end$$;
revoke all on function public.staff_cal_link(uuid) from public;
grant execute on function public.staff_cal_link(uuid) to anon, authenticated;

/* 구독 주소(/cal/<열쇠>.ics)를 받는 서버가 부른다. 열쇠가 틀리면 null — 서버는 404 를 낸다.
   ⚠ 취소된 예식은 아예 안 싣는다 — 빠지면 받아 간 캘린더에서도 지워진다.
   ⚠ 지난 예식은 60일까지만 (오래된 것까지 실으면 파일만 커진다) */
drop function if exists public.staff_cal_feed(text, text);
drop function if exists public.staff_cal_feed(text, text, text);
create or replace function public.staff_cal_feed(p_token text, p_client text default 'other', p_ua text default null)
returns jsonb language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  sid uuid;
  today date := (now() at time zone 'Asia/Seoul')::date;
  cl text;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{32}$' then return null; end if;
  select f.staff_id into sid from private.staff_cal_feed f where f.token = p_token;
  if sid is null then return null; end if;

  cl := case when p_client in ('google', 'apple', 'naver') then p_client else 'other' end;
  insert into private.staff_cal_fetch as x (staff_id, client, last_ua) values (sid, cl, left(p_ua, 200))
  on conflict (staff_id, client) do update set last_at = now(), n = x.n + 1, last_ua = left(p_ua, 200);

  return jsonb_build_object('events', coalesce((
    select jsonb_agg(jsonb_build_object(
             /* 일정 번호 — 예약 번호를 그대로 쓰지 않는다. 예약 번호는 신부님 포털 열쇠다.
                구독한 일정은 구글·애플·네이버 서버에 남으므로 거기 열쇠가 남으면 안 된다.
                늘 같은 값이라야 시각이 바뀐 일정이 새 일정이 아니라 같은 일정으로 잡힌다 */
             'id', md5('otb-cal:' || b.id::text),
             'date', b.wedding_date,
             'time', b.wedding_time,
             'venue', b.wedding_venue,
             'role', case when b.assignee_id = sid then '메인' else '서브' end,
             'reception', coalesce(b.option_reception, false),
             'pyebaek', coalesce(b.option_pyebaek, false),
             'part2', coalesce(b.option_part2, false),
             'two', coalesce(b.photographer = '2인 촬영', false),
             'pick', coalesce(b.pick_pin = sid, false),
             'rep', coalesce(b.rep_designation, false),
             'peer_role', pr.peer->>'peer_role',
             'peer_name', pr.peer->>'peer_name')
           order by b.wedding_date, b.wedding_time)
    from public.bookings b
    cross join lateral (select private.peer_of(b, sid) as peer) pr
    where (b.assignee_id = sid or b.sub_assignee_id = sid)
      and b.status <> '취소'
      and b.wedding_date >= today - 60), '[]'::jsonb));
end$$;
revoke all on function public.staff_cal_feed(text, text, text) from public;
grant execute on function public.staff_cal_feed(text, text, text) to anon, authenticated;
