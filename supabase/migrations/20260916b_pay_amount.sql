-- 작가비 카드에 「얼마를 드려야 하나」를 적는다 (대표 2026-09-16)
--   «관리자 홈에 내가 작가비 입금 확인하는카드 있잖아? 거기에 얼마를 입금해야하는지 적어달라고
--     메인 25 서브 15 출장비 있으면 3만원 더해주고»
--
-- 지금 카드에는 «메인 황지성 · 신부/신랑 · 날짜» 만 있고 **금액이 없다.**
-- 대표가 송금하실 때 머리로 다시 세셔야 했다.
--
-- ⚠ 값은 **새로 정하는 것이 아니다.** 매출 계산(admin_sales)이 이미 같은 수로 원가를 잡고 있다
--   (`20260824a_sales.sql` 의 c_staff 25 · c_travel 3 · c_sub 15).
--   두 화면이 다른 수를 말하면 안 되니 **한 곳에 모아두고 여기서 가져다 쓴다.**
--   ⚠⚠ admin_sales 쪽은 아직 제 안에 그 수를 그대로 들고 있다 (여러 판에 걸쳐 있어 이번에
--     건드리지 않았다). **작가비를 바꾸실 때는 두 곳을 같이 고쳐야 한다** —
--     private.staff_pay_rule() 과 admin_sales 계열(20260824a·d·h·i).
--
-- ⚠ 출장비는 **메인에게만** 붙인다. admin_sales 가 그렇게 세고 있어 그대로 맞춘다
--   (2인 촬영이면 손님은 출장비 10만원을 내신다 — 서브에게도 3만원을 드려야 하면
--    아래 한 줄만 고치면 된다. 대표께 여쭤둔 것이다)

/* ===== 작가비 한 곳에서 =====
   ⚠ 만원이 아니라 **원**으로 둔다. 화면에서 만원으로 줄여 적더라도 셈은 원으로 한다 */
create or replace function private.staff_pay_rule()
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'main',   250000,   -- 메인 작가
    'sub',    150000,   -- 서브 작가 (2인 촬영)
    'travel',  30000)   -- 경기 출장. 지금은 메인에게만 붙는다
$$;
revoke all on function private.staff_pay_rule() from public, anon, authenticated;

/* ===== 밀린 작가비에 금액을 같이 준다 =====
   ⚠ 칸을 더하므로 drop 을 같이 쓴다 — 안 그러면 «returns 가 다르다» 로 터진다.
     부르는 쪽(public.admin_pay_overdue · private.pay_overdue_notify)은 plpgsql 이라
     다시 만들 것 없이 새 칸을 그대로 받는다 (to_jsonb(t) · t.*) */
drop function if exists private.pay_overdue(int, date);
create or replace function private.pay_overdue(p_days int default 7, p_since date default null)
returns table (booking_id uuid, contractor_name text, bride_name text, groom_name text,
               wedding_date date, role text, staff_id uuid, staff_name text, days_over int,
               pay_won int, travel_won int)
language sql stable security definer set search_path = public, pg_temp as $$
  /* ⚠ 세기 시작한 날. 그 앞의 예식은 «안 줬다» 가 아니라 **우리가 안 적어둔 것**이다.
       이 줄이 없으면 첫날부터 55건이 밀린 것으로 잡혀 헛경보가 나간다.
       (자동 멈춤 때 «접속기록은 오늘부터 다시 재» 와 같은 까닭이다)
     ⚠ 체크는 옛 예약에도 할 수 있다. 여기서 막는 것은 **알림**뿐이다. */
  with r as (select private.staff_pay_rule() j),
  x as (
    select b.id, b.contractor_name, b.bride_name, b.groom_name, b.wedding_date,
           '메인'::text as role, b.assignee_id as sid, b.main_pay_at as pay_at,
           -- 출장비는 메인에게만 (admin_sales 와 같은 규칙)
           (case when coalesce(b.travel_fee, false) then (select (j->>'travel')::int from r) else 0 end) as tw,
           (select (j->>'main')::int from r) as base
      from public.bookings b
     where b.status <> '취소' and b.assignee_id is not null
    union all
    select b.id, b.contractor_name, b.bride_name, b.groom_name, b.wedding_date,
           '서브', b.sub_assignee_id, b.sub_pay_at,
           0, (select (j->>'sub')::int from r)
      from public.bookings b
     where b.status <> '취소' and b.sub_assignee_id is not null
  )
  select x.id, x.contractor_name, x.bride_name, x.groom_name, x.wedding_date,
         x.role, x.sid, st.name,
         ((now() at time zone 'Asia/Seoul')::date - x.wedding_date - p_days)::int,
         (x.base + x.tw)::int, x.tw::int
    from x join public.staff st on st.id = x.sid
   where x.pay_at is null
     and x.wedding_date <= (now() at time zone 'Asia/Seoul')::date - p_days
     and x.wedding_date >= coalesce(p_since, date '2026-09-03')
   order by x.wedding_date, x.role;
$$;
revoke all on function private.pay_overdue(int, date) from public, anon, authenticated;
