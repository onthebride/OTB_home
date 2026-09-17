/* 손님 목록에 「우리와 찍은 횟수」를 적는다 (대표 2026-09-17 «촬영횟수 붙여줘»)

   왜 — 후기는 2026년 8월에야 모으기 시작했다. 그래서 오래 찍어 오신 분도
   「아직 받은 후기가 없어요」로만 보였다. 홍창완 작가는 376회를 찍으셨는데
   화면에는 아무 숫자도 없었다. 그 상태로 두면 손님이 후기 있는 몇 분에게만 몰린다
   (대표 «작가 우선순위를 하면 전부다 몰리겠는데 다른사람들 기회가 영 안오지 않을까?»).

   ⚠⚠ 세는 자리를 private.pick_eligible 과 **똑같이** 맞춘다 —
     지나간 예약(주작가) + 옛 이력(서브 아닌 것). 작가님이 제 캘린더에서 보는 숫자와
     손님이 보는 숫자가 다르면 그 자리에서 믿음이 깨진다.
     (2026-09-16 에 staff_history 를 빼먹어 대표가 633회인데 25회로 나온 적이 있다)

   ⚠ 앞으로 올 예식은 안 센다. 「찍은」 횟수라고 적을 것이라 그렇다.
   ⚠ anon 이 부르는 함수다. 늘어난 칸은 숫자 하나뿐이다 — 이름·연락처는 그대로 안 낸다. */

create or replace function public.pick_staff_list(p_wedding_date date default null)
returns jsonb language sql security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
  with r as (select private.pick_rules() j),
  base as (
    select s.id, s.name,
      case when s.pick_fee is null then (select (j->>'pin_default')::int from r)
           else s.pick_fee end as fee,
      s.pick_fee as own_fee,
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
      'score', score, 'n', n,
      'took', took,
      'shots', shots)
    -- ★ 차례는 **섞는다** (대표 2026-09-17 «그냥 랜덤으로 하자»)
    order by random())
    , '[]'::jsonb)
  from base;
$function$;

grant execute on function public.pick_staff_list(date) to anon, authenticated;
