-- 예약·매출 — 해마다 한 줄 + 달마다 보는 기간 고르기 (대표 요청 2026-08-24)
--   "매출통계가 월별 년별로도 나중에 집계 되나?" → "이거 가자"
--
--   1) 해마다: 자료가 있는 해마다 건수·매출·작가비·앨범·순이익 한 줄씩.
--      매출은 예식일, 앨범은 발주일 기준이라 달 단위로는 어긋나지만
--      해 단위로는 서로 상쇄된다. 해가 갈수록 이 숫자가 제일 미덥다.
--   2) 달마다 기간: 'now'(지난 6달~앞으로 3달, 기본) · '1y'(앞뒤 1년) · 'all'(자료 전부).
--      예전엔 창이 못 박혀 있어 2027년 9·10월 예식이 아예 안 보였다.
--
-- (아래는 이전 주석)
-- 예약·매출 — 달마다 표에 보여줄 창을 줄인다 (대표 요청 2026-08-24)
--   "일단 홈에보여주는건 지난달 6개월 앞으로 3개월만 보여주면 될거 같아"
--   지난 6달 + 앞으로 12달(19줄) → 지난 6달 + 앞으로 3달(10줄).
--   나머지는 20260824d 정의 그대로다.
--
-- (아래는 원래 주석)
-- 예약·매출 통계 (대표 요청 2026-08-23)
--   "매출과 순이익 뽑으면 좋겠어 / 작가들 비용은 기본 25만원 이고 경기도 출장비는 3만원
--    / 2인 촬영은 15만원 나가 / 대표지정(김병훈) 촬영한거는 모두 순이익
--    / 미배정이랑 수익은 상관없어 언젠가 배정할거라 보수적으로 가자"
--
-- 매출은 예식일 기준으로 그 건의 전체 금액(계약금+잔금)을 그 달에 잡는다.
-- 계약금은 예약할 때 미리 받지만 입금 시각(deposit_paid_at)이 245건 중 5건에만 남아 있어
-- 입금 시점으로는 못 나눈다. 대신 '그 달에 실제로 들어올 돈'은 잔금(총액 - 10만)으로 따로 적는다.
--
-- 앨범 원가를 넣었다 (2026-08-24). 대표:
--   "이건 예약시스템이랑 아예 별도로 해줘 / 여기서 추출할거는 월 나가는 비용만 봐서
--    손익을 계산하면 될거 같은데"
-- 신부가 셀렉을 보내야 작업이 들어가서 예식과 발주 시점이 제각각이다(24년 촬영이 지금
-- 들어오기도 한다). 그래서 예식에 붙이지 않고 «그 달 발주액»을 그 달 비용으로 뺀다.
-- 매출은 예식일 기준, 앨범은 발주일 기준이라 달 하나만 떼어 보면 어긋나 보인다.
-- 해가 지나면 서로 상쇄되니 연 단위 숫자가 제일 미덥다 — 화면에도 그렇게 적어둔다.

create or replace function public.admin_sales(p_span text default 'now')
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c_staff   numeric := 25;    -- 작가 한 명 기본
  c_travel  numeric := 3;     -- 경기도 출장이면 더 나가는 돈
  c_sub     numeric := 15;    -- 2인 촬영 서브 작가
  v_deposit numeric := 10;    -- 계약금(고정)
  kst  date := (now() at time zone 'Asia/Seoul')::date;
  v_span text := case when p_span in ('now', '1y', 'all') then p_span else 'now' end;
  m_lo date;
  m_hi date;
  y_lo date := date_trunc('year', kst)::date;
  y_hi date := (date_trunc('year', kst) + interval '1 year')::date;
  v_album numeric;
  res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;

  -- 달마다 표에 보여줄 창.
  --   now : 지난 6달 ~ 앞으로 3달 (기본. 대표: "지난달 6개월 앞으로 3개월만")
  --   1y  : 앞뒤 1년씩
  --   all : 예식이든 앨범 발주든 자료가 있는 전 기간
  if v_span = 'all' then
    select date_trunc('month', least(
             coalesce((select min(wedding_date) from public.bookings where status <> '취소'), kst),
             coalesce((select min(order_date)   from public.album_orders), kst)))::date,
           date_trunc('month', greatest(
             coalesce((select max(wedding_date) from public.bookings where status <> '취소'), kst),
             coalesce((select max(order_date)   from public.album_orders), kst)))::date
      into m_lo, m_hi;
  elsif v_span = '1y' then
    m_lo := (date_trunc('month', kst) - interval '12 months')::date;
    m_hi := (date_trunc('month', kst) + interval '12 months')::date;
  else
    m_lo := (date_trunc('month', kst) - interval '6 months')::date;
    m_hi := (date_trunc('month', kst) + interval '3 months')::date;
  end if;
  -- 너무 길어지지 않게 (10년치까지)
  if m_hi > (m_lo + interval '10 years')::date then m_hi := (m_lo + interval '10 years')::date; end if;

  -- 올해 넣은 앨범 발주액 (원 → 만원)
  select round(coalesce(sum(total), 0) / 10000.0) into v_album
  from public.album_orders where order_date >= y_lo and order_date < y_hi;

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
  -- 해마다 넣은 앨범 발주 (만원)
  alb_y as (
    select extract(year from order_date)::int as y, sum(total) / 10000.0 as won
    from public.album_orders group by 1
  ),
  -- 그 달에 넣은 앨범 발주. 만원 단위로 맞춘다(발주는 원 단위로 들어 있다)
  alb as (
    select date_trunc('month', order_date) as m, sum(total) / 10000.0 as won
    from public.album_orders group by 1
  ),
  -- 달마다 한 줄. 예식이 없는 달도 0으로 채워 그래프가 끊기지 않게
  mon as (
    select to_char(g.m, 'YYYY-MM') as m,
           coalesce(x.n, 0) as n,
           coalesce(x.rev, 0) as rev,
           coalesce(x.cost, 0) as cost,
           round(coalesce(a.won, 0)) as album,
           coalesce(x.rev, 0) - coalesce(x.cost, 0) - round(coalesce(a.won, 0)) as profit,
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
    left join alb a on a.m = g.m
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
    'span', v_span,
    'from', to_char(m_lo, 'YYYY-MM'), 'to', to_char(m_hi, 'YYYY-MM'),
    'this_m', to_char(kst, 'YYYY-MM'),
    'this_y', extract(year from kst)::int,
    -- 해마다 한 줄. 예식이 있는 해와 앨범 발주가 있는 해를 모두 모은다
    'years', coalesce((select jsonb_agg(t order by t.y desc) from (
        select g.y,
               coalesce(w.n, 0) as n,
               coalesce(w.rev, 0) as rev,
               coalesce(w.cost, 0) as cost,
               round(coalesce(a.won, 0)) as album,
               coalesce(w.rev, 0) - coalesce(w.cost, 0) - round(coalesce(a.won, 0)) as profit,
               coalesce(w.done, 0) as done,
               w.avg as avg
        from (select distinct y from (
                select extract(year from wedding_date)::int y from liv where wedding_date is not null
                union all select y from alb_y) u) g
        left join lateral (
          select count(*) n, sum(total_price) rev, sum(cost) cost,
                 count(*) filter (where wedding_date < kst) done,
                 round(avg(total_price)) avg
          from liv where extract(year from wedding_date)::int = g.y) w on true
        left join alb_y a on a.y = g.y) t), '[]'::jsonb),
    -- 올해 전체. 매출·작가비는 예식일 기준, 앨범은 그 해에 넣은 발주액.
    -- 시점이 서로 다르지만 한 해를 통째로 보면 서로 상쇄돼 이 값이 제일 미덥다.
    'year', (select jsonb_build_object(
        'y', extract(year from kst)::int,
        'n', count(*), 'rev', coalesce(sum(total_price), 0), 'cost', coalesce(sum(cost), 0),
        'album', v_album,
        'profit', coalesce(sum(total_price) - sum(cost), 0) - v_album,
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

-- 인자 없는 옛 정의는 지운다. 안 지우면 둘이 같이 남아 어느 쪽이 불릴지 헷갈린다
drop function if exists public.admin_sales();
revoke all on function public.admin_sales(text) from public, anon;
grant execute on function public.admin_sales(text) to authenticated;
