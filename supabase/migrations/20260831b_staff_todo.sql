-- 작가 캘린더 「확인」 칸 — 확인해야 할 것을 한 곳에 모은다 (대표 2026-08-31)
--
--   «월요일 체크나 금요일 설문체크도 캘린더 기반으로 하고 싶어 / 알림톡은 가지만 캘린더로
--     가서 확인하고 체크 할 수 있게 / 알림도 좋지만 그것보다 필수확인 해서 확인할 내용
--     숫자 뱃지뜨고 들어가면 확인누를 수 있게 / 스케줄 변경, 배정, 취소, 월요일체크,
--     예식전 체크및 설문 확인 같은거»
--   «알림은 확인으로 바꾸고 확인할게 있으면 캘린더 상단에 확인할 사항이 있습니다. 라고
--     안내박스가 가는거야 그리고 확인 글자에 숫자뱃지»
--   «캘린더 안에서 모든걸 쓸 수 있게 해줘 그래서 알림톡도 캘린더로 가게 하는거여»
--
-- 지금은 확인할 일이 세 군데 흩어져 있다.
--   ① 캘린더 알림함        — 변경·취소·공지
--   ② /staff-schedule 페이지 — 월요일 체크 (참석·도착·옵션)
--   ③ /survey-view 페이지    — 예식 전 신부 설문 확인
-- 이 셋을 한 함수가 모아서 준다. 화면은 이것만 보고 그린다.
--
-- ⚠ 숫자 뱃지가 세는 것이 곧 이 목록이다. 두 곳에서 따로 세면 «뱃지는 3인데 안에는 2개»
--   가 된다. 그래서 세는 것도 여기서 같이 준다 (n).

drop function if exists public.staff_todo(uuid);
create or replace function public.staff_todo(p_staff_id uuid)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp' as $$
declare today date := (now() at time zone 'Asia/Seoul')::date; items jsonb;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and coalesce(active,false)) then
    raise exception 'staff not found';
  end if;

  /* ⚠ 예식 한 줄(private.wedding_line)은 **여기서** 만든다. 아래에서 m.*::bookings 로
       되돌리려 하면 «cannot cast type record to bookings» 로 터진다 — is_main 을 하나
       더 붙이는 순간 그 줄은 더 이상 bookings 가 아니다 */
  with mine as (
    select b.id, b.wedding_date, b.check_sent_at, b.sub_check_sent_at, b.alimtalk_sent,
           (b.assignee_id = p_staff_id) as is_main,
           private.wedding_line(b) as line
    from public.bookings b
    where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
      and b.status <> '취소' and b.wedding_date >= today
  ),
  /* ① 월요일 체크 — 참석·도착·옵션.
     ⚠ 「보낸 것」만 센다. 안 보낸 예식까지 세면 다음 달 것이 전부 할 일로 뜬다
       (월요일 톡이 나가면 그 주 예식에 도장이 찍힌다 — 20260831a) */
  chk as (
    select 'check'::text as kind, m.id as booking_id, null::bigint as notice_id,
           m.wedding_date as day, 0 as pri,
           '예식 확인이 필요해요' as title,
           m.line as body,
           (case when m.is_main then '메인' else '서브' end) as role,
           null::text as at
    from mine m
    where (case when m.is_main then m.check_sent_at else m.sub_check_sent_at end) is not null
      and not public.check_done(m.id, p_staff_id)
  ),
  /* ② 예식 전 신부 설문 확인 — 설문 톡(T)을 받은 사람만.
     설문이 실제로 들어온 예식만 (안 들어왔으면 볼 것이 없다) */
  sv as (
    select 'survey'::text, m.id, null::bigint,
           m.wedding_date, 1,
           '신부님 설문을 확인해 주세요',
           m.line,
           (case when m.is_main then '메인' else '서브' end),
           null::text
    from mine m
    where (coalesce(m.alimtalk_sent, '{}'::jsonb) -> ('T:' || p_staff_id::text)) is not null
      and exists (select 1 from public.surveys s where s.booking_id = m.id)
      and not exists (select 1 from public.assignment_checks c
                       where c.booking_id = m.id and c.staff_id = p_staff_id
                         and c.survey_ack_at is not null)
  ),
  /* ③ 안 읽은 알림 — 배정·변경·취소·공지·자동멈춤이 다 여기로 온다.
     읽은 것은 「지난 소식」으로 내려간다 (staff_notices 가 준다) */
  nt as (
    select 'notice'::text, n.booking_id, n.id,
           null::date, 2,
           n.title, n.body, null::text,
           to_char(n.created_at at time zone 'Asia/Seoul', 'MM/DD HH24:MI')
    from public.staff_notice n
    where n.staff_id = p_staff_id and n.read_at is null
  ),
  all_ as (select * from chk union all select * from sv union all select * from nt)
  select coalesce(jsonb_agg(jsonb_build_object(
           'kind', kind, 'booking_id', booking_id, 'notice_id', notice_id,
           'day', day, 'title', title, 'body', body, 'role', role, 'at', at)
         -- 예식이 가까운 것부터. 날짜가 없는 알림은 뒤로 보내고 최근 것부터
         order by pri, day nulls last, notice_id desc nulls last), '[]'::jsonb)
    into items from all_;

  return jsonb_build_object('n', jsonb_array_length(items), 'items', items);
end$$;
revoke all on function public.staff_todo(uuid) from public;
grant execute on function public.staff_todo(uuid) to anon, authenticated;

/* ===== 「지난 소식」은 읽은 것만 =====
   안 읽은 것은 위 staff_todo 가 「확인이 필요해요」로 들고 있다.
   두 곳에 같은 줄이 뜨면 «아까 확인했는데 왜 또 있지» 가 된다.
   ⚠ 칸을 더하므로 drop 을 같이 쓴다 — 안 그러면 이름이 같은 함수가 둘이 된다 */
drop function if exists public.staff_notices(uuid, integer);
drop function if exists public.staff_notices(uuid, integer, boolean);
create or replace function public.staff_notices(
  p_staff_id uuid, p_page integer default 1, p_read_only boolean default false)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp' as $$
declare rows_ jsonb; per int := 5; pg int; tot int; ro boolean := coalesce(p_read_only, false);
begin
  if not exists (select 1 from public.staff where id = p_staff_id and coalesce(active,false)) then
    raise exception 'staff not found';
  end if;

  select count(*)::int into tot from public.staff_notice
   where staff_id = p_staff_id and (not ro or read_at is not null);
  -- 쪽 번호는 서버가 바로잡는다. 0쪽이나 없는 쪽을 달라고 해도 빈 화면을 주면 안 된다
  pg := greatest(1, least(coalesce(p_page, 1), greatest(1, (tot + per - 1) / per)));

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'title', title, 'body', body,
    'at', to_char(created_at at time zone 'Asia/Seoul', 'MM/DD HH24:MI'),
    'unread', read_at is null) order by created_at desc, id desc), '[]'::jsonb) into rows_
  from (
    select * from public.staff_notice
    where staff_id = p_staff_id and (not ro or read_at is not null)
    -- ⚠ 한 트랜잭션 안에서 여러 건이 생기면 now() 가 같다(거래 시각 고정).
    --   id 로 한 번 더 갈라야 쪽을 넘길 때 같은 줄이 두 번 나오지 않는다
    order by created_at desc, id desc
    limit per offset (pg - 1) * per
  ) t;

  return jsonb_build_object(
    'rows', rows_, 'page', pg, 'per', per, 'total', tot,
    'pages', greatest(1, (tot + per - 1) / per),
    'unread', (select count(*)::int from public.staff_notice
               where staff_id = p_staff_id and read_at is null));
end$$;
revoke all on function public.staff_notices(uuid, integer, boolean) from public;
grant execute on function public.staff_notices(uuid, integer, boolean) to anon, authenticated;
