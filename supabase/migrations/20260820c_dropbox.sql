-- 드롭박스 — 신부에게 원본 폴더를 공유한다.
--
-- 하는 일은 두 가지뿐이다: 폴더 목록 읽기, 공유 링크 만들기.
-- 앱 권한 자체에서 쓰기·삭제를 빼놨기 때문에, 여기 코드가 잘못돼도 파일이 지워지지 않는다
-- (files.metadata.read / sharing.read / sharing.write 만 허용).
-- 그래도 코드 쪽에서도 경로를 '온더브라이드 백업' 아래로만 제한한다 — 셀렉파일 폴더는 건드리지 않는다.
--
-- pg_net 은 비동기라 화면에서 바로 못 받는다. 그래서 '요청 보내기'와 '응답 꺼내기'를 나누고,
-- 화면이 잠깐 기다렸다 꺼내가는 방식으로 만든다(클래리티와 같은 구조).

create table if not exists public.dropbox_links (
  booking_id  uuid primary key references public.bookings(id) on delete cascade,
  path        text not null,
  url         text not null,
  created_at  timestamptz not null default now()
);
alter table public.dropbox_links enable row level security;
revoke all on public.dropbox_links from anon, authenticated;

-- ── 접근 토큰은 미리 받아 캐시해 둔다 ─────────────────────────
-- 화면에서 누를 때마다 토큰을 새로 받으면 왕복이 한 번 더 늘어 느리다.
-- 3시간마다 미리 받아두면(토큰 수명 4시간) 누를 때는 바로 쓸 수 있다.
create or replace function private.dbx_refresh()
returns bigint language plpgsql security definer set search_path = private, public, pg_temp as $fn$
declare k text; s text; rt text; req bigint;
begin
  select val into k  from private.dropbox where key = 'app_key';
  select val into s  from private.dropbox where key = 'app_secret';
  select val into rt from private.dropbox where key = 'refresh_token';
  if k is null or s is null or rt is null then return null; end if;
  -- pg_net 은 본문을 JSON 으로만 보낸다. 드롭박스 토큰 발급은 폼 형식이라 못 맞춘다.
  -- 대신 같은 값을 쿼리스트링으로 보내면 받아준다(확인함).
  select net.http_post(
    url := 'https://api.dropboxapi.com/oauth2/token',
    params := jsonb_build_object('grant_type', 'refresh_token', 'refresh_token', rt),
    headers := jsonb_build_object(
      'Authorization', 'Basic ' || encode(convert_to(k || ':' || s, 'UTF8'), 'base64'))
  ) into req;
  insert into private.dropbox (key, val) values ('token_req', req::text)
    on conflict (key) do update set val = excluded.val;
  return req;
end$fn$;

create or replace function private.dbx_token_collect()
returns text language plpgsql security definer set search_path = private, public, pg_temp as $fn$
declare rid bigint; st int; body jsonb;
begin
  select val::bigint into rid from private.dropbox where key = 'token_req';
  if rid is null then return null; end if;
  select status_code, content::jsonb into st, body from net._http_response where id = rid;
  if st is null then return null; end if;
  if st = 200 and body ? 'access_token' then
    insert into private.dropbox (key, val) values ('access_token', body->>'access_token')
      on conflict (key) do update set val = excluded.val;
    insert into private.dropbox (key, val)
      values ('token_until', (now() + ((body->>'expires_in')::int - 600) * interval '1 second')::text)
      on conflict (key) do update set val = excluded.val;
  end if;
  delete from private.dropbox where key = 'token_req';
  return body->>'access_token';
end$fn$;

-- 3시간마다: 지난 응답 거두고 새로 받아둔다
create or replace function private.dbx_token_job()
returns text language plpgsql security definer set search_path = private, public, pg_temp as $fn$
declare t text; r bigint;
begin
  t := private.dbx_token_collect();
  r := private.dbx_refresh();
  return coalesce(left(t, 8), '-') || ' / req ' || coalesce(r::text, '-');
end$fn$;

create or replace function private.dbx_token()
returns text language sql stable security definer set search_path = private, pg_temp as $$
  select val from private.dropbox where key = 'access_token'
    and (select val::timestamptz from private.dropbox where key = 'token_until') > now()
$$;

-- ── 그 예식의 백업 폴더 경로 ─────────────────────────────────
-- 대표가 쓰던 규칙 그대로: 온더브라이드 백업/2026년/09월/26.09.12
create or replace function private.dbx_day_path(p_date date)
returns text language sql immutable as $$
  select '/온더브라이드 백업/' || to_char(p_date, 'YYYY') || '년/' || to_char(p_date, 'MM') || '월/'
      || to_char(p_date, 'YY.MM.DD')
$$;

-- ── ① 폴더 목록 요청 ─────────────────────────────────────────
create or replace function public.admin_dbx_list_req(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare d date; tok text; req bigint;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select wedding_date into d from public.bookings where id = p_booking_id;
  if d is null then raise exception '예식일이 없습니다'; end if;
  tok := private.dbx_token();
  if tok is null then return jsonb_build_object('error', '드롭박스 연결이 아직 준비되지 않았습니다. 잠시 후 다시 눌러주세요.'); end if;
  select net.http_post(
    url := 'https://api.dropboxapi.com/2/files/list_folder',
    body := jsonb_build_object('path', private.dbx_day_path(d), 'limit', 200),
    headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
  ) into req;
  return jsonb_build_object('req', req, 'path', private.dbx_day_path(d));
end$fn$;
revoke all on function public.admin_dbx_list_req(uuid) from public, anon;
grant execute on function public.admin_dbx_list_req(uuid) to authenticated;

-- ── ② 응답 꺼내기 (목록) ─────────────────────────────────────
create or replace function public.admin_dbx_list_res(p_req bigint)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare st int; body jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select status_code, content::jsonb into st, body from net._http_response where id = p_req;
  if st is null then return jsonb_build_object('pending', true); end if;
  if st <> 200 then
    -- 그날 폴더가 아직 없으면 드롭박스가 not_found 를 준다 — 오류가 아니라 '아직 안 올림'
    if body::text like '%not_found%' then return jsonb_build_object('missing', true); end if;
    return jsonb_build_object('error', coalesce(body->>'error_summary', st::text));
  end if;
  return jsonb_build_object('folders', coalesce((
    select jsonb_agg(jsonb_build_object('name', e->>'name', 'path', e->>'path_display') order by e->>'name')
    from jsonb_array_elements(body->'entries') e
    where e->>'.tag' = 'folder'), '[]'::jsonb));
end$fn$;
revoke all on function public.admin_dbx_list_res(bigint) from public, anon;
grant execute on function public.admin_dbx_list_res(bigint) to authenticated;

-- ── ③ 공유 링크 요청 ─────────────────────────────────────────
create or replace function public.admin_dbx_share_req(p_booking_id uuid, p_path text)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare tok text; req bigint;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  -- 우리 백업 폴더 밖은 아예 손대지 않는다
  if p_path is null or p_path not like '/온더브라이드 백업/%' then
    raise exception '이 폴더는 다룰 수 없습니다';
  end if;
  tok := private.dbx_token();
  if tok is null then return jsonb_build_object('error', '드롭박스 연결이 아직 준비되지 않았습니다.'); end if;
  select net.http_post(
    url := 'https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings',
    body := jsonb_build_object('path', p_path,
              'settings', jsonb_build_object('access', 'viewer', 'allow_download', true)),
    headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
  ) into req;
  return jsonb_build_object('req', req);
end$fn$;
revoke all on function public.admin_dbx_share_req(uuid, text) from public, anon;
grant execute on function public.admin_dbx_share_req(uuid, text) to authenticated;

-- ── ④ 공유 링크 응답 → 예약에 저장 ───────────────────────────
create or replace function public.admin_dbx_share_res(p_req bigint, p_booking_id uuid, p_path text)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare st int; body jsonb; link text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select status_code, content::jsonb into st, body from net._http_response where id = p_req;
  if st is null then return jsonb_build_object('pending', true); end if;

  if st = 200 then
    link := body->>'url';
  elsif body::text like '%shared_link_already_exists%' then
    -- 이미 만든 링크가 있으면 그걸 쓴다
    link := body #>> '{error,shared_link_already_exists,metadata,url}';
  end if;
  if link is null then return jsonb_build_object('error', coalesce(body->>'error_summary', st::text)); end if;

  -- dl=1 로 바꾸지 않는다. 그러면 폴더 전체를 zip 으로 묶어 내려주려다 대용량에서 실패한다.
  -- dl=0 이면 신부가 드롭박스 화면에서 보고 골라 받을 수 있다.
  update public.bookings set download_link = link where id = p_booking_id;
  insert into public.dropbox_links (booking_id, path, url) values (p_booking_id, p_path, link)
    on conflict (booking_id) do update set path = excluded.path, url = excluded.url, created_at = now();
  return jsonb_build_object('url', link);
end$fn$;
revoke all on function public.admin_dbx_share_res(bigint, uuid, text) from public, anon;
grant execute on function public.admin_dbx_share_res(bigint, uuid, text) to authenticated;
