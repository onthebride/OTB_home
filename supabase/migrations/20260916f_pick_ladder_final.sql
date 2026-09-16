-- 지정 촬영 사다리 — 대표가 다시 잡아 확정하신 것 (2026-09-16 저녁)
--
--   «지정 촬영 사다리 다시 얘기해줄께
--     일단 지정은 기본 5만원이고 우리가 주기로 하고
--     그 이상은 조건을 맞춰야 가능해
--     촬영 3회이상 후기 3개이상 갤러리사진 5개이상 부터는 10만원까지 지정가능
--     촬영 10회 이상 후기 10개이상 갤러리 사진 20개부터는 15만원까지
--     촬영 20회 이상 후기 20개 이상 사진 30개 부터는 20만원까지
--     촬영 30회이상 후기 30개 이상 사진 50개 부터는 그 이상
--     이렇게 확정 하자고»
--
-- 앞판(20260916e)과 무엇이 다른가
--   · **자격 문턱이 없어졌다.** 촬영1·후기1·사진1 을 넘어야 지정을 받을 수 있었는데,
--     이제 **누구나 기본 5만원에 지정된다.** 조건은 「그보다 높게 부를 수 있나」에만 쓴다
--   · 기본값이 3만 → **5만원**. 그 돈은 작가님이 받으신다 («우리가 주기로 하고»)
--   · 최소도 6만 → **5만원** (기본값 아래로는 못 부른다)
--   · 사다리 칸이 통째로 바뀌었다
--
-- ⚠⚠ 자격 문턱을 0 으로 내리면서 **「서브작가만 하는 사람은 지정 안 됨」**(대표 2026-08-30)이
--   같이 풀릴 뻔했다. 그 규칙은 지금까지 「주작가로 찍은 것만 세고 3회 이상」으로 지켜지고 있었다.
--   문턱이 0 이면 서브 전용 작가도 통과한다. 그래서 **can_main 을 직접 본다.**
--   (지금 서브 전용: 김태연·임재훈·최선종)
--
-- ⚠ 값이 하루에 네 번 바뀌었다. 수수료(cut_pct·cut_max)는 0 인 채 길만 살려 둔다.
--   세금 3.3%(tax_bp)도 «나중에» 라 남겨 둔다. 서버 두 줄만 고치면 화면이 따라온다.

create or replace function private.pick_rules()
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    /* ⚠ 자격 문턱은 **없다** (대표 2026-09-16 «일단 지정은 기본 5만원»).
       셋을 0 으로 두어 사다리 1단(기본)과 같은 줄로 맞춘다.
       ⚠ 서브 전용 작가를 막는 것은 이 숫자가 아니라 can_main 이다 — pick_eligible 을 볼 것 */
    'shots',   0,
    'reviews', 0,
    'gallery', 0,
    'base',    250000, -- 기본 페이
    'tax_bp',  330,    -- 3.3%. ⚠ 지금은 화면에 안 적는다 (대표 «세금문구는 일단 빼자»)
    -- 값 규칙
    'fee_min',     50000,  -- 기본값 아래로는 못 부른다
    'pin_default', 50000,  -- 안 정하셨으면 이 값에 팔리고 **작가님이 받으신다**
    -- 수수료는 안 뗀다 (대표 «지정하는건 우리가 안가져가는걸로하자»). 길만 살려 둔다
    'cut_pct',     0,
    'cut_max',     0,
    /* 사다리. **촬영·후기·사진 셋을 다** 넘어야 그 단으로 간다.
       1단은 조건이 없다 — 누구나 기본 5만원 */
    'tiers', jsonb_build_array(
      jsonb_build_object('shots',  0, 'reviews',  0, 'gallery',  0, 'cap',   50000),
      jsonb_build_object('shots',  3, 'reviews',  3, 'gallery',  5, 'cap',  100000),
      jsonb_build_object('shots', 10, 'reviews', 10, 'gallery', 20, 'cap',  150000),
      jsonb_build_object('shots', 20, 'reviews', 20, 'gallery', 30, 'cap',  200000),
      -- 맨 윗단은 상한이 없다 («그 이상»). 셈으로는 제약의 천장
      jsonb_build_object('shots', 30, 'reviews', 30, 'gallery', 50, 'cap', 1000000)))
$$;

/* ===== 한 작가가 지금 어디까지 왔나 =====
   ⚠⚠ can_main 을 직접 본다. 대표 2026-08-30 «서브작가만 하는사람은 지정 안됨» —
     문턱이 0 이 되면서 「주작가로 3회」로 걸러지던 것이 풀렸다. 여기서 막는다 */
create or replace function private.pick_eligible(p_staff_id uuid)
returns jsonb language plpgsql stable security definer
set search_path to 'private', 'public', 'pg_temp' as $$
declare
  r jsonb := private.pick_rules();
  today date := (now() at time zone 'Asia/Seoul')::date;
  n_shot int; n_rev int; n_gal int; acc boolean; rep boolean; main boolean;
  okk boolean; capj jsonb;
begin
  select coalesce(st.accepting, true), coalesce(st.is_rep, false), coalesce(st.can_main, true)
    into acc, rep, main
    from public.staff st
   where st.id = p_staff_id and coalesce(st.active, false);
  if not found then raise exception 'staff not found'; end if;

  -- 주작가로 찍은, 지나간, 취소가 아닌 예식 (사다리를 오르는 데 쓴다)
  select count(*)::int into n_shot from public.bookings b
   where b.assignee_id = p_staff_id and b.status <> '취소' and b.wedding_date < today;

  select count(*)::int into n_rev from public.feedback f where f.staff_id = p_staff_id;
  select count(*)::int into n_gal from public.gallery g where g.staff_id = p_staff_id;

  /* 지정을 받을 수 있나 — 이제 셈이 아니라 **둘**이다.
       · 스케줄을 받고 있나 (대표 «자동으로 꺼지면 당연히 지정도 내려가야지»)
       · 메인을 맡을 수 있나 (대표 «서브작가만 하는사람은 지정 안됨»)
     문턱 셋은 0 이라 늘 통과한다 — 남겨 둔 것은 대표가 다시 올리실 수 있어서다 */
  okk := acc and main
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
    'can_main', main,
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

/* ===== 최소 5만원 — 표에도 걸어둔다 =====
   ⚠ 0 은 그대로 받는다. 「지정을 안 받겠다」라는 뜻이다 (기본 5만원도 안 받으신다) */
alter table public.staff drop constraint if exists staff_pick_fee_range;
alter table public.staff add constraint staff_pick_fee_range
  check (pick_fee is null or pick_fee = 0 or (pick_fee >= 50000 and pick_fee <= 1000000));

/* ===== 넣을 때 막는다 — 글귀만 새 최소에 맞춘다 ===== */
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
      raise exception 'not eligible: shots %/% reviews %/% gallery %/% accepting % can_main %',
        e->>'shots', e->>'need_shots', e->>'reviews', e->>'need_reviews',
        e->>'gallery', e->>'need_gallery', e->>'accepting', e->>'can_main';
    end if;
    fee := nullif(p_patch->>'pick_fee','')::int;
    if fee is not null and fee < 0 then raise exception 'bad fee'; end if;
    -- 기본값 아래로는 못 부른다. 0 은 「안 받겠다」라 그대로 받는다
    fmin := (r->>'fee_min')::int;
    if fee is not null and fee > 0 and fee < fmin then
      raise exception '지정 촬영비는 %원부터 정하실 수 있어요 (안 받으시려면 0)',
        to_char(fmin, 'FM999,999,999');
    end if;
    cap := (e->>'fee_cap')::int;
    if fee is not null and fee > cap then
      raise exception '지금 한도는 %원입니다 (촬영 %회·후기 %개·사진 %장). 더 쌓이면 한도가 올라갑니다',
        to_char(cap, 'FM999,999,999'), e->>'shots', e->>'reviews', e->>'gallery';
    end if;
    update public.staff set pick_fee = fee, pick_fee_at = now() where id = p_staff_id;
  end if;

  return public.staff_settings(p_staff_id);
end$$;
revoke all on function public.staff_settings_set(uuid, jsonb) from public;
grant execute on function public.staff_settings_set(uuid, jsonb) to anon, authenticated;
