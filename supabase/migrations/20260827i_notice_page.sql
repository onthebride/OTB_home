-- 「알림」을 칸으로 빼면서 내역까지 보게 한다 (대표 요청 2026-08-27
-- «알림 탭이 따로 있었음 좋겠어 / 내역도 볼 수 있고 / 확인안한건 진하게 /
--   확인누른건 보통으로 / 10개정도만 해서 페이지 네이션»)
--
-- 전에는 「안 읽은 것 + 최근 2주」만 냈다. 이제 지난 것도 다 보므로 쪽으로 나눠 낸다.
-- ⚠ 칸(인자) 수가 달라졌다. `create or replace` 는 옛 갈래를 안 지운다 —
--   남겨두면 «어느 쪽인지 모르겠다» 로 터진다. 반드시 먼저 지운다.

drop function if exists public.staff_notices(uuid);
drop function if exists public.staff_notices(uuid, int);

create or replace function public.staff_notices(p_staff_id uuid, p_page int default 1)
returns jsonb language plpgsql stable security definer set search_path=public, pg_temp as $$
declare rows_ jsonb; per int := 10; pg int; tot int;
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

-- 확인 표시 — 처리한 뒤 보던 쪽을 그대로 돌려준다
drop function if exists public.staff_notice_read(uuid, bigint);
drop function if exists public.staff_notice_read(uuid, bigint, int);
create or replace function public.staff_notice_read(p_staff_id uuid, p_id bigint default null,
                                                    p_page int default 1)
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
begin
  if not exists (select 1 from public.staff where id = p_staff_id and coalesce(active,false)) then
    raise exception 'staff not found';
  end if;
  -- ⚠ staff_id 를 반드시 함께 건다 — 안 걸면 번호만 알면 남의 것을 읽음 처리할 수 있다
  update public.staff_notice set read_at = now()
   where staff_id = p_staff_id and read_at is null
     and (p_id is null or id = p_id);
  return public.staff_notices(p_staff_id, p_page);
end$$;
revoke all on function public.staff_notice_read(uuid, bigint, int) from public;
grant execute on function public.staff_notice_read(uuid, bigint, int) to anon, authenticated;
