-- 작가 입금(작가비 지급) 체크 (대표 2026-09-03)
--   «캘린더에 날짜누르면 나오는 스케줄 목록 카드에 작가들 입금 했는지 체크 하게 해줘
--     그리고 일주일 넘게 입금체크가 안되면 나한테 알려줘
--     서브 메인 둘다 체크하게 해줘»
--
-- ⚠ 「입금」이 두 가지라 헷갈리기 쉽다. 여기 것은 **우리가 작가에게 주는 돈**이다.
--   손님이 우리에게 넣는 계약금·잔금(deposit_paid·balance_paid)과 다른 것이다.
--   그래서 이름을 pay_ 로 시작한다.
--
-- ⚠ 준 사람을 같이 적어둔다(pay_to). 준 뒤에 배정을 바꾸시면 «다른 사람에게 준 것»이
--   되는데, 그것을 알아볼 수 있어야 한다. 적어두지 않으면 준 적 없는 사람이
--   받은 것처럼 보인다.

alter table public.bookings add column if not exists main_pay_at timestamptz;
alter table public.bookings add column if not exists main_pay_to uuid references public.staff(id);
alter table public.bookings add column if not exists sub_pay_at  timestamptz;
alter table public.bookings add column if not exists sub_pay_to  uuid references public.staff(id);

-- 아직 안 준 것을 자주 찾는다. 그 줄만 추린다
create index if not exists bookings_pay_todo
  on public.bookings (wedding_date) where main_pay_at is null or sub_pay_at is null;

/* ===== 켜고 끄기 =====
   ⚠ 되돌릴 수 있어야 한다. 잘못 눌렀는데 못 되돌리면 그 줄은 영영 틀린 채로 남는다 */
drop function if exists public.admin_mark_pay(uuid, text, boolean);
create or replace function public.admin_mark_pay(p_id uuid, p_role text, p_on boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare b public.bookings;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_role not in ('메인', '서브') then raise exception 'bad role'; end if;

  select * into b from public.bookings where id = p_id;
  if not found then raise exception 'booking not found'; end if;

  if p_role = '메인' then
    -- ⚠ 배정이 없으면 줄 사람이 없다. 그런데도 켜면 나중에 누구에게 준 건지 모른다
    if p_on and b.assignee_id is null then raise exception '메인 작가가 배정되지 않았습니다'; end if;
    update public.bookings
       set main_pay_at = case when p_on then now() end,
           main_pay_to = case when p_on then b.assignee_id end
     where id = p_id;
  else
    if p_on and b.sub_assignee_id is null then raise exception '서브 작가가 배정되지 않았습니다'; end if;
    update public.bookings
       set sub_pay_at = case when p_on then now() end,
           sub_pay_to = case when p_on then b.sub_assignee_id end
     where id = p_id;
  end if;

  select * into b from public.bookings where id = p_id;
  return to_jsonb(b);
end$$;
revoke all on function public.admin_mark_pay(uuid, text, boolean) from public, anon;
grant execute on function public.admin_mark_pay(uuid, text, boolean) to authenticated;

/* ===== 일주일 넘게 안 준 것 =====
   대표 «일주일 넘게 입금체크가 안되면 나한테 알려줘».
   ⚠ 「예식이 끝난 지 일주일」이다. 예식 전에는 줄 일이 없다.
   ⚠ 배정된 사람만 센다. 미배정은 줄 사람이 없으니 여기 낄 것이 아니다.
   ⚠ 취소된 예식은 뺀다. */
drop function if exists private.pay_overdue(int);
drop function if exists private.pay_overdue(int, date);
create or replace function private.pay_overdue(p_days int default 7, p_since date default null)
returns table (booking_id uuid, contractor_name text, wedding_date date,
               role text, staff_id uuid, staff_name text, days_over int)
language sql stable security definer set search_path = public, pg_temp as $$
  /* ⚠ 세기 시작한 날. 그 앞의 예식은 «안 줬다» 가 아니라 **우리가 안 적어둔 것**이다.
       이 줄이 없으면 첫날부터 55건이 밀린 것으로 잡혀 헛경보가 나간다.
       (자동 멈춤 때 «접속기록은 오늘부터 다시 재» 와 같은 까닭이다)
     ⚠ 체크는 옛 예약에도 할 수 있다. 여기서 막는 것은 **알림**뿐이다. */
  with x as (
    select b.id, b.contractor_name, b.wedding_date,
           '메인'::text as role, b.assignee_id as sid, b.main_pay_at as pay_at
      from public.bookings b
     where b.status <> '취소' and b.assignee_id is not null
    union all
    select b.id, b.contractor_name, b.wedding_date,
           '서브', b.sub_assignee_id, b.sub_pay_at
      from public.bookings b
     where b.status <> '취소' and b.sub_assignee_id is not null
  )
  select x.id, x.contractor_name, x.wedding_date, x.role, x.sid, st.name,
         ((now() at time zone 'Asia/Seoul')::date - x.wedding_date - p_days)::int
    from x join public.staff st on st.id = x.sid
   where x.pay_at is null
     and x.wedding_date <= (now() at time zone 'Asia/Seoul')::date - p_days
     and x.wedding_date >= coalesce(p_since, date '2026-09-03')
   order by x.wedding_date, x.role;
$$;
revoke all on function private.pay_overdue(int, date) from public, anon, authenticated;

-- 대표 화면에서 보는 목록 (2026-09-03 «홈화면에 작가 입금 처리 목록을 따로 줘»)
-- ⚠ 목록과 알림의 범위가 다르다. 목록은 옛것까지 다 보여야 처리를 하실 수 있고,
--   알림은 9/3 부터여야 첫날 헛경보(55건)가 안 난다. 그래서 p_since 를 밖으로 뺀다.
drop function if exists public.admin_pay_overdue(int);
drop function if exists public.admin_pay_overdue(int, date);
create or replace function public.admin_pay_overdue(p_days int default 7, p_since date default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(t) order by t.wedding_date, t.role), '[]'::jsonb)
            from private.pay_overdue(p_days, p_since) t);
end$$;
revoke all on function public.admin_pay_overdue(int, date) from public, anon;
grant execute on function public.admin_pay_overdue(int, date) to authenticated;

/* ===== 하루 한 번 알린다 =====
   ⚠ 매번 다 알리면 시끄럽다. **어제 없던 것만** 알린다 —
     그러려면 무엇을 알렸는지 적어둬야 한다 */
create table if not exists private.pay_alert_sent (
  booking_id uuid not null,
  role       text not null,
  at         timestamptz not null default now(),
  primary key (booking_id, role)
);

create or replace function private.pay_overdue_notify()
returns jsonb language plpgsql security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp' as $$
declare n int := 0; tot int; r record; lines text := '';
begin
  select count(*) into tot from private.pay_overdue(7, null);

  for r in
    select t.* from private.pay_overdue(7, null) t
     where not exists (select 1 from private.pay_alert_sent s
                        where s.booking_id = t.booking_id and s.role = t.role)
     order by t.wedding_date limit 5
  loop
    lines := lines || E'\n' || to_char(r.wedding_date, 'FMMM/FMDD') || ' '
          || coalesce(r.contractor_name, '') || ' · ' || r.role || ' ' || coalesce(r.staff_name, '');
    insert into private.pay_alert_sent(booking_id, role) values (r.booking_id, r.role)
      on conflict (booking_id, role) do nothing;
    n := n + 1;
  end loop;

  -- 준 것으로 바뀌었으면 적어둔 것을 지운다. 나중에 다시 밀리면 또 알려야 한다
  delete from private.pay_alert_sent s
   where not exists (select 1 from private.pay_overdue(7, null) t
                      where t.booking_id = s.booking_id and t.role = s.role);

  if n > 0 then
    perform private.otb_push('💸 작가비 입금 확인이 밀렸습니다',
      '예식 끝난 지 일주일이 넘었는데 아직 체크가 안 된 것이 ' || tot || '건입니다.' || lines,
      '/admin');
  end if;
  return jsonb_build_object('ok', true, 'total', tot, 'new', n);
end$$;
revoke all on function private.pay_overdue_notify() from public, anon, authenticated;

do $do$
declare jid bigint;
begin
  select jobid into jid from cron.job where command like '%pay_overdue_notify%';
  if jid is null then
    -- 한국 아침 10시 (UTC 1시). 대표가 보실 만한 때에 한 번만
    perform cron.schedule('otb-pay-overdue', '0 1 * * *', 'select private.pay_overdue_notify();');
    raise notice '작가비 입금 알림을 새로 걸었다 (한국 아침 10시)';
  else
    perform cron.alter_job(jid, schedule => '0 1 * * *');
    raise notice '작가비 입금 알림(jobid %) 시각을 맞췄다', jid;
  end if;
end$do$;
