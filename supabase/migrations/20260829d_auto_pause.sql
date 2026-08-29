-- 오래 안 들어오시면 스케줄 받기를 자동으로 꺼둔다 (대표 2026-08-29)
-- «캘린더에 우리스케줄이나 개인일정 등 스케줄 활동이 없어서 한달동안 접속 안하는 사람은
--   자동으로 스케줄 안받는 설정으로 변경되게해줘 / 작가알림에 비활성화 몇 일 남음 이런거 뜨게»
--
-- 왜 필요한가. 쉬시는 분에게 배정이 나가면 그날 사람이 안 나온다.
-- 「쉬는 중」으로 바꿔달라고 말씀 안 주고 그냥 안 들어오시는 경우가 있다.
--
-- ⚠ 끄는 것은 **스케줄 받기(accepting)** 뿐이다. 작가를 비활성(active)으로 만들지 않는다.
--   비활성은 그만두신 분에게 쓰는 것이고, 이건 «잠시 안 보이시네요» 다.
--   본인이 캘린더에서 스위치 하나로 다시 켤 수 있다.
--
-- 조건 (셋 다 맞아야 끈다)
--   ① 지금 활성 + 받는 중
--   ② 앞으로 잡힌 것이 없다 — 우리 예식도, 본인이 넣은 개인 일정도
--      (하나라도 있으면 «쓰고 계신 것» 이라 안 건드린다)
--   ③ 마지막 접속이 30일 넘었다 (한 번도 안 들어온 분은 작가로 만든 날부터 센다)
--
-- 미리 알린다
--   23일째(=7일 남음)에 한 번 «7일 뒤 꺼집니다» 를 알림+폰으로 보낸다.
--   들어오시면 접속 기록이 갱신되어 날수가 처음부터 다시 센다 — 저절로 풀린다.
--   ⚠ 예고를 이미 보냈는지는 staff_notice 를 보고 판단한다. 칸을 새로 만들지 않는다.
--
-- ⚠ 이 함수는 하루 한 번만 돌아야 한다. 두 번 돌아도 탈은 없다 —
--   끈 사람은 accepting 이 false 라 ①에서 걸러지고, 예고는 최근 30일 안에 보낸 게
--   있으면 건너뛴다.

create or replace function private.staff_auto_pause(p_dry boolean default false)
returns jsonb language plpgsql security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $$
declare
  today date := (now() at time zone 'Asia/Seoul')::date;
  WARN_AT constant int := 23;   -- 이 날부터 «7일 남음» 을 알린다
  OFF_AT  constant int := 30;   -- 이 날 끈다
  r record; n_off int := 0; n_warn int := 0;
  off_rows jsonb := '[]'::jsonb; warn_rows jsonb := '[]'::jsonb;
  ttl text; msg text;
begin
  for r in
    select st.id, st.name,
           -- 마지막 접속. 한 번도 없으면 «작가로 만든 날» 부터 센다
           coalesce((select max(v.the_day) from public.staff_visit v where v.staff_id = st.id),
                    (st.created_at at time zone 'Asia/Seoul')::date) as last_day,
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

  return jsonb_build_object('ok', true, 'dry', p_dry, 'today', today,
    'off', n_off, 'warn', n_warn, 'off_rows', off_rows, 'warn_rows', warn_rows);
end$$;
revoke all on function private.staff_auto_pause(boolean) from public, anon, authenticated;

-- 한국 아침 9시 (cron.timezone 이 GMT 라 0시로 적는다).
-- 작가 톡(10시)보다 먼저 돌아야 «꺼진 사람에게 스케줄 톡이 가는» 일이 없다.
do $$
declare jid bigint;
begin
  select jobid into jid from cron.job where command like '%staff_auto_pause%';
  if jid is null then
    perform cron.schedule('otb-staff-auto-pause', '0 0 * * *', 'select private.staff_auto_pause();');
    raise notice '자동 멈춤 작업을 새로 걸었다 (한국 아침 9시)';
  else
    perform cron.alter_job(jid, schedule => '0 0 * * *');
    raise notice '자동 멈춤 작업(jobid %) 시각을 맞췄다', jid;
  end if;
end $$;

-- ===== 작가 화면이 「중요 공지」를 위에 띄울 수 있게 =====
-- 대표 «내가 보내는 공지랑 비활성화 안내는 중요공지니까 캘린더 상단에 바로 보이게
--       뜨게해줘 그리고 알림화면에도 있어야해»
--
-- 중요한 것 = 대표 공지(notice) · 멈춤 예고(pause_warn) · 멈춤 알림(pause).
-- 예식 변경(change)·취소(cancel)는 아니다 — 그건 그 예식 카드에서 보인다.
--
-- ⚠ 안 읽은 것만 준다. 읽으면 위에서 사라지고 「알림」 칸에는 그대로 남는다.
create or replace function public.staff_top_notices(p_staff_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp as $fn$
declare res jsonb;
begin
  if p_staff_id is null then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(t order by t.id desc), '[]'::jsonb) into res from (
    select sn.id, sn.kind, sn.title, sn.body,
           to_char(sn.created_at at time zone 'Asia/Seoul', 'MM/DD') as at
    from public.staff_notice sn
    where sn.staff_id = p_staff_id
      and sn.read_at is null
      and sn.kind in ('notice', 'pause_warn', 'pause')
    order by sn.id desc
    limit 3          -- 위쪽은 좁다. 셋까지만 띄우고 나머지는 「알림」 칸에서 본다
  ) t;
  return res;
end$fn$;
revoke all on function public.staff_top_notices(uuid) from public;
grant execute on function public.staff_top_notices(uuid) to anon, authenticated;
