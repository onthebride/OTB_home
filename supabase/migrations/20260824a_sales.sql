-- 예약·매출 통계 (대표 요청 2026-08-23)
--   "매출과 순이익 뽑으면 좋겠어 / 작가들 비용은 기본 25만원 이고 경기도 출장비는 3만원
--    / 2인 촬영은 15만원 나가 / 대표지정(김병훈) 촬영한거는 모두 순이익
--    / 미배정이랑 수익은 상관없어 언젠가 배정할거라 보수적으로 가자"
--
-- 매출은 예식일 기준으로 그 건의 전체 금액(계약금+잔금)을 그 달에 잡는다.
-- 계약금은 예약할 때 미리 받지만 입금 시각(deposit_paid_at)이 245건 중 5건에만 남아 있어
-- 입금 시점으로는 못 나눈다. 대신 '그 달에 실제로 들어올 돈'은 잔금(총액 - 10만)으로 따로 적는다.
--
-- 앨범 원가는 아직 안 뺀다. 대표가 발주 시스템 자료를 주면 그때 넣는다.

create or replace function public.admin_sales()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c_staff   numeric := 25;    -- 작가 한 명 기본
  c_travel  numeric := 3;     -- 경기도 출장이면 더 나가는 돈
  c_sub     numeric := 15;    -- 2인 촬영 서브 작가
  v_deposit numeric := 10;    -- 계약금(고정)
  kst  date := (now() at time zone 'Asia/Seoul')::date;
  m_lo date := (date_trunc('month', kst) - interval '6 months')::date;
  m_hi date := (date_trunc('month', kst) + interval '12 months')::date;
  y_lo date := date_trunc('year', kst)::date;
  y_hi date := (date_trunc('year', kst) + interval '1 year')::date;
  res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;

  with
  -- 데이터 이전으로 하루에 왕창 들어온 날 — 접수일이 진짜가 아니라서 '언제 예약하나'에서 뺀다
  bulk as (
    select (created_at at time zone 'Asia/Seoul')::date as d
    from public.bookings group by 1 having count(*) >= 15
  ),
  liv as (
    select b.id, b.wedding_date, b.total_price, b.assignee_id, b.line_items,
           (b.created_at at time zone 'Asia/Seoul')::date as made,
           coalesce(nullif(trim(b.wedding_venue), ''), '(안 적힘)') as venue,
           coalesce(s.is_rep, false) as by_rep,
           (case when coalesce(s.is_rep, false) then 0
                 else c_staff + case when b.travel_fee then c_travel else 0 end end)
           + case when exists (
               select 1 from jsonb_array_elements(coalesce(b.line_items, '[]'::jsonb)) li
               where li->>'name' = '2인 촬영') then c_sub else 0 end as cost
    from public.bookings b
    left join public.staff s on s.id = b.assignee_id
    where b.status <> '취소'
  ),
  -- 달마다 한 줄. 예식이 없는 달도 0으로 채워 그래프가 끊기지 않게
  mon as (
    select to_char(g.m, 'YYYY-MM') as m,
           coalesce(x.n, 0) as n,
           coalesce(x.rev, 0) as rev,
           coalesce(x.cost, 0) as cost,
           coalesce(x.rev, 0) - coalesce(x.cost, 0) as profit,
           coalesce(x.rev, 0) - coalesce(x.n, 0) * v_deposit as balance,
           coalesce(x.unassigned, 0) as unassigned,
           coalesce(x.rep_n, 0) as rep_n
    from generate_series(m_lo, m_hi, '1 month') g(m)
    left join lateral (
      select count(*) n, sum(total_price) rev, sum(cost) cost,
             count(*) filter (where assignee_id is null) unassigned,
             count(*) filter (where by_rep) rep_n
      from liv where date_trunc('month', wedding_date) = g.m
    ) x on true
    order by g.m
  ),
  -- 상품(베이직·스페셜)을 뺀 나머지. 값이 마이너스면 할인이라 따로 센다
  opt as (
    select li->>'name' as name, count(*) n, sum((li->>'price')::numeric) rev
    from liv, lateral jsonb_array_elements(coalesce(liv.line_items, '[]'::jsonb)) li
    where li->>'name' not in ('베이직', '스페셜', '베이직(구)')
    group by 1
  ),
  -- 예식장 이름이 제각각이다. "아펠가모 공덕", "공덕 아펠가모 라로브홀" 이 같은 곳이다.
  -- 홀 이름 낱말을 떼고 나머지를 가나다순으로 붙인 것을 같은 곳의 표로 삼는다.
  -- 낱말이 전부 떨어져 나가면(예: "상록아트홀") 원래 이름을 쓴다.
  ven as (
    select venue, total_price, wedding_date,
           coalesce(nullif((
             select string_agg(w, '' order by w)
             from unnest(string_to_array(regexp_replace(lower(venue), '[^[:alnum:]]+', ' ', 'g'), ' ')) w
             where w <> '' and w !~ '(홀|볼룸|층|룸)$'), ''), lower(venue)) as vkey
    from liv
  ),
  -- 예식 몇 달 전에 예약하나. 이전해 온 건은 뺀다
  ld as (
    select (wedding_date - made) as days from liv
    where wedding_date is not null and made not in (select d from bulk)
  ),
  vis as (
    select to_char(ts at time zone 'Asia/Seoul', 'YYYY-MM') m,
           count(distinct coalesce(sid, 'row-' || id::text)) v
    from public.pageviews group by 1
  ),
  made as (
    select to_char(made, 'YYYY-MM') m, count(*) b from liv
    where made not in (select d from bulk) group by 1
  )
  select jsonb_build_object(
    'cost', jsonb_build_object('staff', c_staff, 'travel', c_travel, 'sub', c_sub,
                               'deposit', v_deposit,
                               'rep', (select string_agg(name, ', ') from public.staff where is_rep)),
    'months', coalesce((select jsonb_agg(to_jsonb(mon)) from mon), '[]'::jsonb),
    'this_m', to_char(kst, 'YYYY-MM'),
    -- 올해 전체 (예식일 기준)
    'year', (select jsonb_build_object(
        'y', extract(year from kst)::int,
        'n', count(*), 'rev', coalesce(sum(total_price), 0), 'cost', coalesce(sum(cost), 0),
        'profit', coalesce(sum(total_price) - sum(cost), 0),
        'avg', round(coalesce(avg(total_price), 0)),
        'done', count(*) filter (where wedding_date < kst))
      from liv where wedding_date >= y_lo and wedding_date < y_hi),
    -- 옵션이 매출에서 차지하는 몫 (최근 1년 예식)
    'opt_pct', (select round(100.0 * coalesce(sum(case when li->>'name'
                    not in ('베이직', '스페셜', '베이직(구)') then (li->>'price')::numeric else 0 end), 0)
                  / nullif(sum((li->>'price')::numeric), 0), 1)
                from liv, lateral jsonb_array_elements(coalesce(liv.line_items, '[]'::jsonb)) li
                where liv.wedding_date >= kst - 365),
    'options', coalesce((select jsonb_agg(t) from (
        select name, n, rev from opt where rev > 0 order by rev desc, n desc) t), '[]'::jsonb),
    'discounts', coalesce((select jsonb_agg(t) from (
        select name, n, rev from opt where rev <= 0 order by rev asc, n desc) t), '[]'::jsonb),
    'venues', coalesce((select jsonb_agg(t) from (
        select mode() within group (order by venue) as venue,
               count(*) n, sum(total_price) rev,
               count(*) filter (where wedding_date >= kst) soon,
               count(distinct venue) names
        from ven group by vkey order by count(*) desc, sum(total_price) desc limit 12) t), '[]'::jsonb),
    'lead', (select jsonb_build_object(
        'n', count(*),
        'median', percentile_cont(0.5) within group (order by days)::int,
        'avg', round(avg(days))::int,
        'min', min(days), 'max', max(days),
        'buckets', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
            select k, (select count(*) from ld where days >= lo and days < hi) n
            from (values ('3개월 안', 0, 90), ('3~6개월', 90, 180), ('6~9개월', 180, 270),
                         ('9~12개월', 270, 365), ('1년 넘게', 365, 100000)) v(k, lo, hi)) t))
      from ld),
    'funnel', coalesce((select jsonb_agg(t) from (
        select coalesce(vis.m, made.m) m, vis.v visits, coalesce(made.b, 0) bk,
               round(100.0 * coalesce(made.b, 0) / nullif(vis.v, 0), 1) pct
        from vis full join made on vis.m = made.m
        where vis.v is not null
        order by 1 desc limit 12) t), '[]'::jsonb)
  ) into res;
  return res;
end; $$;

revoke all on function public.admin_sales() from public, anon;
grant execute on function public.admin_sales() to authenticated;
