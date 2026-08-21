-- 드롭박스 폴더 열기 링크가 «지원되지 않습니다» 로 거부되던 진짜 이유. (대표 화면에서 드러남)
--
-- 온더브라이드 드롭박스는 팀 계정이다. 그래서 보는 자리가 두 군데다.
--   API 가 보는 곳  : /2026 셀렉파일/…              (내 폴더가 뿌리)
--   웹에서 보는 곳  : /byunghoon kim/2026 셀렉파일/… (팀 공간이 뿌리, 그 아래 내 폴더)
-- 링크를 API 경로 그대로 만들었으니 웹이 못 찾는 게 당연했다.
--
--   users/get_current_account →
--     root_info: { ".tag":"user", "home_path":"/byunghoon kim", … }
--
-- home_path 를 적어두고, 링크를 만들 때 앞에 붙인다.

insert into private.dropbox (key, val) values ('home_path', '/byunghoon kim')
  on conflict (key) do update set val = excluded.val;

-- 팀 폴더 이름이 바뀌면 링크가 조용히 깨진다. 토큰 받을 때 같이 확인해 둔다.
create or replace function private.dbx_home_fire()
returns bigint language plpgsql security definer set search_path = private, public, pg_temp as $fn$
declare tok text; req bigint;
begin
  tok := private.dbx_token();
  if tok is null then return null; end if;
  select net.http_post(
    url := 'https://api.dropboxapi.com/2/users/get_current_account',
    headers := jsonb_build_object('Authorization', 'Bearer ' || tok)
  ) into req;
  insert into private.dropbox (key, val) values ('home_req', req::text)
    on conflict (key) do update set val = excluded.val;
  return req;
end$fn$;

create or replace function private.dbx_home_reap()
returns text language plpgsql security definer set search_path = private, public, pg_temp as $fn$
declare rid bigint; st int; body jsonb; hp text;
begin
  select val::bigint into rid from private.dropbox where key = 'home_req';
  if rid is null then return null; end if;
  select status_code, content::jsonb into st, body from net._http_response where id = rid;
  if st = 200 then
    hp := body->'root_info'->>'home_path';
    if hp is not null then
      insert into private.dropbox (key, val) values ('home_path', hp)
        on conflict (key) do update set val = excluded.val;
    end if;
  end if;
  delete from private.dropbox where key = 'home_req';
  return hp;
end$fn$;

-- 토큰 거둘 때 같이 한다 — 따로 크론을 두느니 붙이는 게 낫다
create or replace function private.dbx_token_reap()
returns text language plpgsql security definer set search_path = private, public, pg_temp as $fn$
declare t text; hp text;
begin
  t := private.dbx_token_collect();
  hp := private.dbx_home_reap();          -- 지난번 답 거두기
  perform private.dbx_home_fire();        -- 다음 것 띄우기
  return coalesce(left(t, 8), '못 받음') || ' / ' || coalesce(hp, '-');
end$fn$;

-- ── 화면이 링크를 만들 때 쓸 값 ──────────────────────────────
create or replace function public.admin_dbx_home()
returns text language sql stable security definer set search_path = private, public, pg_temp as $fn$
  select case when auth.uid() is null then null
              else (select val from private.dropbox where key = 'home_path') end;
$fn$;
revoke all on function public.admin_dbx_home() from public, anon;
grant execute on function public.admin_dbx_home() to authenticated;
