-- 작가 캘린더에 「설정」 칸 (대표 요청 2026-08-27)
-- «작가별 설정탭을 하나 더 추가해줘 / 거기에 알람여부도 넣고 / 스케줄을 계속 받을지
--   그만받을지도 토글 넣어줘 / 지정비용을 넣을 수 있게 해주고 /
--   지정비용은 우리랑 촬영 후 후기가 5개이상 쌓여야지만 비용을 넣을 수 있게 해줘»
--
-- 앞으로 신부가 예약할 때 「이 작가로 지정」을 옵션으로 고르면 기본가에 이 값이 붙는다.
-- **그 앞단은 아직 안 만든다** — 대표 «지금은 아니고 나중에». 여기서는 작가가 값을 적어두는 데까지만.
--
-- 작가는 로그인이 없다. 캘린더와 같이 **링크(작가ID)를 아는 사람을 본인으로 본다.**

alter table public.staff add column if not exists accepting  boolean not null default true;
alter table public.staff add column if not exists pick_fee   int;
alter table public.staff add column if not exists pick_fee_at timestamptz;

-- 값은 서버가 지킨다. 0 은 「지정비 안 받음」, 위로는 100만원까지
alter table public.staff drop constraint if exists staff_pick_fee_range;
alter table public.staff add constraint staff_pick_fee_range
  check (pick_fee is null or (pick_fee >= 0 and pick_fee <= 1000000));

-- 지정비를 적을 수 있는 문턱. 한 곳에서만 정한다 — 화면과 서버가 어긋나면 안 된다
create or replace function private.pick_fee_min_reviews()
returns int language sql immutable as $$ select 5 $$;

/* ===== 작가 본인이 보는 설정 ===== */
drop function if exists public.staff_settings(uuid);
create or replace function public.staff_settings(p_staff_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public, pg_temp as $$
declare st public.staff; n int; need int := private.pick_fee_min_reviews();
begin
  select * into st from public.staff where id = p_staff_id and coalesce(active,false);
  if not found then raise exception 'staff not found'; end if;

  -- 「우리랑 촬영 후 후기」 = 그 작가가 메인으로 찍은 예식의 설문 응답
  select count(*)::int into n from public.feedback where staff_id = p_staff_id;

  return jsonb_build_object(
    'name', st.name,
    'is_rep', coalesce(st.is_rep, false),
    'accepting', coalesce(st.accepting, true),
    'pick_fee', st.pick_fee,
    'reviews', n,
    'need', need,
    'can_fee', n >= need);
end$$;
revoke all on function public.staff_settings(uuid) from public;
grant execute on function public.staff_settings(uuid) to anon, authenticated;

/* ===== 작가가 고치는 것 =====
   p_patch = {"accepting": true|false} 또는 {"pick_fee": 30000}  (둘 다 줘도 된다) */
drop function if exists public.staff_settings_set(uuid, jsonb);
create or replace function public.staff_settings_set(p_staff_id uuid, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
declare n int; need int := private.pick_fee_min_reviews(); fee int;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and coalesce(active,false)) then
    raise exception 'staff not found';
  end if;
  if jsonb_typeof(p_patch) <> 'object' then raise exception 'bad patch'; end if;

  if p_patch ? 'accepting' then
    if jsonb_typeof(p_patch->'accepting') <> 'boolean' then raise exception 'bad accepting'; end if;
    update public.staff set accepting = (p_patch->>'accepting')::boolean where id = p_staff_id;
  end if;

  if p_patch ? 'pick_fee' then
    -- ⚠ 문턱은 **서버에서** 막는다. 화면만 잠그면 개발자도구로 그냥 부를 수 있다
    select count(*)::int into n from public.feedback where staff_id = p_staff_id;
    if n < need then
      raise exception 'need % reviews (now %)', need, n;
    end if;
    fee := nullif(p_patch->>'pick_fee','')::int;
    if fee is not null and (fee < 0 or fee > 1000000) then raise exception 'bad fee'; end if;
    update public.staff set pick_fee = fee, pick_fee_at = now() where id = p_staff_id;
  end if;

  return public.staff_settings(p_staff_id);
end$$;
revoke all on function public.staff_settings_set(uuid, jsonb) from public;
grant execute on function public.staff_settings_set(uuid, jsonb) to anon, authenticated;
