-- 앨범 발주 (대표 요청 2026-08-24)
--   "내가 앨범 발주 넣는 시스템이 있거든? 그거 넣고 싶은데"
--   "이건 예약시스템이랑 아예 별도로 해줘 / 내가 하려는 이유는 순익을 좀 더 정확하게
--    계산하기 위해서야 / 여기서 추출할거는 월 나가는 비용만 봐서 손익을 계산하면 될거 같은데"
--
-- 예약(bookings)과 잇지 않는다. 신부가 셀렉을 보내야 작업이 들어가서 예식과 발주 시점이
-- 제각각이고(24년 촬영이 지금 들어오기도 한다), 억지로 이으면 오히려 틀린다.
-- 손익에는 «그 달 발주액»을 그 달 비용으로 넣는다.
--
-- 넘겨받은 사양서(이관패키지/HANDOFF.md)의 규칙을 그대로 지킨다:
--   · 라인의 이름·단가는 발주 시점 스냅샷 — 단가표와 조인하지 않는다
--   · 금액은 전부 정수(원). 소수·부가세 개념 없음
--   · 날짜는 DATE. timestamptz 로 두면 월말 발주가 이전 달로 밀린다
--   · check 형 항목은 수량이 언제나 1
--   · total 은 서버가 라인 합계로 다시 계산한다 (클라이언트 값을 믿지 않는다)
--
-- 원본 이름이 orders 였지만 우리 예약(bookings)과 헷갈려서 album_ 을 붙였다.

-- ── 1. 단가 ──────────────────────────────────────────────────
create table if not exists public.album_price_items (
  id          text primary key,
  name        text    not null,
  unit        integer not null default 0 check (unit >= 0),
  type        text    not null check (type in ('check', 'qty')),
  sort_order  integer not null default 0,
  active      boolean not null default true,      -- 지워도 과거 발주가 살아 있어야 해서 끄기만 한다
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists idx_album_price_sort on public.album_price_items (active, sort_order);

-- ── 2. 발주 ──────────────────────────────────────────────────
create table if not exists public.album_orders (
  id          text primary key,
  customer    text    not null check (btrim(customer) <> ''),
  order_date  date    not null,
  paid        boolean not null default false,
  total       integer not null default 0,          -- 라인 합계 (쓸 때마다 다시 계산)
  memo        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists idx_album_orders_date on public.album_orders (order_date desc, created_at desc);
create index if not exists idx_album_orders_paid on public.album_orders (paid);
create index if not exists idx_album_orders_cust on public.album_orders (lower(customer) text_pattern_ops);
-- 달로 뽑는 인덱스는 만들지 않는다. to_char(date,…) 가 immutable 이 아니라 인덱스가 못 만들어진다.
-- 달 조회는 order_date 범위로 하며 위의 날짜 인덱스가 그대로 먹는다.

-- ── 3. 발주 라인 (원본의 items + extras 를 한 표로) ──────────
create table if not exists public.album_order_lines (
  id            bigserial primary key,
  order_id      text    not null references public.album_orders(id) on delete cascade,
  price_item_id text    references public.album_price_items(id) on delete set null,
  name          text    not null,                  -- ★ 발주 시점 이름
  unit          integer not null check (unit >= 0),-- ★ 발주 시점 단가
  qty           integer not null check (qty > 0),
  kind          text    not null check (kind in ('item', 'extra')),
  item_type     text    not null check (item_type in ('check', 'qty')),
  sort_order    integer not null default 0,
  constraint chk_album_check_qty  check (item_type <> 'check' or qty = 1),
  constraint chk_album_extra_ref  check (kind <> 'extra' or price_item_id is null)
);
create index if not exists idx_album_lines_order on public.album_order_lines (order_id, sort_order);
create index if not exists idx_album_lines_price on public.album_order_lines (price_item_id);

-- 바깥에서 표를 직접 못 만진다. 아래 함수로만 드나든다
alter table public.album_price_items enable row level security;
alter table public.album_orders      enable row level security;
alter table public.album_order_lines enable row level security;
revoke all on public.album_price_items from anon, authenticated;
revoke all on public.album_orders      from anon, authenticated;
revoke all on public.album_order_lines from anon, authenticated;


-- ═══ 단가 ═══════════════════════════════════════════════════
create or replace function public.admin_album_prices(p_all boolean default false)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  return coalesce((select jsonb_agg(t) from (
    select id, name, unit, type, sort_order, active
    from public.album_price_items
    where p_all or active
    order by sort_order, created_at) t), '[]'::jsonb);
end; $$;

-- 넣기·고치기 둘 다. p_id 가 없으면 새로 만든다
create or replace function public.admin_album_price_save(
  p_id text, p_name text, p_unit integer, p_type text, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id text; v_next int;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_type is null or p_type not in ('check', 'qty') then raise exception '상품 종류가 잘못됐습니다'; end if;
  if coalesce(p_unit, 0) < 0 then raise exception '단가는 0보다 작을 수 없습니다'; end if;

  if p_id is null then
    select coalesce(max(sort_order), -1) + 1 into v_next from public.album_price_items;
    v_id := replace(gen_random_uuid()::text, '-', '');
    insert into public.album_price_items (id, name, unit, type, sort_order)
    values (v_id, coalesce(nullif(btrim(p_name), ''), '이름 없음'), coalesce(p_unit, 0), p_type, v_next);
  else
    v_id := p_id;
    update public.album_price_items
       set name = coalesce(nullif(btrim(p_name), ''), name),
           unit = coalesce(p_unit, unit),
           type = coalesce(p_type, type),
           active = coalesce(p_active, active),
           updated_at = now()
     where id = v_id;
    if not found then raise exception '없는 항목입니다'; end if;
  end if;
  return (select to_jsonb(t) from (
    select id, name, unit, type, sort_order, active from public.album_price_items where id = v_id) t);
end; $$;

-- 지우지 않고 끈다. 과거 발주가 이름·단가를 스스로 갖고 있어 금액은 그대로 남는다
create or replace function public.admin_album_price_off(p_id text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.album_price_items set active = false, updated_at = now() where id = p_id;
  if not found then raise exception '없는 항목입니다'; end if;
  return jsonb_build_object('ok', true);
end; $$;

create or replace function public.admin_album_price_order(p_ids text[])
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.album_price_items p set sort_order = x.i - 1, updated_at = now()
    from unnest(p_ids) with ordinality as x(id, i) where p.id = x.id;
  return jsonb_build_object('ok', true);
end; $$;


-- ═══ 발주 ═══════════════════════════════════════════════════
-- p_month: 'YYYY-MM' | 'YYYY' | 'all'   p_paid: 'all' | 'paid' | 'unpaid'
create or replace function public.admin_album_orders(
  p_month text default 'all', p_paid text default 'all', p_q text default null, p_limit int default 400)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare d_lo date; d_hi date; res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;

  if p_month ~ '^[0-9]{4}-[0-9]{2}$' then
    d_lo := (p_month || '-01')::date;  d_hi := (d_lo + interval '1 month')::date;
  elsif p_month ~ '^[0-9]{4}$' then
    d_lo := (p_month || '-01-01')::date;  d_hi := (d_lo + interval '1 year')::date;
  end if;

  -- 합계는 «거른 것 전부», 목록은 «앞에서 몇 건». 둘을 나눠 두지 않으면
  -- 합계가 보이는 만큼만 더해져 아래 합계 줄이 거짓말을 한다
  with flt as (
    select o.* from public.album_orders o
    where (d_lo is null or (o.order_date >= d_lo and o.order_date < d_hi))
      and (p_paid = 'all' or p_paid is null or (p_paid = 'paid') = o.paid)
      and (nullif(btrim(coalesce(p_q, '')), '') is null
           or lower(o.customer) like '%' || lower(btrim(p_q)) || '%')
  ),
  pick as (
    select * from flt
    order by order_date desc, created_at desc
    limit least(greatest(coalesce(p_limit, 400), 1), 2000)
  )
  select jsonb_build_object(
    'count', (select count(*) from flt),
    'total', (select coalesce(sum(total), 0) from flt),
    'paid',  (select coalesce(sum(total) filter (where paid), 0) from flt),
    'shown', (select count(*) from pick),
    'items', coalesce((select jsonb_agg(t order by t.order_date desc, t.created_at desc) from (
      select p.id, p.customer, p.order_date, p.paid, p.total, p.memo, p.created_at,
             coalesce((select jsonb_agg(l order by l.sort_order, l.lid) from (
               select id lid, sort_order, name, unit, qty, kind, item_type, price_item_id
               from public.album_order_lines where order_id = p.id) l), '[]'::jsonb) as lines
      from pick p) t), '[]'::jsonb),
    -- 달 탭을 그리려면 자료가 있는 달을 알아야 한다 (거른 것과 무관하게 전부)
    'months', coalesce((select jsonb_agg(m order by m desc) from (
      select distinct to_char(order_date, 'YYYY-MM') m from public.album_orders) x), '[]'::jsonb)
  ) into res;
  return res;
end; $$;

-- 넣기·고치기 한 함수로. p_id 가 있으면 «제자리 수정» —
-- 원본은 지우고 새로 넣는 방식이라 결제완료가 풀리고 id 가 바뀌었다. 그 버릇을 여기서 끊는다.
create or replace function public.admin_album_order_save(
  p_id text, p_customer text, p_date date, p_lines jsonb, p_memo text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id text; li jsonb; i int := 0; v_total int := 0;
  v_name text; v_unit int; v_type text; v_qty int; v_kind text; v_pid text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if nullif(btrim(coalesce(p_customer, '')), '') is null then raise exception '고객 이름을 적어주세요'; end if;
  if p_date is null then raise exception '발주 날짜를 골라주세요'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception '상품을 하나 이상 고르세요';
  end if;

  if p_id is null then
    v_id := replace(gen_random_uuid()::text, '-', '');
    insert into public.album_orders (id, customer, order_date, memo)
    values (v_id, btrim(p_customer), p_date, nullif(btrim(coalesce(p_memo, '')), ''));
  else
    v_id := p_id;
    update public.album_orders
       set customer = btrim(p_customer), order_date = p_date,
           memo = nullif(btrim(coalesce(p_memo, '')), ''), updated_at = now()
     where id = v_id;                              -- paid · created_at 은 건드리지 않는다
    if not found then raise exception '없는 발주입니다'; end if;
    delete from public.album_order_lines where order_id = v_id;
  end if;

  for li in select * from jsonb_array_elements(p_lines) loop
    v_kind := coalesce(li->>'kind', 'item');
    v_qty  := coalesce((li->>'qty')::int, 0);
    if v_qty <= 0 then continue; end if;           -- 0개는 담지 않는다

    if v_kind = 'item' then
      -- 이름·단가는 클라이언트 말을 믿지 않고 단가표에서 떠온다 (금액 장난 방지)
      v_pid := li->>'price_item_id';
      select name, unit, type into v_name, v_unit, v_type
        from public.album_price_items where id = v_pid;
      if v_name is null then raise exception '없는 상품입니다'; end if;
    else
      v_pid  := null;
      v_name := coalesce(nullif(btrim(coalesce(li->>'name', '')), ''), '기타');
      v_unit := greatest(coalesce((li->>'unit')::int, 0), 0);
      v_type := 'qty';
    end if;

    if v_type = 'check' then v_qty := 1; end if;   -- 체크형은 언제나 1개
    insert into public.album_order_lines
      (order_id, price_item_id, name, unit, qty, kind, item_type, sort_order)
    values (v_id, v_pid, v_name, v_unit, v_qty, v_kind, v_type, i);
    v_total := v_total + v_unit * v_qty;
    i := i + 1;
  end loop;

  if i = 0 then raise exception '상품을 하나 이상 고르세요'; end if;
  update public.album_orders set total = v_total, updated_at = now() where id = v_id;
  return jsonb_build_object('id', v_id, 'total', v_total);
end; $$;

create or replace function public.admin_album_order_paid(p_id text, p_paid boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.album_orders set paid = coalesce(p_paid, false), updated_at = now() where id = p_id;
  if not found then raise exception '없는 발주입니다'; end if;
  return jsonb_build_object('ok', true);
end; $$;

create or replace function public.admin_album_order_del(p_id text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  delete from public.album_orders where id = p_id;                 -- 라인은 함께 지워진다
  if not found then raise exception '없는 발주입니다'; end if;
  return jsonb_build_object('ok', true);
end; $$;


-- ═══ 통계 ═══════════════════════════════════════════════════
create or replace function public.admin_album_stats(p_month text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m text; d_lo date; d_hi date; res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  m := case when p_month ~ '^[0-9]{4}-[0-9]{2}$' then p_month
            else to_char((now() at time zone 'Asia/Seoul')::date, 'YYYY-MM') end;
  d_lo := (m || '-01')::date;  d_hi := (d_lo + interval '1 month')::date;

  select jsonb_build_object(
    'month', m,
    'sum', (select jsonb_build_object(
        'total',  coalesce(sum(total), 0),
        'paid',   coalesce(sum(total) filter (where paid), 0),
        'unpaid', coalesce(sum(total) filter (where not paid), 0),
        'count',  count(*), 'people', count(distinct customer))
      from public.album_orders where order_date >= d_lo and order_date < d_hi),
    'by_month', coalesce((select jsonb_agg(t order by t.m desc) from (
        select to_char(order_date, 'YYYY-MM') m, count(*) n,
               sum(total) total,
               coalesce(sum(total) filter (where paid), 0) paid,
               coalesce(sum(total) filter (where not paid), 0) unpaid
        from public.album_orders group by 1) t), '[]'::jsonb),
    -- 그 달 항목별. 기타는 이름 뒤에 «(기타)» 를 붙이고 이름으로 묶는다
    'by_item', coalesce((select jsonb_agg(t order by t.total desc, t.qty desc) from (
        select l.name || case when l.kind = 'extra' then ' (기타)' else '' end nm,
               sum(l.qty)::int qty, sum(l.unit * l.qty)::int total
        from public.album_order_lines l join public.album_orders o on o.id = l.order_id
        where o.order_date >= d_lo and o.order_date < d_hi
        group by 1) t), '[]'::jsonb)
  ) into res;
  return res;
end; $$;

do $$
declare f text;
begin
  foreach f in array array[
    'admin_album_prices(boolean)', 'admin_album_price_save(text,text,integer,text,boolean)',
    'admin_album_price_off(text)', 'admin_album_price_order(text[])',
    'admin_album_orders(text,text,text,integer)',
    'admin_album_order_save(text,text,date,jsonb,text)',
    'admin_album_order_paid(text,boolean)', 'admin_album_order_del(text)',
    'admin_album_stats(text)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
