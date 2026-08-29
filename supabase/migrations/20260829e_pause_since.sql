-- 자동 멈춤의 날수를 «오늘부터» 센다 (대표 2026-08-29
-- «무슨소리 접속재기 시작한지 얼마안됨 / 접속기록은 오늘부터 다시 재»)
--
-- 무엇이 틀렸나. 접속 기록(public.staff_visit)은 2026-08-28 에 만들었다.
-- 그 전에는 누가 언제 들어왔는지 남지 않았다. 그런데 어제 만든 staff_auto_pause 는
-- 기록이 없으면 «작가로 만든 날» 부터 셌다. 그래서 오래 전에 등록된 분이
-- 「두 달 넘게 안 들어옴」으로 잡혔다. 실제로는 우리가 안 세고 있었을 뿐이다.
--
-- 고치는 법. 세기 시작한 날을 바닥으로 깐다.
--   마지막 접속 = 가장 큰 값(진짜 접속 기록, 작가 만든 날, 2026-08-29)
-- 그래서 아무리 오래된 분이라도 2026-09-28 (오늘+30) 전에는 꺼지지 않는다.
-- 예고는 2026-09-21 (오늘+23) 부터 나갈 수 있다.
--
-- ⚠ 이 날짜를 지우면 안 된다. 지우면 다시 «작가 만든 날» 로 돌아가 옛 분들이 한꺼번에 꺼진다.
--   나중에 기록이 넉넉히 쌓이면 그때 빼도 된다 — 그때는 이미 모두의 진짜 기록이 이 날 뒤다.

-- ⚠ 칸이 하나 늘었다(p_since). create or replace 는 칸 수가 다르면 **새 함수를 만든다** —
--   옛 한 칸짜리가 나란히 살아남아 크론의 staff_auto_pause() 가 «어느 쪽인지 모르겠다» 로
--   터진다. 반드시 먼저 지운다.
drop function if exists private.staff_auto_pause(boolean);

create or replace function private.staff_auto_pause(
  p_dry boolean default false,
  -- 시험에서만 앞당겨 넣는다. 운영에서는 비워 두고 아래 기본값을 쓴다
  p_since date default null)
returns jsonb language plpgsql security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $$
declare
  today date := (now() at time zone 'Asia/Seoul')::date;
  -- 접속 기록을 제대로 세기 시작한 날. 이 앞의 «안 들어옴» 은 우리가 안 센 것이지
  -- 안 들어오신 게 아니다 (대표 2026-08-29 «접속기록은 오늘부터 다시 재»)
  SINCE   constant date := coalesce(p_since, date '2026-08-29');
  WARN_AT constant int  := 23;   -- 이 날부터 «7일 남음» 을 알린다
  OFF_AT  constant int  := 30;   -- 이 날 끈다
  r record; n_off int := 0; n_warn int := 0;
  off_rows jsonb := '[]'::jsonb; warn_rows jsonb := '[]'::jsonb;
  ttl text; msg text;
begin
  for r in
    select st.id, st.name,
           -- 마지막 접속. 기록이 없으면 만든 날, 그마저 옛날이면 «세기 시작한 날»
           greatest(
             coalesce((select max(v.the_day) from public.staff_visit v where v.staff_id = st.id),
                      (st.created_at at time zone 'Asia/Seoul')::date),
             SINCE) as last_day,
           -- 앞으로 잡힌 우리 예식
           exists (select 1 from public.bookings b
                   where b.status <> '취소' and b.wedding_date >= today
                     and st.id in (b.assignee_id, b.sub_assignee_id)) as has_wed,
           -- 앞으로 잡힌 본인 일정 (쉬는 날·다른 촬영 둘 다)
           exists (select 1 from public.staff_busy sb
                   where sb.staff_id = st.id and sb.the_date >= today) as has_busy
    from public.staff st
    where coalesce(st.active, false) and coalesce(st.accepting, false)
  loop
    -- 앞으로 쓰고 계신 것이 있으면 손대지 않는다
    if r.has_wed or r.has_busy then continue; end if;

    if today - r.last_day >= OFF_AT then
      off_rows := off_rows || jsonb_build_object('staff', r.name, 'last', r.last_day);
      n_off := n_off + 1;
      if not p_dry then
        update public.staff set accepting = false where id = r.id;
        ttl := '⏸ 스케줄 받기가 꺼졌습니다';
        msg := '한 달 넘게 캘린더에 들어오지 않으셔서 새 예식 배정을 잠시 멈췄어요.'
            || E'\n다시 받으시려면 캘린더 「설정」에서 「스케줄 받기」를 켜주세요.';
        insert into public.staff_notice(staff_id, booking_id, kind, title, body)
        values (r.id, null, 'pause', ttl, msg);
        perform private.otb_push(ttl, msg, '/staff-calendar?s=' || r.id::text, r.id);
      end if;

    elsif today - r.last_day >= WARN_AT
      -- 최근 30일 안에 예고를 이미 보냈으면 또 안 보낸다
      and not exists (select 1 from public.staff_notice sn
                      where sn.staff_id = r.id and sn.kind = 'pause_warn'
                        and sn.created_at >= now() - interval '30 days') then
      warn_rows := warn_rows || jsonb_build_object(
        'staff', r.name, 'last', r.last_day, 'days_left', OFF_AT - (today - r.last_day));
      n_warn := n_warn + 1;
      if not p_dry then
        ttl := '⏳ 스케줄 받기가 ' || (OFF_AT - (today - r.last_day)) || '일 뒤 꺼집니다';
        msg := '한 달 가까이 캘린더에 들어오지 않으셨어요.'
            || E'\n이대로 두면 새 예식 배정이 잠시 멈춥니다.'
            || E'\n캘린더를 한 번 열어보시면 그대로 유지됩니다.';
        insert into public.staff_notice(staff_id, booking_id, kind, title, body)
        values (r.id, null, 'pause_warn', ttl, msg);
        perform private.otb_push(ttl, msg, '/staff-calendar?s=' || r.id::text, r.id);
      end if;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'dry', p_dry, 'today', today, 'since', SINCE,
    'off', n_off, 'warn', n_warn, 'off_rows', off_rows, 'warn_rows', warn_rows);
end$$;
revoke all on function private.staff_auto_pause(boolean, date) from public, anon, authenticated;
