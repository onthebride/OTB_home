-- 작가 목록에서 추천을 빼고 차례를 섞는다 (대표 2026-09-17)
--   «작가 우선순위에 추천은 빼자 / 점수순으로 도 놓지 말고 그냥 랜덤으로 하자»
--
-- 지금까지는 후기 점수(감점 뺀 값)가 높은 순으로 세우고 위 셋에 「추천 1·2·3위」를 붙였다.
-- 대표가 그걸 빼자고 하셨다. **누구를 먼저 보여주느냐가 곧 미는 것**이라,
-- 순서를 안 정하는 편이 공정하다. 점수와 건수는 그대로 보여드린다 — 보고 고르시라는 것이다.
--
-- ⚠ 순서를 섞으면서 **감점을 아예 안 본다.** 원래도 밖으로 안 냈지만 이제 셈에서도 빠진다.
--   손님에게 가는 함수에서 민감한 자리를 하나 덜어낸 셈이다.
-- ⚠ `stable` 을 뗀다. random() 은 volatile 이라, stable 로 두면 계획이 굳어
--   같은 차례가 되풀이될 수 있다. 열 때마다 새로 섞여야 한다.
-- ⚠ 새로고침하면 차례가 바뀐다. 그게 이 바꿈의 뜻이다 — 고정된 앞자리를 없애는 것.

drop function if exists public.pick_staff_list(date);
create or replace function public.pick_staff_list(p_wedding_date date default null)
returns jsonb language sql security definer
set search_path to 'public', 'private', 'pg_temp' as $$
  with r as (select private.pick_rules() j),
  base as (
    select s.id, s.name,
      case when s.pick_fee is null then (select (j->>'pin_default')::int from r)
           else s.pick_fee end as fee,
      s.pick_fee as own_fee,
      (select round(avg(private.fb_score(f.*)), 1) from public.feedback f where f.staff_id = s.id) as score,
      (select count(*)::int from public.feedback f where f.staff_id = s.id) as n,
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
    -- ★ 차례는 **섞는다** (대표 2026-09-17 «그냥 랜덤으로 하자»)
    order by random())
    , '[]'::jsonb)
  from base;
$$;
revoke all on function public.pick_staff_list(date) from public;
grant execute on function public.pick_staff_list(date) to anon, authenticated;
