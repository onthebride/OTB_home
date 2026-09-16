-- 지정 촬영 — 문턱을 낮추고 사다리를 새로 잡는다 (대표 2026-09-16)
--
--   «지정비 문턱을 확 낮추자 / 일단 기본 촬영 1번에 후기 1개 갤러리 1개 면
--     무조건 지정비용 넣을 수 있는걸로»
--   «사다리를 조정을 좀 하자 / 그래야 약간 동기부여도 되고 할거 같은데
--     촬영 1회, 후기 1회, 사진 1개 는 지정비용 10만원까지 가능
--     촬영 3회 후기 3회 사진 10개는 15만원까지
--     촬영 5회 후기 5회 사진 30개는 20만원
--     촬영 20회 후기 20회 사진 50개 이상은 30만원 이상»
--   «확정 값 3만원 가고 최소 지정 비용 6만원 이상으로 하자 / 50% 최대 3만원 까지 수수료»
--   «상한은 없이 하자 / 금액 없으면 지정값 3만원»
--   «그리고 세금문구는 일단 빼자»
--   «일단 예약신청에는 넣지말고 작가들 오늘 내가 공지를 할꺼니까 바꿔놔줘»
--
-- ⚠ **문이 둘이다.** 자격 문턱(pick_rules)만 낮추면 아무도 안 열린다 —
--   한도 사다리(pick_cap) 1단이 「후기3·갤10 → 5만원」이라 최소 6만원을 못 적는다.
--   그래서 **둘을 같이** 고친다. 실측: 지금 적을 수 있는 분 둘 → 여섯.
--
-- ⚠ 사다리에 **촬영 수**가 새로 들어온다. pick_cap 에 칸을 더하므로 drop 을 같이 쓴다.
--
-- ⚠ 「상한 없음」은 셈으로는 100만원이다 (staff_pick_fee_range 의 천장).
--   지정비에 100만원을 적을 일은 없으니 사실상 안 막는 것과 같다. 화면에는 「상한 없음」으로 적는다.
--
-- ⚠ 세금 3.3% 는 **셈만 남기고 글을 감춘다** (대표 «일단» 빼자). tax_bp 는 그대로 둔다 —
--   지우면 되살리실 때 다시 만들어야 한다.

/* ===== 규칙은 한 곳에서만 ===== */
create or replace function private.pick_rules()
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    -- 자격 문턱 (대표 2026-09-16 «확 낮추자»). 사다리 1단과 **같은 줄**이라야 한다 —
    -- 문턱을 넘었는데 한도가 0이면 「되는데 못 넣는」 자리가 생긴다
    'shots',   1,      -- 주작가로 찍은 우리 예식 (부작가는 안 센다)
    'reviews', 1,      -- 후기
    'gallery', 1,      -- 갤러리에 올라간 내 사진
    'base',    250000, -- 기본 페이
    'tax_bp',  330,    -- 3.3%. ⚠ 지금은 화면에 안 적는다 (대표 «세금문구는 일단 빼자»)
    -- 값 규칙 (대표 2026-09-16)
    'fee_min',     60000,  -- 작가가 적을 수 있는 최소
    'pin_default', 30000,  -- 안 적었거나 0이면 이 값에 팔린다
    /* ⚠ 수수료는 **안 뗀다** — 대표 2026-09-16 «지정하는건 우리가 안가져가는걸로하자».
       그날 낮에 «50% 최대 3만원» 으로 정하셨다가 한 시간 만에 뒤집으셨다.
       **셈하는 길은 살려 둔다** — 0 으로 두기만 했다. 다시 떼기로 하시면 이 두 줄만 고치면 되고
       화면·시험은 그대로 따라온다 (화면은 0 이면 「회사 몫」 줄을 아예 안 그린다) */
    'cut_pct',     0,
    'cut_max',     0,
    /* 지정비 한도 사다리. **촬영·후기·갤러리 셋을 다 넘어야** 그 단으로 간다.
       ⚠ 셋 중 하나만 높으면 신부님이 보고 고를 것이 모자란다 */
    'tiers', jsonb_build_array(
      jsonb_build_object('shots',  1, 'reviews',  1, 'gallery',  1, 'cap',  100000),
      jsonb_build_object('shots',  3, 'reviews',  3, 'gallery', 10, 'cap',  150000),
      jsonb_build_object('shots',  5, 'reviews',  5, 'gallery', 30, 'cap',  200000),
      -- 맨 윗단은 상한이 없다 (대표 «상한은 없이 하자»). 셈으로는 제약의 천장
      jsonb_build_object('shots', 20, 'reviews', 20, 'gallery', 50, 'cap', 1000000)))
$$;

/* ===== 지금 얼마까지 올릴 수 있나 =====
   ⚠ 칸(촬영)을 더하므로 옛 판을 먼저 버린다. 안 그러면 이름이 같은 함수가 둘이 된다 */
drop function if exists private.pick_cap(int, int);
create or replace function private.pick_cap(p_shots int, p_reviews int, p_gallery int)
returns jsonb language sql immutable as $$
  with t as (
    select (e->>'shots')::int sh, (e->>'reviews')::int rv, (e->>'gallery')::int gl,
           (e->>'cap')::int cap, row_number() over (order by (e->>'cap')::int) i
      from jsonb_array_elements(private.pick_rules()->'tiers') e
  ), got as (
    select * from t where p_shots >= sh and p_reviews >= rv and p_gallery >= gl
  )
  select jsonb_build_object(
    -- 셋을 다 넘은 것 중 제일 높은 단. 하나도 못 넘었으면 0
    'cap', coalesce((select max(cap) from got), 0),
    'tier', coalesce((select max(i) from got), 0),
    'tiers_n', (select count(*) from t),
    -- 맨 윗단에 올랐으면 상한이 없다 — 화면이 「상한 없음」으로 적는다
    'no_cap', coalesce((select max(i) from got), 0) = (select count(*) from t),
    -- 바로 다음 단 (없으면 null = 꼭대기)
    'next', (select jsonb_build_object('shots', sh, 'reviews', rv, 'gallery', gl, 'cap', cap)
               from t where not (p_shots >= sh and p_reviews >= rv and p_gallery >= gl)
              order by cap limit 1));
$$;
revoke all on function private.pick_cap(int, int, int) from public, anon, authenticated;

/* ===== 한 작가가 지금 어디까지 왔나 ===== */
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

  -- 셋을 다 넘고, 스케줄을 받고 있어야 지정을 받는다
  okk := acc
     and n_shot >= (r->>'shots')::int
     and n_rev  >= (r->>'reviews')::int
     and n_gal  >= (r->>'gallery')::int;

  capj := private.pick_cap(n_shot, n_rev, n_gal);

  return jsonb_build_object(
    'shots', n_shot, 'reviews', n_rev, 'gallery', n_gal,
    'need_shots',   (r->>'shots')::int,
    'need_reviews', (r->>'reviews')::int,
    'need_gallery', (r->>'gallery')::int,
    'accepting', acc,
    'is_rep', rep,
    'ok', okk,
    -- 대표는 한도를 안 탄다 — 대표지정은 우리가 값을 정해 파는 상품이다
    'fee_cap',  case when not okk then 0
                     when rep then 1000000
                     else (capj->>'cap')::int end,
    'no_cap',   case when rep then true
                     when not okk then false
                     else (capj->>'no_cap')::boolean end,
    'fee_tier', (capj->>'tier')::int,
    'tiers_n',  (capj->>'tiers_n')::int,
    'next_tier', case when rep then null else capj->'next' end,
    'tiers', r->'tiers');
end$$;
revoke all on function private.pick_eligible(uuid) from public, anon, authenticated;

/* ===== 최소 6만원 — 표에도 걸어둔다 =====
   ⚠ 0 은 그대로 둔다. 다만 뜻이 바뀌었다 — 「안 팔린다」가 아니라
     「팔리지만 내 몫이 없다」다 (확정값 3만원은 전액 회사). 화면 글도 그렇게 고쳤다 */
alter table public.staff drop constraint if exists staff_pick_fee_range;
alter table public.staff add constraint staff_pick_fee_range
  check (pick_fee is null or pick_fee = 0 or (pick_fee >= 60000 and pick_fee <= 1000000));

/* ===== 작가 화면이 받는 것 — 값 규칙을 같이 준다 ===== */
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
    'elig', e,
    'base', (r->>'base')::int,
    'tax_bp', (r->>'tax_bp')::int,
    -- 2026-09-16 에 더한 값 규칙. 화면이 여기서 받아 적는다 — 두 곳에 숫자를 두지 않는다
    'fee_min',     (r->>'fee_min')::int,
    'pin_default', (r->>'pin_default')::int,
    'cut_pct',     (r->>'cut_pct')::int,
    'cut_max',     (r->>'cut_max')::int);
end$$;
revoke all on function public.staff_settings(uuid) from public;
grant execute on function public.staff_settings(uuid) to anon, authenticated;

/* ===== 넣을 때 막는다 =====
   ⚠ 화면만 잠그면 개발자도구로 그냥 부를 수 있다. 여기서 막아야 진짜로 막힌다 */
create or replace function public.staff_settings_set(p_staff_id uuid, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'private', 'pg_temp' as $$
declare e jsonb; r jsonb; fee int; cap int; fmin int;
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
    e := private.pick_eligible(p_staff_id);
    r := private.pick_rules();
    if not (e->>'ok')::boolean then
      raise exception 'not eligible: shots %/% reviews %/% gallery %/% accepting %',
        e->>'shots', e->>'need_shots', e->>'reviews', e->>'need_reviews',
        e->>'gallery', e->>'need_gallery', e->>'accepting';
    end if;
    fee := nullif(p_patch->>'pick_fee','')::int;
    if fee is not null and fee < 0 then raise exception 'bad fee'; end if;
    /* 최소 6만원 (대표 2026-09-16). 0 은 「안 받겠다」라 그대로 받는다 —
       그래도 지정은 확정값 3만원에 팔리고, 그 3만원은 전액 회사 몫이다 */
    fmin := (r->>'fee_min')::int;
    if fee is not null and fee > 0 and fee < fmin then
      raise exception '지정 촬영비는 %원부터 정하실 수 있어요 (안 받으시려면 0)',
        to_char(fmin, 'FM999,999,999');
    end if;
    cap := (e->>'fee_cap')::int;
    if fee is not null and fee > cap then
      raise exception '지금 한도는 %원입니다 (촬영 %회·후기 %개·갤러리 %장). 더 쌓이면 한도가 올라갑니다',
        to_char(cap, 'FM999,999,999'), e->>'shots', e->>'reviews', e->>'gallery';
    end if;
    update public.staff set pick_fee = fee, pick_fee_at = now() where id = p_staff_id;
  end if;

  return public.staff_settings(p_staff_id);
end$$;
revoke all on function public.staff_settings_set(uuid, jsonb) from public;
grant execute on function public.staff_settings_set(uuid, jsonb) to anon, authenticated;
