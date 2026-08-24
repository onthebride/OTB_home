-- 서브 작가 별점을 집계에 넣는다 (대표 요청 2026-08-24)
--   설문 문항은 메인 작가에 대한 것이고, 서브는 별점 한 칸을 따로 받는다.
--   두 점수를 섞지 않는다 — 물어본 것이 다르다. 화면에서도 따로 보여준다.
--   나머지는 20260824f 정의 그대로다.
--
-- (아래는 이전 주석)
-- 작가별 «응답률» 추가 (대표 요청 2026-08-24)
--   "작가들 후기작성 안되는것들은 그냥 만점처리 하는게 좋을까?
--    아니면 놔두고 장성된것만 점수화 하는게 변별력이 좋ㄴ?"
--   → 만점 처리는 안 한다. 응답이 0건인 작가가 100점 만점 작가가 되어버린다.
--     (실측: 황성용 7건 찍고 응답 0건, 이명철·김주영·홍창완도 0건)
--     그리고 만점을 채워도 전원 98~100점이라 변별력이 오히려 없어진다.
--   → 대신 응답률을 붙인다. 지금 실제로 벌어지는 건 점수가 아니라 응답률이다.
--     김병훈 38% / 황지성 25% / 양재훈 22% / 이병호 17% / 황성용 0%
--
-- 분모 = 그 작가가 메인으로 찍은 «지난 예식» 중 조회 기간 안의 것.
-- 응답은 낸 시각(created_at) 기준, 대상은 예식일 기준이라 축이 조금 다르다.
-- 설문은 예식 며칠 안에 오니 실무상 문제 없고, 100을 넘지 않게 눌러 둔다.
--
-- 나머지는 2026-08-23 정의 그대로다 (private.fb_score 가중 점수).

create or replace function public.admin_feedback(p_days int default 365)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare n_days int := least(greatest(coalesce(p_days, 365), 1), 3650); res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  with f as (
    select fb.*, private.fb_score(fb.*) as score,
           s.name as staff_name, s2.name as sub_staff_name,
           b.contractor_name, b.bride_name, b.wedding_date, b.wedding_venue
    from public.feedback fb
    join public.bookings b on b.id = fb.booking_id
    left join public.staff s on s.id = fb.staff_id
    left join public.staff s2 on s2.id = fb.sub_staff_id
    where fb.created_at >= now() - (n_days || ' days')::interval
  ),
  -- 서브로 참여해 받은 별점. 메인 점수와 따로 센다 (1~5)
  subq as (
    select coalesce(sub_staff_name, '(이름 없음)') as staff_name,
           count(*) as n, round(avg(sub_stars)::numeric, 1) as avg
    from f where sub_stars is not null group by 1
  ),
  -- 설문을 받을 수 있었던 예식 (분모)
  tgt as (
    select coalesce(s.name, '(배정 없음)') as staff_name, count(*) as n
    from public.bookings b
    left join public.staff s on s.id = b.assignee_id
    where b.status <> '취소' and b.wedding_date is not null
      and b.wedding_date < (now() at time zone 'Asia/Seoul')::date
      and b.wedding_date >= (now() at time zone 'Asia/Seoul')::date - n_days
    group by 1
  )
  select jsonb_build_object(
    'count', (select count(*) from f),
    'avg_overall', (select round(avg(overall)::numeric, 2) from f),
    'avg_family', (select round(avg(family)::numeric, 2) from f),
    'avg_score', (select round(avg(score)::numeric, 1) from f),
    -- 전체 응답률
    'target', (select coalesce(sum(n), 0) from tgt),
    'rate', (select case when coalesce(sum(t.n), 0) = 0 then null
                    else least(100, round(100.0 * (select count(*) from f) / sum(t.n))) end from tgt t),
    -- 묶어서 센 뒤에 분모를 붙인다. 묶는 자리에서 바로 붙이면
    -- count(*) 와 g.n 을 한 줄에 못 써서 «group by 에 있어야 한다» 로 막힌다
    'staff', coalesce((select jsonb_agg(t order by t.avg_score desc nulls last) from (
        select a.*, g.n as target,
               case when coalesce(g.n, 0) = 0 then null
                    else least(100, round(100.0 * a.n / g.n)) end as rate,
               q.n as sub_n, q.avg as sub_avg
        from (
          select coalesce(staff_name, '(배정 없음)') as staff_name,
                 count(*) as n,
                 round(avg(score)::numeric, 1)    as avg_score,
                 round(avg(overall)::numeric, 2)  as avg_overall,
                 round(avg(kindness)::numeric, 2) as avg_kindness,
                 round(avg(requests)::numeric, 2) as avg_requests,
                 round(avg(flow)::numeric, 2)     as avg_flow,
                 round(avg(family)::numeric, 2)   as avg_family,
                 count(*) filter (where arrival <> 'ontime') as late_n,
                 count(*) filter (where issue)               as issue_n,
                 count(*) filter (where next_req is not null) as req_n
          from f group by 1) a
        left join tgt g on g.staff_name = a.staff_name
        left join subq q on q.staff_name = a.staff_name) t), '[]'::jsonb),
    -- 서브로만 참여한 작가는 위 목록에 아예 안 뜬다 (메인 응답이 없어서). 따로 준다
    'subs', coalesce((select jsonb_agg(t order by t.avg desc nulls last) from (
        select q.staff_name, q.n, q.avg from subq q) t), '[]'::jsonb),
    -- 설문이 한 번도 안 온 작가도 보여준다. 만점으로 채우지 않고 «평가 없음» 으로 남긴다 —
    -- 무응답은 «만족» 이 아니라 «모른다» 이고, 안 찍힌 작가가 100점이 되면 그건 거짓 숫자다
    'silent', coalesce((select jsonb_agg(t order by t.n desc) from (
        select g.staff_name, g.n from tgt g
        where not exists (select 1 from f where coalesce(f.staff_name, '(배정 없음)') = g.staff_name)
          and g.staff_name <> '(배정 없음)') t), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(t order by t.created_at desc) from (
        select booking_id, created_at, coalesce(staff_name, '(배정 없음)') as staff_name,
               contractor_name, bride_name, wedding_date, wedding_venue,
               overall, arrival, kindness, requests, flow,
               family, next_req, score,
               sub_staff_name, sub_stars,
               issue, issue_text, message
        from f) t), '[]'::jsonb)
  ) into res;
  return res;
end$fn$;
revoke all on function public.admin_feedback(int) from public, anon;
grant execute on function public.admin_feedback(int) to authenticated;
