-- 「지난 소식」을 한 쪽에 일곱 줄씩 (대표 2026-08-31)
--   «작가 캘린더 확인 5개는 넘 적네 7개 하자»
--
-- ⚠ 줄 수는 **여기 한 곳에서만** 정한다. 화면에 또 박아두면 서버가 일곱을 주는데
--   화면은 다섯으로 알고 쪽 수를 잘못 세게 된다. staff_notices 가 per 를 같이 돌려주고
--   화면은 그걸 받아 쓴다.

create or replace function public.staff_notices(
  p_staff_id uuid, p_page integer default 1, p_read_only boolean default false)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp' as $$
declare rows_ jsonb; per int := 7; pg int; tot int; ro boolean := coalesce(p_read_only, false);
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
