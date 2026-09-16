-- 「우리 촬영」 수가 옛 이력을 빼먹고 있었다 (대표 2026-09-16)
--   «우리 촬영 많이 한 작가들 있잖아 왜 작가 캘린더에는 제대로 우리 촬영 숫자가 제대로
--     안적혀 있나? 나도 작가 캘린더에는 우리 촬영 25회로 적혀 있는데?»
--
-- 맞다. private.pick_eligible 이 public.bookings 만 세고 있었다.
-- 2026-08-25 에 대표가 캘린더를 주셔서 만든 **지난 촬영 이력(public.staff_history)** 을 안 봤다.
-- 그래서 실제 촬영 수의 한 줌만 세고 있었다.
--
--   대표(김병훈)  예약 25 + 이력 608 = **633회**  (화면에는 25회로 적혀 있었다)
--   양재훈        13 + 446 = 459 · 홍창완 3 + 368 = 371 · 이병호 7 + 359 = 366
--   황지성 13 + 167 = 180 · 황성용 9 + 111 = 120 · 이명철 2 + 95 = 97 · 장길희 1 + 42 = 43
--
-- ⚠ 「내 기록」 칸(public.staff_stats)은 **처음부터 둘을 합쳐** 세고 있었다.
--   그래서 한 화면 안에서 두 숫자가 달랐다. 이제 같은 것을 센다.
--
-- ⚠ **서브로 찍은 것은 안 센다** (대표 2026-08-30 «서브작가만 하는사람은 지정 안됨»).
--   staff_history 에는 as_sub 칸이 있다 — 그것만 빼면 된다.
--   (지금 서브로 찍힌 이력: 양재훈 26 · 황성용 11 · 김주영 10 · 이병호 1 · 이명철 1)

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

  /* 우리와 찍은 횟수 = 예약(지나간 것) + 옛 이력. **주작가로 찍은 것만** 센다.
     ⚠ 「내 기록」 칸(staff_stats)과 같은 자리를 세야 한 화면에서 두 숫자가 안 갈린다 */
  select (select count(*) from public.bookings b
           where b.assignee_id = p_staff_id and b.status <> '취소' and b.wedding_date < today)
       + (select count(*) from public.staff_history h
           where h.staff_id = p_staff_id and not coalesce(h.as_sub, false))
    into n_shot;

  select count(*)::int into n_rev from public.feedback f where f.staff_id = p_staff_id;
  select count(*)::int into n_gal from public.gallery g where g.staff_id = p_staff_id;

  /* 지정을 받을 수 있나 — 쉬는 중이 아니고, 메인을 맡으실 수 있으면 된다.
     문턱 셋은 지금 0 이라 늘 통과한다 (대표 «일단 지정은 기본 5만원») */
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
