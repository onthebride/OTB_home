-- 출장비는 서브 작가에게도 나간다 (대표 2026-09-16)
--   «서브도 3만원 나감»
--
-- 바로 앞(20260916b)에서 출장비를 **메인에게만** 붙였다. 매출 계산(admin_sales)이
-- 그렇게 세고 있어서 그대로 맞춘 것이고, 맞는지 대표께 여쭈었다. 아니었다.
-- 2인 촬영에 경기 출장이면 손님이 출장비 10만원을 내시고(`booking.html:177` 5만 × 2인),
-- **두 분 다 가시니 두 분 다 3만원씩 나간다.**
--
-- ⚠⚠ **같은 잘못이 매출 계산에도 있다.** `admin_sales` 계열(20260824a·d·h·i)은
--   서브 원가를 15만원 고정으로 잡고 출장비를 안 얹는다. 그래서 2인 촬영 + 경기 출장인
--   예식마다 **순이익이 3만원씩 실제보다 높게** 잡혀 있다.
--   여기서는 안 고쳤다 — 고치면 **지난 달들의 순이익 숫자가 내려간다.** 대표께 여쭙고 따로 한다.

create or replace function private.pay_overdue(p_days int default 7, p_since date default null)
returns table (booking_id uuid, contractor_name text, bride_name text, groom_name text,
               wedding_date date, role text, staff_id uuid, staff_name text, days_over int,
               pay_won int, travel_won int)
language sql stable security definer set search_path = public, pg_temp as $$
  /* ⚠ 세기 시작한 날. 그 앞의 예식은 «안 줬다» 가 아니라 **우리가 안 적어둔 것**이다.
       이 줄이 없으면 첫날부터 55건이 밀린 것으로 잡혀 헛경보가 나간다.
     ⚠ 체크는 옛 예약에도 할 수 있다. 여기서 막는 것은 **알림**뿐이다. */
  with r as (select private.staff_pay_rule() j),
  x as (
    select b.id, b.contractor_name, b.bride_name, b.groom_name, b.wedding_date,
           '메인'::text as role, b.assignee_id as sid, b.main_pay_at as pay_at,
           (case when coalesce(b.travel_fee, false) then (select (j->>'travel')::int from r) else 0 end) as tw,
           (select (j->>'main')::int from r) as base
      from public.bookings b
     where b.status <> '취소' and b.assignee_id is not null
    union all
    select b.id, b.contractor_name, b.bride_name, b.groom_name, b.wedding_date,
           '서브', b.sub_assignee_id, b.sub_pay_at,
           -- 대표 2026-09-16 «서브도 3만원 나감». 두 분 다 가시니 두 분 다 받으신다
           (case when coalesce(b.travel_fee, false) then (select (j->>'travel')::int from r) else 0 end),
           (select (j->>'sub')::int from r)
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
