-- 드롭박스 접속권(토큰)이 세 시간 중 두 시간 반은 죽어 있었다. 그걸 고친다.
--
-- 무슨 일이 있었나 (2026-08-21 점검 중 발견)
--   토큰 받아두기를 한 함수가 두 가지를 같이 했다 — ① 지난번 요청의 답을 거둬 저장하고
--   ② 다음 요청을 새로 띄운다. 3시간마다 돌았으니, 거둔 토큰은 '3시간 전에 발급된' 것이다.
--   그런데 저장할 때 유효기한을 '지금부터 4시간'으로 적었다. 실제로는 이미 3시간을 쓴 토큰이라
--   1시간 뒤 죽는데, 우리 기록은 3시간 50분 뒤까지 살아 있다고 되어 있었다.
--   그래서 매 주기의 뒤쪽 2시간 50분 동안 드롭박스가 401(expired_access_token)을 돌려줬다.
--   실제로 확인함: 기록상 '09:57 까지 유효'인데 07:16 에 이미 401.
--
-- 어떻게 고치나
--   띄우는 일과 거두는 일을 1분 간격의 두 크론으로 나눈다. 그러면 거둘 때가 발급 직후라
--   '지금부터 4시간'이 실제와 맞는다. 토큰은 늘 1분 된 것이다.

create or replace function private.dbx_token_fire()
returns bigint language plpgsql security definer set search_path = private, public, pg_temp as $fn$
begin
  return private.dbx_refresh();
end$fn$;

-- 거두기 — 받은 즉시 저장하므로 '지금부터'가 곧 발급 시각이다
create or replace function private.dbx_token_reap()
returns text language plpgsql security definer set search_path = private, public, pg_temp as $fn$
declare t text;
begin
  t := private.dbx_token_collect();
  return coalesce(left(t, 8), '못 받음');
end$fn$;

-- 예전 크론(띄우기+거두기를 한꺼번에 하던 것)은 내린다
select cron.unschedule('otb-dropbox-token') where exists (select 1 from cron.job where jobname = 'otb-dropbox-token');

select cron.schedule('otb-dropbox-token-fire', '5 */3 * * *', $$select private.dbx_token_fire()$$);
select cron.schedule('otb-dropbox-token-reap', '6 */3 * * *', $$select private.dbx_token_reap()$$);

-- 그래도 죽은 토큰을 들고 있으면 곤란하니, 꺼내 쓸 때 한 번 더 본다.
-- (유효기한이 지났으면 아예 없는 것으로 친다 — 화면에는 '연결이 준비되지 않았습니다'가 뜬다)
create or replace function private.dbx_token()
returns text language sql stable security definer set search_path = private, pg_temp as $$
  select val from private.dropbox where key = 'access_token'
    and (select val::timestamptz from private.dropbox where key = 'token_until') > now() + interval '1 minute'
$$;
