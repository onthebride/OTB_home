-- 「알림」 목록을 한 쪽에 다섯 줄로 (대표 요청 2026-08-28
-- «캘린더 알림은 목록 5개이상 페이지네이션»).
-- 전에는 열 줄이었다 — 폰에서 한 화면을 넘겨 스크롤이 길었다.
--
-- 칸(인자)은 그대로라 `create or replace` 로 몸통만 바꾼다.
-- 화면(staff-calendar.js)은 서버가 준 per/pages/total 을 그대로 쓰므로 손댈 것이 없다.

create or replace function public.staff_notices(p_staff_id uuid, p_page int default 1)
returns jsonb language plpgsql stable security definer set search_path=public, pg_temp as $$
declare rows_ jsonb; per int := 5; pg int; tot int;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and coalesce(active,false)) then
    raise exception 'staff not found';
  end if;

  select count(*)::int into tot from public.staff_notice where staff_id = p_staff_id;
  -- 쪽 번호는 서버가 바로잡는다. 0쪽이나 없는 쪽을 달라고 해도 빈 화면을 주면 안 된다
  pg := greatest(1, least(coalesce(p_page, 1), greatest(1, (tot + per - 1) / per)));

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'title', title, 'body', body,
    'at', to_char(created_at at time zone 'Asia/Seoul', 'MM/DD HH24:MI'),
    'unread', read_at is null) order by created_at desc, id desc), '[]'::jsonb) into rows_
  from (
    select * from public.staff_notice
    where staff_id = p_staff_id
    -- ⚠ 한 트랜잭션 안에서 여러 건이 생기면 now() 가 같다(거래 시각 고정).
    --   id 로 한 번 더 갈라야 쪽을 넘길 때 같은 줄이 두 번 나오지 않는다
    order by created_at desc, id desc
    limit per offset (pg - 1) * per
  ) t;

  return jsonb_build_object(
    'rows', rows_,
    'page', pg,
    'per', per,
    'total', tot,
    'pages', greatest(1, (tot + per - 1) / per),
    'unread', (select count(*)::int from public.staff_notice
               where staff_id = p_staff_id and read_at is null));
end$$;
revoke all on function public.staff_notices(uuid, int) from public;
grant execute on function public.staff_notices(uuid, int) to anon, authenticated;
