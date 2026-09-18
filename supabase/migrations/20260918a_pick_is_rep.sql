/* 지정 목록에 「(대표)」 표시를 달 수 있게 한다 (대표 2026-09-18
     «작가 지정에만 내이름 옆에 (대표) 라고 적어줘»)

   같은 판에서 홈 가격 안내의 「대표 작가를 지정하시면 : …」 줄도 내린다
   (대표 «여기 대표작가지정 옵션은 이제 없으니까 빼고»).
   대표님은 이제 지정 목록 안에 계신다 — 밖에 따로 적어둘 자리가 아니다.

   ⚠ 우선순위 목록에는 대표님이 안 나온다(2026-09-17). 그래서 이 표시는 지정에서만 보인다.
   ⚠ anon 이 부르는 함수다. 늘어난 칸은 참/거짓 하나뿐이다.

   이 파일은 살아 있는 정의를 읽어와 한 군데만 갈아 끼운 것이다 (_isrep_patch.mjs). */
CREATE OR REPLACE FUNCTION public.pick_staff_list(p_wedding_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
  with r as (select private.pick_rules() j),
  base as (
    select s.id, s.name,
      case when s.pick_fee is null then (select (j->>'pin_default')::int from r)
           else s.pick_fee end as fee,
      s.pick_fee as own_fee,
      coalesce(s.is_rep, false) as is_rep,
      (select round(avg(private.fb_score(f.*)), 1) from public.feedback f where f.staff_id = s.id) as score,
      (select count(*)::int from public.feedback f where f.staff_id = s.id) as n,
      /* 우리와 찍은 횟수 — private.pick_eligible 의 n_shot 과 같은 셈이다 */
      ((select count(*) from public.bookings b
         where b.assignee_id = s.id and b.status <> '취소'
           and b.wedding_date < (now() at time zone 'Asia/Seoul')::date)
     + (select count(*) from public.staff_history h
         where h.staff_id = s.id and not coalesce(h.as_sub, false)))::int as took,
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
      /* 우선순위로 고를 수 있나 — 대표는 빠진다 (대표 2026-09-17 «우선순위에사 나는 빼자»).
         앞으로 오는 예식의 43%를 이미 맡고 계셔서 무료 1순위까지 받으면 더 쏠린다.
         그리고 홈 글이 «대표 지정의 차이는 확정에 있습니다» 라고 말한다 —
         대표님을 원하시면 지정으로 확정하시는 것이 원래 이야기다.
         ⚠ 지정(can_pin)에서는 안 뺀다. 아무것도 안 고르신 손님께는 그대로 랜덤 배정된다 */
      'can_wish', not is_rep,
      /* 지정 목록에서 이름 옆에 「(대표)」를 적는다 (대표 2026-09-18
         «작가 지정에만 내이름 옆에 (대표) 라고 적어줘»).
         ⚠ 우선순위 목록에는 대표님이 안 나오니 이 표시는 지정에서만 보인다 */
      'is_rep', is_rep,
      'score', score, 'n', n,
      'took', took,
      'shots', shots)
    -- ★ 차례는 **섞는다** (대표 2026-09-17 «그냥 랜덤으로 하자»)
    order by random())
    , '[]'::jsonb)
  from base;
$function$
;

grant execute on function public.pick_staff_list(date) to anon, authenticated;
