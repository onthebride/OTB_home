-- 폰 알림은 「알림 켜기」를 누른 그 기기에만 (대표 2026-09-10
--   «황지성 배정한게 왜 관리자 나한테 알림이 오지?»
--   «당연히 알림켜기 한 기기만 알림이 오게 해야지 / 나도 수시로 보기때문에 내가 보는건 그냥 아예 막아야해»)
--
-- 무슨 일이 있었나
--   staff-calendar.js 가 페이지를 열 때마다 이 기기를 «지금 보고 있는 작가» 것으로 다시 적었다.
--   단추를 누르지 않아도 그랬다. 게다가 여기 있던 「작가는 한 기기만」 규칙이
--   그 작가가 제 폰에 켜둔 등록을 지웠다.
--   그래서 대표가 작가 캘린더를 열어보기만 해도
--     ① 그 작가 알림이 대표 폰으로 가고
--     ② 그 작가는 제 폰으로 못 받게 됐다.
--   실제로 여섯 분이 그랬다 (8/27 손대희 · 8/28 김보라 · 8/29 황지성 ·
--   8/31 강사무엘 · 8/31 장길희 · 9/10 김주영). 오늘 대표 폰에 뜬 황지성 배정 알림이 그것이다.
--
-- 여기서 막는 것
--   · 관리자로 쓰는 기기(그 엔드포인트에 staff_id 가 빈 줄이 있는 것)에는 남의 작가 알림을 붙이지 않는다.
--     되돌려 보내기만 하고 **아무것도 지우지 않는다** — 작가가 제 폰에 켜둔 것은 그대로 있어야 한다.
--   · 대표 본인(is_rep)은 예외다. 제 알림을 제 기기에서 받는 것은 막을 까닭이 없다.
--   · 화면이 «켜져 있나» 를 물어볼 수 있게 push_state 를 새로 판다.
--     예전에는 물어볼 길이 없어서 save 를 불러 «저장하면서» 알아봤다 — 그게 이 사고의 출발이었다.

create or replace function public.save_push_subscription(
  p_endpoint text, p_p256dh text, p_auth text, p_staff_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
declare shared boolean := false; rep boolean := false;
begin
  if p_endpoint is null or p_p256dh is null or p_auth is null then raise exception 'bad subscription'; end if;
  if p_staff_id is null then
    if auth.uid() is null then raise exception 'unauthorized'; end if;
  else
    select coalesce(st.is_rep, false) into rep
      from public.staff st where st.id = p_staff_id and coalesce(st.active, false);
    if rep is null then raise exception 'staff not found'; end if;
    -- 이 기기가 관리자 기기인가
    select exists (select 1 from public.push_subscriptions
                   where endpoint = p_endpoint and staff_id is null) into shared;
    if shared and not rep then
      -- 대표가 보러 들어온 것이다. 붙이지 않는다. 작가가 다른 폰에 켜둔 것도 건드리지 않는다
      return jsonb_build_object('ok', false, 'reason', 'admin_app', 'admin_app', true);
    end if;
    -- 작가는 한 기기만. 제가 다른 기기에서 켜면 이전 것은 꺼진다
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

-- 켜져 있나 물어보기만 한다 — 아무것도 적지 않는다
create or replace function public.push_state(p_endpoint text, p_staff_id uuid)
returns jsonb language sql stable security definer set search_path=public, pg_temp as $$
  select jsonb_build_object(
    'on', exists (select 1 from public.push_subscriptions
                   where endpoint = p_endpoint and staff_id = p_staff_id),
    'admin_app', exists (select 1 from public.push_subscriptions
                          where endpoint = p_endpoint and staff_id is null));
$$;
revoke all on function public.push_state(text, uuid) from public;
grant execute on function public.push_state(text, uuid) to anon, authenticated;

-- 지금 잘못 붙어 있는 것을 치운다 (대표 «내가 보는건 그냥 아예 막아야해»).
-- 이 여섯 분은 제 폰에서 「알림 켜기」를 다시 눌러야 한다 — 옛 등록은 이미 지워져 되살릴 수 없다
delete from public.push_subscriptions p
 where p.staff_id is not null
   and exists (select 1 from public.push_subscriptions a
                where a.endpoint = p.endpoint and a.staff_id is null)
   and not exists (select 1 from public.staff st
                    where st.id = p.staff_id and coalesce(st.is_rep, false));
