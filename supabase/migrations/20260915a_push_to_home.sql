-- 대표에게 가는 폰 알림을 홈에도 남긴다 (대표 2026-09-15
--   «이게 관리자에서 뭔가 알림이 오잖아? 아까같은경우 비활성화 작가같은거 알람오던데
--     그런게 오면 홈에 내용이 공지처럼 바로 보였으면 해»)
--
-- 지금까지 대표에게 가는 알림은 **폰으로만** 갔다. 잠금화면에서 지나가면 그걸로 끝이라,
-- 무슨 알림이었는지 다시 볼 길이 없었다.
--   (작가 쪽은 staff_notice 에 남아 캘린더 「알림」 칸에서 다시 본다 — 대표 쪽만 없었다)
--
-- 홈에는 이미 「할 일 알림」 배너(public.admin_reminders)가 있다. 확인 단추까지 달려 있다.
-- 새 화면을 만들 까닭이 없다 — **그 배너에 한 줄 남긴다.**
--
-- ⚠ 한 곳(otb_push)에서 한다. 알림을 쏘는 자리가 열 군데가 넘어서,
--   그때그때 붙이면 새로 만든 알림이 또 빠진다.
-- ⚠ **작가에게 가는 것은 안 남긴다** (p_staff_id 가 있으면 그 작가 것이다).
-- ⚠ 홈에 **이미 제 카드가 있는 알림은 뺀다** (아래 skip_titles) — 같은 말이 두 번 보이면 안 된다.
-- ⚠ 남기는 것을 **먼저** 한다. 푸시 열쇠가 없어도 홈에는 남아야 한다.
--
-- ⚠⚠ **admin_reminders 에는 unique(kind, due_date, booking_id) 가 걸려 있다.**
--   그래서 kind 를 'push' 로만 두면 **하루에 한 줄밖에 못 들어간다** (처음에 그렇게 만들어 걸렸다).
--   kind 에 «제목+내용의 도장» 을 붙여 갈래를 가른다 — 'push:1a2b3c4d'.
--   덕분에 같은 날 같은 내용은 저절로 한 줄이 된다(on conflict do nothing).
--   ⚠ 확인한 뒤에 같은 내용이 그날 또 와도 홈에는 다시 안 뜬다. 폰 알림은 그대로 간다.
--     같은 말을 하루에 두 번 붙이는 것보다 낫다고 봤다.
--   ⚠ 화면은 kind 가 'push' 로 **시작하는지**를 본다 (같은지가 아니라).

create or replace function private.otb_push(
  p_title text, p_body text, p_url text default '/admin', p_staff_id uuid default null)
returns bigint language plpgsql security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $$
declare sec text; url text; req bigint;
  /* 홈에 제 카드가 이미 있는 알림 — 배너에 또 적지 않는다
       🔔 신규 예약        → 홈 「🔔 신규 예약」 카드
       🗓 작가 스케줄 체크  → generate_admin_reminders 가 제 줄을 따로 만든다
       📋 설문 공유         → 같음 */
  skip_titles text[] := array['🔔 신규 예약', '🗓 작가 스케줄 체크', '📋 설문 공유 (내일 예식)'];
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
end$$;
revoke all on function private.otb_push(text, text, text, uuid) from public, anon, authenticated;
