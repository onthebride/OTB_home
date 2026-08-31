-- 월요일 체크가 나갔는데 「보냄」 표가 안 남는다 (대표 2026-08-31
--   «이거 월요일체크가 이제 알림톡으로 가는데 내가 확인 체크 했는데 저기에는 체크완료가
--     안뜨네? / 작가 미확인에 월요일체크도 안보이는 거 같은데 확인해봐»)
--
-- 무엇이 잘못됐나.
--   private.staff_check_send_weekly() 는 **작가마다 한 통** 을 보낸다. 그 주에 몇 건이든
--   한 통이다. 그래서 예약 줄에는 아무 표시도 안 남겼다 — check_sent_at 이 계속 null 이었다.
--
--   그런데 「보냄」 표를 보고 도는 곳이 둘이다.
--     ① 다가오는 예식 카드 — b.check_sent_at 이 있어야 «보냄 ✓» 를 그린다
--     ② public.admin_unconfirmed() — **보낸 건만** 미확인으로 센다
--        (안 보낸 것까지 세면 다음 달 예식이 전부 벌겋게 뜬다)
--
--   ②가 아무것도 안 물어서 「작가 미확인」에 월요일 체크가 통째로 안 보였고,
--   작가가 체크를 마쳐도 카드에 «메인 확인 ✓» 가 안 떴다. 확인한 게 안 세어진 게 아니라
--   **애초에 목록에 없었다.** (2026-08-31 확인: 이번 주 예식 6건 중 3건은 이미 체크 완료)
--
-- 고치는 길: 보낼 때 그 주 예식들에 도장을 찍는다.
--
-- ⚠ 예약 줄을 만지는 일이라 앞뒤를 봤다.
--   · trg_assignment_audit_upd 는 `update of assignee_id, sub_assignee_id` 라 안 깨어난다
--   · trg_booking_change_notify 는 날짜·시간·장소·옵션·1인2인만 본다. 여기 없으니 안 나간다
--   · trg_auto_rep 은 assignee_id 가 null 일 때만 손댄다. 우리는 배정된 건만 만진다
--   **배정은 건드리지 않는다.** check_sent_at / sub_check_sent_at 만 채운다.
--   이미 찍힌 것은 안 덮는다 (대표가 손으로 보낸 시각을 지우지 않는다).

create or replace function private.staff_check_send_weekly(p_dry boolean default false)
returns jsonb language plpgsql security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $function$
declare
  d0 date := date_trunc('week', (now() at time zone 'Asia/Seoul')::date)::date;  -- 이번 주 월요일
  r record; n int := 0; vars jsonb; out_rows jsonb := '[]'::jsonb; n_mark int := 0; m int;
begin
  if not p_dry and exists (select 1 from private.send_hold h where h.kind = 'S' and h.on_date = d0) then
    return jsonb_build_object('ok', true, 'held', true, 'week_of', d0, 'n', 0);
  end if;

  for r in
    -- 메인·서브 가릴 것 없이 «이번 주에 나갈 사람» 이면 받는다.
    -- 한 작가가 이번 주에 세 건이어도 한 통만 간다 (버튼을 누르면 다 보인다)
    select st.id, st.name, st.phone, count(*) as n_wed, min(b.wedding_date) as first_wed
    from public.bookings b
    join public.staff st on st.id in (b.assignee_id, b.sub_assignee_id)
    where b.status <> '취소'
      and b.wedding_date >= d0 and b.wedding_date < d0 + 7
      and coalesce(st.active, false)
      and coalesce(st.phone, '') <> ''
      -- 대표를 걸러내지 않는 것은 일부러다 (대표 요청 2026-08-25 «나한테도 톡 주고»).
      -- 본인도 찍으러 나가니 이번 주 일정을 같은 방식으로 받는 게 맞다
      --
      -- 이번 주에 이미 보냈으면 다시 안 보낸다 (크론이 두 번 돌아도 안전하게)
      and not exists (
        select 1 from private.alimtalk_outbox o
        where o.template = 'S' and o.phone = st.phone
          and o.created_at >= (d0::timestamp at time zone 'Asia/Seoul'))
    group by st.id, st.name, st.phone
    order by st.name
  loop
    out_rows := out_rows || jsonb_build_object(
      'staff', r.name, 'phone', right(r.phone, 4), 'weddings', r.n_wed, 'first', r.first_wed);
    if not p_dry then
      vars := jsonb_build_object('#{작가명}', coalesce(r.name, ''), '#{작가ID}', r.id::text);
      perform private.alimtalk_dispatch(null, 'S', r.phone, vars);
      -- ★ 여기가 이번에 더한 것 — 그 주 예식들에 «체크 요청이 나갔다» 를 남긴다.
      --   이게 없으면 admin_unconfirmed() 가 이 건들을 아예 안 문다
      select private.mark_weekly_sent(r.id, d0, now()) into m;
      n_mark := n_mark + m;
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'dry', p_dry, 'held', false, 'week_of', d0,
    'n', n, 'marked', n_mark, 'rows', out_rows);
end$function$;
revoke all on function private.staff_check_send_weekly(boolean) from public, anon, authenticated;

/* 한 작가의 그 주 예식에 「보냄」 도장을 찍는다. 찍은 줄 수를 돌려준다.
   보내는 곳과 소급하는 곳 둘이 같은 셈을 써야 해서 따로 뺐다 */
drop function if exists private.mark_weekly_sent(uuid, date, timestamptz);
create or replace function private.mark_weekly_sent(p_staff_id uuid, p_week date, p_at timestamptz)
returns int language plpgsql security definer
set search_path to 'private', 'public', 'pg_temp' as $$
declare a int; b int;
begin
  -- ⚠ 배정은 안 건드린다. 이미 찍힌 것도 안 덮는다
  update public.bookings x set check_sent_at = p_at
   where x.assignee_id = p_staff_id and x.status <> '취소'
     and x.wedding_date >= p_week and x.wedding_date < p_week + 7
     and x.check_sent_at is null;
  get diagnostics a = row_count;

  update public.bookings x set sub_check_sent_at = p_at
   where x.sub_assignee_id = p_staff_id and x.status <> '취소'
     and x.wedding_date >= p_week and x.wedding_date < p_week + 7
     and x.sub_check_sent_at is null;
  get diagnostics b = row_count;

  return a + b;
end$$;
revoke all on function private.mark_weekly_sent(uuid, date, timestamptz) from public, anon, authenticated;

/* ===== 이번 주 것을 소급해서 찍는다 =====
   오늘(2026-08-31) 새벽 1시에 이미 다섯 통이 나갔다. 그 톡들은 도장을 안 찍고 갔으므로
   대표 화면에 지금 아무것도 안 보인다. 나간 기록(alimtalk_outbox)을 따라가 채운다.
   ⚠ 보낸 시각을 그대로 쓴다 — 지금 시각으로 찍으면 «언제 나갔나» 가 틀어진다 */
do $$
declare d0 date := date_trunc('week', (now() at time zone 'Asia/Seoul')::date)::date;
        o record; tot int := 0; m int;
begin
  for o in
    select (vars->>'#{작가ID}')::uuid sid, min(created_at) at0
      from private.alimtalk_outbox
     where template = 'S'
       and created_at >= (d0::timestamp at time zone 'Asia/Seoul')
       and vars ? '#{작가ID}'
     group by 1
  loop
    select private.mark_weekly_sent(o.sid, d0, o.at0) into m;
    tot := tot + m;
  end loop;
  raise notice '소급해서 찍은 줄: %', tot;
end$$;
