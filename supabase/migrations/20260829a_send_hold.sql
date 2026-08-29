-- 작가에게 나가는 알림톡 — 나가기 전에 대표가 먼저 보고 막을 수 있게 한다.
-- 대표 지시 2026-08-29 «예식 전날 작가에게 설문톡이 자동으로 가네? 확인 후 발송 아니었나?»
--
-- 무엇이 어긋나 있었나.
--   · 아침 6시  — 관리자 홈에 「작가에게 설문 안내 발송」 알림이 뜬다. 눌러서 목록을 보고
--                 확인하면 나간다. 대표가 기억하시는 «확인 후 발송» 이 이것이다
--   · 오전 10시 2분 — private.staff_survey_send_daily() 이 자동으로 보낸다 (2026-08-25 부터)
--   6시 알림을 보기도 전에 10시에 자동이 먼저 보내버려서, 그 단추를 누를 일이 없어졌다.
--   admin.js 에는 아직도 «자동으로 나가는 알림톡은 없다» 고 적혀 있었다. 같이 바로잡는다.
--
-- 대표가 고른 길(㉯): 자동은 그대로 두되, 나가기 전에 먼저 보여주고 막을 수 있게 한다.
--   6시 알림 문구를 «오늘 오전 10시에 이 분들께 나갑니다» 로 바꾸고,
--   「오늘은 안 보내기」를 누르면 그날 것만 막는다. 다음 날은 다시 정상.
--
-- ⚠ 막은 것을 alimtalk_sent 에 적지 않는다. 그 칸의 «T:<작가ID>» 는 홈의 「작가 미확인」이
--   «보냈다» 로 읽는 자리다(20260828b_unconf_two.sql). 막은 것은 «안 보낸 것» 이 맞다.
--   그래서 따로 표를 둔다.

-- ===== 하루치 «보내지 않기» =====
create table if not exists private.send_hold (
  kind    text not null,          -- 'T' 예식 전날 설문 · 'S' 월요일 스케줄
  on_date date not null,          -- T 는 그날(한국), S 는 그 주 월요일
  held_at timestamptz not null default now(),
  primary key (kind, on_date)
);
comment on table private.send_hold is
  '작가 알림톡을 그날/그 주만 안 보내기로 한 표시. 대표가 관리자 홈에서 누른다 (2026-08-29)';

revoke all on table private.send_hold from public, anon, authenticated;

-- ===== 막혔는지 보는 함수 (관리자 화면이 부른다) =====
create or replace function public.admin_send_hold_state()
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare d date := (now() at time zone 'Asia/Seoul')::date;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  return jsonb_build_object(
    'today', d,
    'T', exists (select 1 from private.send_hold h where h.kind = 'T' and h.on_date = d),
    'S', exists (select 1 from private.send_hold h
                 where h.kind = 'S' and h.on_date = date_trunc('week', d)::date));
end$fn$;
revoke all on function public.admin_send_hold_state() from public, anon;
grant execute on function public.admin_send_hold_state() to authenticated;

-- ===== 막기 / 풀기 =====
create or replace function public.admin_send_hold_set(p_kind text, p_on boolean)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare d date := (now() at time zone 'Asia/Seoul')::date; target date;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_kind not in ('T', 'S') then raise exception '알 수 없는 종류: %', p_kind; end if;

  -- T 는 오늘 하루, S 는 이번 주
  target := case when p_kind = 'S' then date_trunc('week', d)::date else d end;

  if p_on then
    insert into private.send_hold (kind, on_date) values (p_kind, target)
    on conflict (kind, on_date) do nothing;
  else
    delete from private.send_hold h where h.kind = p_kind and h.on_date = target;
  end if;

  return jsonb_build_object('ok', true, 'kind', p_kind, 'on_date', target, 'held', p_on);
end$fn$;
revoke all on function public.admin_send_hold_set(text, boolean) from public, anon;
grant execute on function public.admin_send_hold_set(text, boolean) to authenticated;

-- ===== 보내는 쪽이 그 표시를 본다 =====
-- ⚠ 칸을 더하는 게 아니라 몸통만 고친다. 이름·인자·반환형이 그대로라 drop 이 필요없다.

create or replace function private.staff_survey_send_daily(p_dry boolean default false)
returns jsonb language plpgsql security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $$
declare
  d0 date := (now() at time zone 'Asia/Seoul')::date;        -- 오늘(보내는 날)
  d1 date := (now() at time zone 'Asia/Seoul')::date + 1;    -- 내일 예식
  r record; n int := 0; vars jsonb; line text; out_rows jsonb := '[]'::jsonb;
begin
  -- 대표가 오늘은 안 보내기로 했으면 여기서 끝낸다 (다음 날은 다시 나간다)
  if not p_dry and exists (select 1 from private.send_hold h where h.kind = 'T' and h.on_date = d0) then
    return jsonb_build_object('ok', true, 'held', true, 'for_date', d1, 'n', 0);
  end if;

  for r in
    -- 메인과 서브에게 각각 간다. 두 분이 가는 예식이면 둘 다 신부 설문을 봐야 한다.
    -- 보냈다는 표시는 «T:<작가ID>» 로 남긴다 — 손 버튼(admin_send_staff_survey)과 같은 열쇠라
    -- 손으로 먼저 보냈으면 자동으로 또 가지 않는다.
    -- 예약은 b.* 로 풀지 말고 «b» 통째로 들고 다닌다 — private.wedding_line 이 bookings 형을
    -- 받는데, 다른 칸과 섞어 편 record 는 그 형으로 못 바꾼다 (coerce_record_to_complex)
    select b as bk, st.id as staff_id, st.name as staff_name, st.phone as staff_phone
    from public.bookings b
    join public.staff st on st.id in (b.assignee_id, b.sub_assignee_id)
    where b.status <> '취소'
      and b.wedding_date = d1
      and coalesce(st.phone, '') <> ''
      and (coalesce(b.alimtalk_sent, '{}'::jsonb) -> ('T:' || st.id::text)) is null
    order by st.name
  loop
    -- 설문이 아직이면 그렇다고 적어 보낸다 (손 버튼과 같은 문장)
    line := private.wedding_line(r.bk)
      || case when exists (select 1 from public.surveys sv where sv.booking_id = (r.bk).id)
              then '' else ' (설문 미작성)' end;
    out_rows := out_rows || jsonb_build_object(
      'staff', r.staff_name, 'phone', right(r.staff_phone, 4), 'line', line,
      'link', '/survey-view?b=' || (r.bk).id::text || '&s=' || r.staff_id::text);
    if not p_dry then
      vars := jsonb_build_object(
        '#{작가명}', coalesce(r.staff_name, ''),
        '#{예식정보}', line,
        -- 여기에 «&s=<작가ID>» 를 같이 실어야 열었을 때 확인 단추가 뜬다 (위 설명 참고)
        '#{예약ID}', (r.bk).id::text || '&s=' || r.staff_id::text);
      perform private.alimtalk_dispatch((r.bk).id, 'T', r.staff_phone, vars);
      update public.bookings
         set alimtalk_sent = coalesce(alimtalk_sent, '{}'::jsonb)
             || jsonb_build_object('T:' || r.staff_id::text, to_jsonb(now()))
       where id = (r.bk).id;
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'dry', p_dry, 'held', false, 'for_date', d1, 'n', n, 'rows', out_rows);
end$$;
revoke all on function private.staff_survey_send_daily(boolean) from public, anon, authenticated;

-- 월요일 스케줄 톡도 같은 방식으로 막을 수 있게 한다
create or replace function private.staff_check_send_weekly(p_dry boolean default false)
returns jsonb language plpgsql security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $$
declare
  d0 date := date_trunc('week', (now() at time zone 'Asia/Seoul')::date)::date;  -- 이번 주 월요일
  r record; n int := 0; vars jsonb; out_rows jsonb := '[]'::jsonb;
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
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'dry', p_dry, 'held', false, 'week_of', d0, 'n', n, 'rows', out_rows);
end$$;
revoke all on function private.staff_check_send_weekly(boolean) from public, anon, authenticated;


-- ===== 관리자 알림 문구 =====
-- 예전엔 «관리자에서 발송하세요» 였다. 이제 자동으로 나가므로 그 말이 틀렸다.
-- «오늘 오전 10시에 자동으로 나갑니다 · 막으려면 관리자에서» 로 바꾼다.
-- 몸통은 그대로다 — 문구 넉 줄만 다르다.

CREATE OR REPLACE FUNCTION private.generate_admin_reminders()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'private', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  today_kst date := (now() at time zone 'Asia/Seoul')::date;
  r record;
  wk_cnt int; wk_staff int;
  n_new int := 0;
  n_t int := 0; names text := '';
begin
  -- 오래된 알림 정리 (기존 동작)
  update public.admin_reminders
     set dismissed = true, dismissed_at = now()
   where not dismissed and due_date < today_kst - 7;

  -- 월요일: 작가 스케줄 체크 (대표 규칙 = 월요일 기준 +3 ~ +9 일 예식)
  if extract(dow from today_kst) = 1 then
    select count(*), count(distinct s.id) into wk_cnt, wk_staff
      from public.bookings b
      join public.staff s on (s.id = b.assignee_id or s.id = b.sub_assignee_id)
     where b.status <> '취소' and s.active
       and b.wedding_date between today_kst + 3 and today_kst + 9;
    insert into public.admin_reminders (kind, due_date, title, body, url)
    values ('weekly_schedule', today_kst,
            '작가 스케줄 톡 — 월요일 오전 10시 자동 발송' || case when wk_staff > 0 then ' (' || wk_staff || '명)' else '' end,
            case when wk_cnt > 0
                 then to_char(today_kst + 3, 'FMMM/FMDD') || '~' || to_char(today_kst + 9, 'FMMM/FMDD')
                      || ' 예식 ' || wk_cnt || '건'
                 else '이번 주기에는 예식이 없습니다.' end,
            '/admin')
    on conflict do nothing;
    if found then
      n_new := n_new + 1;
      perform private.otb_push('🗓 작가 스케줄 톡',
        case when wk_cnt > 0 then '작가 ' || wk_staff || '명 · 예식 ' || wk_cnt || '건 — 월요일 오전 10시에 자동으로 나갑니다. 막으려면 관리자에서.'
             else '이번 주기에는 예식이 없습니다.' end, '/admin');
    end if;
  end if;

  -- 매일: 내일 예식 담당 작가에게 설문 안내 (한 줄로 묶음)
  for r in
    select coalesce(nullif(b.bride_name,''), nullif(b.contractor_name,''), '고객') as who
    from public.bookings b
    where b.status <> '취소' and b.wedding_date = today_kst + 1 and b.assignee_id is not null
    order by b.wedding_time nulls last
  loop
    n_t := n_t + 1;
    names := names || case when names = '' then '' else ', ' end || r.who;
  end loop;

  if n_t > 0 then
    insert into public.admin_reminders (kind, due_date, title, body, url)
    values ('staff_survey', today_kst,
            '내일 예식 ' || n_t || '건 — 오늘 오전 10시에 작가에게 자동 발송', names, '/admin')
    on conflict do nothing;
    if found then
      n_new := n_new + 1;
      perform private.otb_push('📋 작가 설문 안내',
        '내일 예식 ' || n_t || '건 · ' || names || ' — 오늘 오전 10시에 자동으로 나갑니다. 막으려면 관리자에서.', '/admin');
    end if;
  end if;

  return n_new;
end$function$
