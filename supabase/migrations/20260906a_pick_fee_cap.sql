-- 지정비를 마음대로 넣는 게 아니라 «한도»를 쌓아 올린다 (대표 2026-09-06
--   «이게 마음대로 지정비를 넣는거말고 / 일정 후기랑 갤러리 사진이 쌓이면
--     지정비 한도를 늘리게해주는걸로»)
--
-- 전에는 요건 셋을 넘으면 0~100만원 사이 아무 값이나 넣을 수 있었다.
-- 이제는 후기와 갤러리가 쌓인 만큼만 올릴 수 있다.
--
-- ⚠ 사다리 두 칸(후기·갤러리)을 **둘 다** 넘어야 그 단으로 간다.
--   후기만 많고 갤러리가 비면 신부님이 보고 고를 것이 없다. 반대도 마찬가지다.
-- ⚠ 숫자는 여기 한 곳에만 있다. 대표가 바꾸라 하시면 이 표만 고친다.
-- ⚠ 대표는 한도를 안 탄다. 「대표지정」은 우리가 값을 정해 파는 상품이지
--   작가가 쌓아 올리는 것이 아니다 (예약 폼의 대표지정 35만원과 같은 것).

create or replace function private.pick_rules()
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'shots',   3,      -- 주작가로 찍은 우리 예식 (부작가는 안 센다)
    'reviews', 3,      -- 후기. 대표가 5 → 3 으로 내렸다 (2026-08-30)
    'gallery', 10,     -- 갤러리에 올라간 내 사진
    'base',    250000, -- 기본 페이
    'tax_bp',  330,    -- 3.3% = 330/10000. 지정 촬영은 전체 페이에서 뗀다
    -- 지정비 한도 사다리 (대표 2026-09-06). 후기·갤러리를 둘 다 넘은 가장 높은 단
    'tiers', jsonb_build_array(
      jsonb_build_object('reviews',  3, 'gallery',  10, 'cap',  50000),
      jsonb_build_object('reviews',  5, 'gallery',  20, 'cap', 100000),
      jsonb_build_object('reviews', 10, 'gallery',  40, 'cap', 200000),
      jsonb_build_object('reviews', 20, 'gallery',  70, 'cap', 300000),
      jsonb_build_object('reviews', 30, 'gallery', 100, 'cap', 500000)))
$$;

/* ── 지금 얼마까지 올릴 수 있나 ──
   ⚠ 요건을 못 넘었으면 0 이다. 「넣을 수는 있는데 한도가 0」이 아니라 아예 못 넣는다.
   ⚠ 다음 단이 무엇인지도 같이 준다 — 얼마나 더 모으면 얼마까지 되는지 보여드려야
     작가님이 채울 마음이 생긴다 */
create or replace function private.pick_cap(p_reviews int, p_gallery int)
returns jsonb language sql immutable as $$
  with t as (
    select (e->>'reviews')::int rv, (e->>'gallery')::int gl, (e->>'cap')::int cap,
           row_number() over (order by (e->>'cap')::int) i
      from jsonb_array_elements(private.pick_rules()->'tiers') e
  )
  select jsonb_build_object(
    -- 둘 다 넘은 것 중 제일 높은 단. 하나도 못 넘었으면 0
    'cap', coalesce((select max(cap) from t where p_reviews >= rv and p_gallery >= gl), 0),
    'tier', coalesce((select max(i) from t where p_reviews >= rv and p_gallery >= gl), 0),
    'tiers_n', (select count(*) from t),
    -- 바로 다음 단 (없으면 null = 꼭대기)
    'next', (select jsonb_build_object('reviews', rv, 'gallery', gl, 'cap', cap)
               from t where not (p_reviews >= rv and p_gallery >= gl) order by cap limit 1));
$$;

create or replace function private.pick_eligible(p_staff_id uuid)
returns jsonb language plpgsql stable security definer
set search_path to 'private', 'public', 'pg_temp' as $$
declare
  r jsonb := private.pick_rules();
  today date := (now() at time zone 'Asia/Seoul')::date;
  n_shot int; n_rev int; n_gal int; acc boolean; rep boolean; okk boolean; capj jsonb;
begin
  select coalesce(st.accepting, true), coalesce(st.is_rep, false) into acc, rep
    from public.staff st
   where st.id = p_staff_id and coalesce(st.active, false);
  if not found then raise exception 'staff not found'; end if;

  -- 주작가로 찍은, 지나간, 취소가 아닌 예식.
  -- ⚠ sub_assignee_id 는 세지 않는다 (대표 «서브작가만 하는사람은 지정 안됨»)
  select count(*)::int into n_shot from public.bookings b
   where b.assignee_id = p_staff_id and b.status <> '취소' and b.wedding_date < today;

  select count(*)::int into n_rev from public.feedback f where f.staff_id = p_staff_id;
  select count(*)::int into n_gal from public.gallery g where g.staff_id = p_staff_id;

  -- 셋을 다 넘고, 스케줄을 받고 있어야 지정을 받는다.
  -- 손으로 끄셨든 석 달 자동으로 꺼졌든 구분하지 않는다 (대표 2026-08-30)
  okk := acc
     and n_shot >= (r->>'shots')::int
     and n_rev  >= (r->>'reviews')::int
     and n_gal  >= (r->>'gallery')::int;

  capj := private.pick_cap(n_rev, n_gal);

  return jsonb_build_object(
    'shots', n_shot, 'reviews', n_rev, 'gallery', n_gal,
    'need_shots',   (r->>'shots')::int,
    'need_reviews', (r->>'reviews')::int,
    'need_gallery', (r->>'gallery')::int,
    'accepting', acc,
    'is_rep', rep,
    'ok', okk,
    -- 한도 (대표 2026-09-06). 대표는 한도를 안 탄다 — 대표지정은 우리가 값을 정해 파는 상품이다
    'fee_cap',  case when not okk then 0
                     when rep then (r->>'base')::int * 4      -- 사실상 안 막는다
                     else (capj->>'cap')::int end,
    'fee_tier', (capj->>'tier')::int,
    'tiers_n',  (capj->>'tiers_n')::int,
    'next_tier', case when rep then null else capj->'next' end,
    'tiers', r->'tiers');
end$$;
revoke all on function private.pick_cap(int, int) from public, anon, authenticated;
revoke all on function private.pick_eligible(uuid) from public, anon, authenticated;

/* ── 작가 화면이 받는 것 ── */
create or replace function public.staff_settings(p_staff_id uuid)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'private', 'pg_temp' as $$
declare st public.staff; r jsonb := private.pick_rules(); e jsonb;
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

/* ── 넣을 때 한도를 넘는지 본다 ──
   ⚠ 화면만 잠그면 개발자도구로 그냥 부를 수 있다. 여기서 막아야 진짜로 막힌다 */
create or replace function public.staff_settings_set(p_staff_id uuid, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare e jsonb; fee int; cap int;
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
    if fee is not null and fee < 0 then raise exception 'bad fee'; end if;
    -- 한도 (대표 2026-09-06 «후기랑 갤러리 사진이 쌓이면 지정비 한도를 늘리게»)
    cap := (e->>'fee_cap')::int;
    if fee is not null and fee > cap then
      raise exception '지금 한도는 %원입니다 (후기 %개·갤러리 %장). 더 쌓이면 한도가 올라갑니다',
        to_char(cap, 'FM999,999,999'), e->>'reviews', e->>'gallery';
    end if;
    update public.staff set pick_fee = fee, pick_fee_at = now() where id = p_staff_id;
  end if;

  return public.staff_settings(p_staff_id);
end$$;
revoke all on function public.staff_settings_set(uuid, jsonb) from public;
grant execute on function public.staff_settings_set(uuid, jsonb) to anon, authenticated;
