-- 지정 촬영 — 작가가 지정을 받을 수 있는 요건 (대표 2026-08-30)
--
--   «온더브라이드 스케줄을 최소 3회 이상 촬영
--     후기 3개 이상
--     신부님들 yes하신 촬영건 중 갤러리에 10장이상 올라가야함
--     추가되는 지정 비용은 자유 입니다 ...
--     지정촬영시 페이는 3.3프로 세금 공제 됩니다»
--
-- 이어서 물어본 것에 대한 답:
--   «서브작가만 하는사람은 지정 안됨»            → 주작가(assignee_id)로 찍은 것만 센다
--   «스케줄을 안받지 않는 한 계속 유지»          → 자동으로 뺏지 않는다. accepting 이 곧 자격이다
--   «자동으로 꺼지면 당연히 지정도 내려가야지»   → 그래서 손으로 끄든 석 달 자동이든 구분하지 않는다
--
-- ⚠ 「신부님들 yes하신 촬영건 중」 을 기계가 확인할 방법이 없다.
--   public.gallery 에 booking_id 가 없어서 그 사진이 어느 예약에서 나왔는지 모른다.
--   **그래서 「갤러리에 있다 = 이미 yes 건」 으로 센다.** 이건 짐작이 아니라 대표가
--   확인해 준 것이다 — 2026-08-30 «맞아 갤러리에 올라간던 다 yes된 사진만 내가 올리는거야».
--   즉 동의 확인은 대표가 올리실 때 손으로 하고 계신다. 프로그램은 그 뒤를 센다.
--   ⚠ 이 전제가 깨지는 날(작가가 직접 올리게 되는 등)에는 여기부터 다시 봐야 한다.
--     그때는 gallery 에 booking_id 를 붙이고 photo_usage_agree 로 걸러야 한다.
--
-- ⚠ 갤러리 693장 중 451장에 작가가 안 적혀 있다(2026-08-30). 안 적힌 사진은 아무의 몫도
--   아니라 이 요건이 실제보다 빡빡하게 걸린다. 대표가 채우시는 중이다.

/* ===== 요건은 한 곳에서만 정한다 =====
   화면과 서버가 어긋나면 «화면엔 됐다는데 저장이 안 된다» 가 된다 */
create or replace function private.pick_rules()
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'shots',   3,      -- 주작가로 찍은 우리 예식 (부작가는 안 센다)
    'reviews', 3,      -- 후기. 대표가 5 → 3 으로 내렸다 (2026-08-30)
    'gallery', 10,     -- 갤러리에 올라간 내 사진
    'base',    250000, -- 기본 페이
    'tax_bp',  330)    -- 3.3% = 330/10000. 지정 촬영은 전체 페이에서 뗀다
$$;

-- 예전 이름은 남겨 둔다 — 후기 문턱 하나만 묻는 자리가 있다
create or replace function private.pick_fee_min_reviews()
returns int language sql immutable as $$ select (private.pick_rules()->>'reviews')::int $$;

/* ===== 한 작가가 지금 어디까지 왔나 =====
   못 넘은 요건만 알려주는 게 아니라 **셋 다 숫자로** 준다.
   작가님이 「뭘 더 하면 되는지」 를 봐야 하기 때문이다 */
drop function if exists private.pick_eligible(uuid);
create or replace function private.pick_eligible(p_staff_id uuid)
returns jsonb language plpgsql stable security definer
set search_path to 'private', 'public', 'pg_temp' as $$
declare
  r jsonb := private.pick_rules();
  today date := (now() at time zone 'Asia/Seoul')::date;
  n_shot int; n_rev int; n_gal int; acc boolean;
begin
  select coalesce(st.accepting, true) into acc from public.staff st
   where st.id = p_staff_id and coalesce(st.active, false);
  if not found then raise exception 'staff not found'; end if;

  -- 주작가로 찍은, 지나간, 취소가 아닌 예식.
  -- ⚠ sub_assignee_id 는 세지 않는다 (대표 «서브작가만 하는사람은 지정 안됨»)
  select count(*)::int into n_shot from public.bookings b
   where b.assignee_id = p_staff_id and b.status <> '취소' and b.wedding_date < today;

  select count(*)::int into n_rev from public.feedback f where f.staff_id = p_staff_id;
  select count(*)::int into n_gal from public.gallery g where g.staff_id = p_staff_id;

  return jsonb_build_object(
    'shots', n_shot, 'reviews', n_rev, 'gallery', n_gal,
    'need_shots',   (r->>'shots')::int,
    'need_reviews', (r->>'reviews')::int,
    'need_gallery', (r->>'gallery')::int,
    'accepting', acc,
    -- 셋을 다 넘고, 스케줄을 받고 있어야 지정을 받는다.
    -- 손으로 끄셨든 석 달 자동으로 꺼졌든 구분하지 않는다 (대표 2026-08-30)
    'ok', acc
       and n_shot >= (r->>'shots')::int
       and n_rev  >= (r->>'reviews')::int
       and n_gal  >= (r->>'gallery')::int);
end$$;
revoke all on function private.pick_eligible(uuid) from public, anon, authenticated;

/* ===== 작가 본인이 보는 설정 ===== */
drop function if exists public.staff_settings(uuid);
create or replace function public.staff_settings(p_staff_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public, pg_temp as $$
declare st public.staff; e jsonb; r jsonb := private.pick_rules();
begin
  select * into st from public.staff where id = p_staff_id and coalesce(active,false);
  if not found then raise exception 'staff not found'; end if;

  e := private.pick_eligible(p_staff_id);

  return jsonb_build_object(
    'name', st.name,
    'is_rep', coalesce(st.is_rep, false),
    'accepting', coalesce(st.accepting, true),
    'pick_fee', st.pick_fee,
    -- 지금까지 화면이 쓰던 이름 둘. 그대로 둔다
    'reviews', e->'reviews',
    'need', (r->>'reviews')::int,
    'can_fee', (e->>'ok')::boolean,
    -- 진행률을 그리는 데 쓴다
    'elig', e,
    'base', (r->>'base')::int,
    'tax_bp', (r->>'tax_bp')::int);
end$$;
revoke all on function public.staff_settings(uuid) from public;
grant execute on function public.staff_settings(uuid) to anon, authenticated;

/* ===== 작가가 고치는 것 ===== */
drop function if exists public.staff_settings_set(uuid, jsonb);
create or replace function public.staff_settings_set(p_staff_id uuid, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
declare e jsonb; fee int;
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
    -- ⚠ 요건은 **서버에서** 막는다. 화면만 잠그면 개발자도구로 그냥 부를 수 있다
    e := private.pick_eligible(p_staff_id);
    if not (e->>'ok')::boolean then
      raise exception 'not eligible: shots %/% reviews %/% gallery %/% accepting %',
        e->>'shots', e->>'need_shots', e->>'reviews', e->>'need_reviews',
        e->>'gallery', e->>'need_gallery', e->>'accepting';
    end if;
    fee := nullif(p_patch->>'pick_fee','')::int;
    if fee is not null and (fee < 0 or fee > 1000000) then raise exception 'bad fee'; end if;
    update public.staff set pick_fee = fee, pick_fee_at = now() where id = p_staff_id;
  end if;

  return public.staff_settings(p_staff_id);
end$$;
revoke all on function public.staff_settings_set(uuid, jsonb) from public;
grant execute on function public.staff_settings_set(uuid, jsonb) to anon, authenticated;
