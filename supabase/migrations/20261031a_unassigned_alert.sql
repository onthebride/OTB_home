-- 한 달 안 예식에 작가가 비어 있으면 대표 폰을 울린다
--   (대표 2026-10-31 «일주일전 미배정 알림 강하게 줘라» → 곧이어 «한달 전부터 알려줘»)
--
-- 지금까지는 알림이 아예 없었다. 관리자 화면에 「미배정」 딱지가 붙는 것뿐이었고,
-- 2인 촬영에서 서브만 빈 것은 「다가오는 예식」 에 아무 표시도 안 났다.
--
-- 고르는 기준 (캘린더·날짜 카드와 같다 — 취소 아님 + 계약금 확인)
--   · 오늘 ~ 30일 뒤 예식
--   · 메인이 비었거나, 2인 촬영인데 서브가 비었다
--
-- 울리는 때 — 가까워질수록 세게
--   · 아침 9시 — 30일 안 것을 **배정될 때까지 매일**. 어제 알린 것도 또 알린다
--   · 저녁 8시 — 일주일 안(내일~7일 뒤) 것만 한 번 더
--   같은 날 같은 때에 두 번 돌아도 한 번만 간다 (unassigned_alert_log)
--
-- 홈 배너(admin_reminders)에는 안 남긴다. 관리자 화면 맨 위 빨간 칸이 **지금 상태**를 그대로 보여준다 —
-- 확인을 눌러 지우는 줄이 아니라, 배정하면 저절로 사라진다. 같은 말이 두 번 보이지 않게 otb_push 의
-- 건너뛰는 제목에 넣는다.
--
-- ⚠ 배정은 건드리지 않는다. 읽고 알리기만 한다.
-- ⚠ 폰 알림 글에는 신랑신부 이름을 안 쓴다. 날짜·시각·예식장이면 대표가 알아보신다.

drop function if exists private.unassigned_soon(date);
create or replace function private.unassigned_soon(p_today date default null, p_days int default 30)
returns table (booking_id uuid, wedding_date date, wedding_time text, venue text, need text, d_left int)
language sql stable security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp' as $$
  select b.id, b.wedding_date, b.wedding_time, coalesce(nullif(trim(b.wedding_venue), ''), '예식장 미정'),
         case when b.assignee_id is null and b.photographer = '2인 촬영' and b.sub_assignee_id is null then '메인·서브 없음'
              when b.assignee_id is null then '메인 없음'
              else '서브 없음' end,
         (b.wedding_date - coalesce(p_today, (now() at time zone 'Asia/Seoul')::date))::int
    from public.bookings b
   where b.status <> '취소' and coalesce(b.deposit_paid, false)
     and b.wedding_date between coalesce(p_today, (now() at time zone 'Asia/Seoul')::date)
                            and coalesce(p_today, (now() at time zone 'Asia/Seoul')::date) + coalesce(p_days, 30)
     and (b.assignee_id is null or (b.photographer = '2인 촬영' and b.sub_assignee_id is null))
   order by b.wedding_date, b.wedding_time nulls last
$$;
revoke all on function private.unassigned_soon(date, int) from public, anon, authenticated;

create table if not exists private.unassigned_alert_log (
  on_date date not null,
  slot    text not null check (slot in ('am', 'pm')),
  n       int  not null,
  at      timestamptz not null default now(),
  primary key (on_date, slot)
);
revoke all on table private.unassigned_alert_log from public, anon, authenticated;

create or replace function private.unassigned_alert(p_slot text default 'am')
returns jsonb language plpgsql security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp' as $$
declare
  today date := (now() at time zone 'Asia/Seoul')::date;
  wd text[] := array['일', '월', '화', '수', '목', '금', '토'];
  lo int := case when p_slot = 'pm' then 1 else 0 end;
  hi int := case when p_slot = 'pm' then 7 else 30 end;
  r record; n int := 0; n7 int := 0; lines text := ''; ids jsonb := '[]'::jsonb; body text;
begin
  if p_slot not in ('am', 'pm') then return jsonb_build_object('ok', false, 'error', 'slot'); end if;
  for r in select * from private.unassigned_soon(today, 30) u where u.d_left between lo and hi loop
    n := n + 1;
    if r.d_left <= 7 then n7 := n7 + 1; end if;
    ids := ids || to_jsonb(r.booking_id);
    if n <= 6 then
      lines := lines || E'\n' || case when r.d_left = 0 then '오늘' else 'D-' || r.d_left end
            || ' ' || to_char(r.wedding_date, 'FMMM/FMDD') || '(' || wd[extract(dow from r.wedding_date)::int + 1] || ')'
            || coalesce(' ' || nullif(r.wedding_time, ''), '') || ' ' || r.venue || ' — ' || r.need;
    end if;
  end loop;
  if n = 0 then return jsonb_build_object('ok', true, 'slot', p_slot, 'n', 0, 'sent', false); end if;

  insert into private.unassigned_alert_log (on_date, slot, n) values (today, p_slot, n)
  on conflict (on_date, slot) do nothing;
  if not found then return jsonb_build_object('ok', true, 'slot', p_slot, 'n', n, 'sent', false, 'already', true); end if;

  body := n || '건 · ' || case when p_slot = 'pm' then '일주일 안 예식이라 저녁에 한 번 더 알려드려요'
                              when n7 > 0 then '한 달 안 예식 (일주일 안 ' || n7 || '건)'
                              else '한 달 안 예식' end
       || lines || case when n > 6 then E'\n외 ' || (n - 6) || '건' else '' end || E'\n관리자에서 배정해 주세요';
  -- ⚠ 대표에게만. staff_id 를 넘기면 그 작가에게 간다 — 절대 넘기지 않는다
  perform private.otb_push('🚨 작가 미배정', body, '/admin');
  return jsonb_build_object('ok', true, 'slot', p_slot, 'n', n, 'sent', true, 'ids', ids, 'body', body);
end$$;
revoke all on function private.unassigned_alert(text) from public, anon, authenticated;

-- otb_push — 건너뛰는 제목에 「🚨 작가 미배정」 하나만 더했다. 나머지는 운영 판 그대로
create or replace function private.otb_push(p_title text, p_body text, p_url text DEFAULT '/admin'::text, p_staff_id uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'private', 'public', 'extensions', 'pg_temp'
AS $function$
declare sec text; url text; req bigint;
  /* 홈에 제 카드가 이미 있는 알림 — 배너에 또 적지 않는다
       🔔 신규 예약        → 홈 「🔔 신규 예약」 카드
       🗓 작가 스케줄 체크  → generate_admin_reminders 가 제 줄을 따로 만든다
       📋 설문 공유         → 같음
       🚨 작가 미배정       → 관리자 화면 맨 위 빨간 칸 (배정하면 저절로 사라진다) */
  skip_titles text[] := array['🔔 신규 예약', '🗓 작가 스케줄 체크', '📋 설문 공유 (내일 예식)', '🚨 작가 미배정'];
begin
  -- ★ 대표에게 가는 것은 홈 배너에도 한 줄 남긴다 (푸시보다 먼저 — 폰이 안 울려도 남아야 한다)
  if p_staff_id is null and not (p_title = any(skip_titles)) then
    insert into public.admin_reminders (kind, due_date, title, body, url)
    values ('push:' || left(md5(coalesce(p_title, '') || '|' || coalesce(p_body, '')), 8),
            (now() at time zone 'Asia/Seoul')::date, p_title, p_body, coalesce(p_url, '/admin'))
    on conflict do nothing;
  end if;

  select val into sec from private.solapi where key = 'push_secret';
  select val into url from private.solapi where key = 'push_url';
  if sec is null or url is null then return null; end if;
  select net.http_post(
    url := url,
    body := jsonb_build_object(
      'title', p_title, 'body', coalesce(p_body, ''),
      'url', coalesce(p_url, '/admin'), 'tag', 'otb',
      -- 비어 있으면 대표에게. 있으면 그 작가에게만
      'staff_id', p_staff_id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', sec)
  ) into req;
  return req;
exception when others then return null;   -- 푸시 실패는 무시(호출측 보호)
end$function$;

do $do$
declare jid bigint;
begin
  -- 아침 9시 (UTC 0시) — 30일 안 전부
  select jobid into jid from cron.job where jobname = 'otb-unassigned-am';
  if jid is not null then perform cron.unschedule(jid); end if;
  perform cron.schedule('otb-unassigned-am', '0 0 * * *', $$select private.unassigned_alert('am');$$);
  -- 저녁 8시 (UTC 11시) — 일주일 안 것만 한 번 더
  select jobid into jid from cron.job where jobname = 'otb-unassigned-pm';
  if jid is not null then perform cron.unschedule(jid); end if;
  perform cron.schedule('otb-unassigned-pm', '0 11 * * *', $$select private.unassigned_alert('pm');$$);
end$do$;
