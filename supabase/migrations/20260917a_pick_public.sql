-- 예약 폼에 「작가 우선순위」와 「작가 지정」을 붙인다 (대표 2026-09-17 «예약 폼 넣자»)
--
-- 지금까지는 미리보기(/pick-sample)만 있었고, 그것도 **관리자 함수**로 자료를 받았다.
-- 예약 폼은 **로그인 전**이라 손님(anon)이 부를 수 있는 함수가 따로 있어야 한다.
--
-- ⚠⚠ **이 저장소는 public 이고, 여기서 여는 것은 아무나 부를 수 있다.**
--   그래서 **최소한만** 낸다 — 이름 · 후기 점수 · 후기 건수 · 갤러리 사진 · 지정비 · 그날 되나.
--   ⚠ 감점은 **순서를 정하는 데만** 쓰고 내보내지 않는다 (대표만 볼 것이다).
--   ⚠ 연락처·정산·손님 이름은 근처에도 안 간다.
--   ⚠⚠ **촬영 후 설문(public.feedback)의 「한마디」는 안 낸다.**
--     대표 «응답은 대표만 열람» — 신부님이 우리에게 적어주신 글이지 밖에 내라고 주신 글이 아니다.
--     미리보기에서는 보였는데, 그건 대표가 보시는 화면이라 관리자 함수로 받은 것이다.
--     손님에게도 후기 글을 보이고 싶으시면 **후기 이벤트(review_post)** 쪽을 쓰거나
--     신부님께 따로 여쭙는 것이 맞다. 대표께 여쭤둔다.
--
-- ⚠ 사진은 이미 공개다 (public.gallery_list 가 anon 이다). 새로 여는 것이 아니다.

/* ===== 예약에 저장할 칸 ===== */
alter table public.bookings add column if not exists pick_wish     uuid[];  -- 우선순위 1·2·3 (차례 그대로)
alter table public.bookings add column if not exists pick_pin      uuid;    -- 지정한 작가 (한 명)
alter table public.bookings add column if not exists pick_fee_won  int;     -- 그때 받은 지정비 (나중에 값이 바뀌어도 남는다)
comment on column public.bookings.pick_wish is
  '신부님이 고른 작가 우선순위 1·2·3. 무료이고 **약속이 아니다** — 「가능한 맞춰드립니다」';
comment on column public.bookings.pick_pin is
  '신부님이 지정한 작가. 돈을 받은 것이라 **바뀌면 안 된다**';
comment on column public.bookings.pick_fee_won is
  '지정비를 그때 얼마로 받았나. 작가가 나중에 금액을 바꿔도 이 값은 안 변한다';

/* ⚠ 셋을 한꺼번에 고를 수는 없다 — 지정을 고르면 우선순위는 비운다 (대표 «자동으로 빠진다»).
     화면에서도 막지만, 서버 표에도 걸어 둔다 */
alter table public.bookings drop constraint if exists bookings_pick_one_way;
alter table public.bookings add constraint bookings_pick_one_way
  check (pick_pin is null or pick_wish is null or cardinality(pick_wish) = 0);

/* ===== 손님이 보는 작가 목록 =====
   p_wedding_date 를 주면 **그날 안 되는 분은 지정에서 뺀다** (대표 2026-09-16 «빼야지»).
   ⚠ 우선순위는 안 뺀다 — 셋 중 하나라 그날 한 분이 막혀도 나머지가 있다
     (대표 «셋중 하나는 되지 않을까?»).
   ⚠ 되는지 여부는 관리자 화면(admin_staff_availability)과 **같은 규칙**으로 본다 —
     두 화면이 다른 말을 하면 안 된다. 다만 **까닭은 안 낸다** (누가 그날 뭘 하는지는 남의 일이다) */
drop function if exists public.pick_staff_list(date);
create or replace function public.pick_staff_list(p_wedding_date date default null)
returns jsonb language sql stable security definer
set search_path to 'public', 'private', 'pg_temp' as $$
  with r as (select private.pick_rules() j),
  base as (
    select s.id, s.name,
      -- 지정비: 안 정했으면 기본값. 0 은 「안 받겠다」라 지정에서 뺀다
      case when s.pick_fee is null then (select (j->>'pin_default')::int from r)
           else s.pick_fee end as fee,
      s.pick_fee as own_fee,
      (select round(avg(private.fb_score(f.*)), 1) from public.feedback f where f.staff_id = s.id) as score,
      (select count(*)::int from public.feedback f where f.staff_id = s.id) as n,
      -- ⚠ 감점은 **줄 세우는 데만** 쓴다. 아래 select 에서 내보내지 않는다
      coalesce((private.penalty_of(s.id)->>'total')::numeric, 0) as pen,
      coalesce((select jsonb_agg(g.image_url order by g.sort, g.id)
                  from (select image_url, sort, id from public.gallery
                         where staff_id = s.id and image_url is not null
                         order by sort, id limit 10) g), '[]'::jsonb) as shots,
      /* 그날 되나 — admin_staff_availability 와 같은 규칙.
         날짜를 안 주면 아무도 안 뺀다 (아직 안 고르신 것이다) */
      (p_wedding_date is null
       or not exists (select 1 from public.staff_busy sb
                       where sb.staff_id = s.id and sb.the_date = p_wedding_date)
      and not exists (select 1 from public.bookings b
                       where (b.assignee_id = s.id or b.sub_assignee_id = s.id)
                         and b.status <> '취소' and b.wedding_date = p_wedding_date)
      ) as free_that_day
    from public.staff s
    where coalesce(s.active, false)
      and coalesce(s.can_main, true)          -- 서브 전용은 안 나온다 (대표 «서브는 빼고»)
      and coalesce(s.accepting, true)          -- 쉬는 중인 분도 안 나온다
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'name', name,
      'fee', fee,
      -- 지정을 고를 수 있나. 0 으로 두신 분은 아예 못 고른다
      'can_pin', (coalesce(own_fee, 1) <> 0) and free_that_day,
      'score', score, 'n', n,
      'shots', shots)
    -- 추천 차례: 감점을 뺀 점수가 높은 순. 평가 없는 분은 뒤로 (만점으로 치지 않는다)
    order by (case when score is null then 1 else 0 end), (coalesce(score, 0) - pen) desc, name)
    , '[]'::jsonb)
  from base;
$$;
revoke all on function public.pick_staff_list(date) from public;
grant execute on function public.pick_staff_list(date) to anon, authenticated;
