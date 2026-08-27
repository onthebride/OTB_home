-- 「내 캘린더로 알림이 안 오고 관리자로 온다」 (대표 2026-08-27)
--
-- 아이폰은 홈 화면에 추가한 앱마다 저장소가 따로다. 그래서 알림도 **켠 앱**으로 간다.
-- 대표는 관리자 앱 안에서 캘린더를 열고 거기서 알림을 켰다 —
-- 그 앱의 등록(endpoint)이 이미 관리자 것으로 쓰이고 있어서, 작가 알림이
-- 관리자 앱 이름과 아이콘으로 떴다.
--
-- 근본은 관리자 manifest 의 울타리(scope)가 «/» 여서 /staff-calendar 도 관리자 앱 안이었던 것.
-- 그건 /admin 으로 좁혔다. 여기서는 **이미 그렇게 켠 사람에게 알려주는** 길을 만든다.
--
-- ⚠ 돌려주는 형이 바뀐다(void → jsonb). `create or replace` 로는 형을 못 바꾼다. 먼저 지운다.

drop function if exists public.save_push_subscription(text, text, text, uuid);
drop function if exists public.save_push_subscription(text, text, text);

create or replace function public.save_push_subscription(
  p_endpoint text, p_p256dh text, p_auth text, p_staff_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
declare shared boolean := false;
begin
  if p_endpoint is null or p_p256dh is null or p_auth is null then raise exception 'bad subscription'; end if;
  if p_staff_id is null then
    if auth.uid() is null then raise exception 'unauthorized'; end if;
  else
    if not exists (select 1 from public.staff where id = p_staff_id and coalesce(active, false)) then
      raise exception 'staff not found';
    end if;
    -- 이 등록이 이미 «관리자 것» 이라면, 이 앱에서 켠 알림은 관리자 앱으로 뜬다.
    -- 막지는 않는다 — 못 받는 것보다는 낫다. 대신 화면이 알려줄 수 있게 알려준다
    select exists (select 1 from public.push_subscriptions
                   where endpoint = p_endpoint and staff_id is null) into shared;
    -- 작가는 한 기기만. 다른 데서 켜면 이전 것은 꺼진다
    delete from public.push_subscriptions
     where staff_id = p_staff_id and endpoint <> p_endpoint;
  end if;
  insert into public.push_subscriptions (endpoint, p256dh, auth, staff_id)
    values (p_endpoint, p_p256dh, p_auth, p_staff_id)
  on conflict (endpoint, staff_id) do update
    set p256dh = excluded.p256dh, auth = excluded.auth;
  return jsonb_build_object('ok', true, 'admin_app', shared);
end$$;
revoke all on function public.save_push_subscription(text, text, text, uuid) from public;
grant execute on function public.save_push_subscription(text, text, text, uuid) to anon, authenticated;
