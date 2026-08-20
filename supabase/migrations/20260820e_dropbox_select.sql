-- 셀렉 매칭 — 신부가 고른 JPG 이름으로 RAW 를 찾아 셀렉파일 폴더에 복사한다.
--
-- 지금은 대표가 3천 장짜리 RAW 폴더에서 40개를 눈으로 찾아 고른다. 그걸 없앤다.
-- JPG 와 RAW 는 확장자만 다르고 이름이 같다(M4200526.JPG / M4200526.ARW). 확인함.
--
-- 안전 규칙 (대표가 셀렉파일 폴더 보호를 특별히 요청)
--   · 삭제·이동 명령은 이 파일 어디에도 없다. 복사만 한다
--   · 가져오는 곳은 '/온더브라이드 백업/' 아래, 넣는 곳은 '/@ 연도 셀렉파일/' 아래로만
--   · autorename 이라 같은 이름이 있어도 덮어쓰지 않고 옆에 새로 만든다
--   · 복사할 때마다 기록을 남긴다

create table if not exists public.dropbox_copy_log (
  id          bigserial primary key,
  booking_id  uuid references public.bookings(id) on delete set null,
  dest        text not null,
  n_files     int  not null,
  created_at  timestamptz not null default now()
);
alter table public.dropbox_copy_log enable row level security;
revoke all on public.dropbox_copy_log from anon, authenticated;

-- ── 폴더 목록 (이어보기 포함) ────────────────────────────────
create or replace function public.admin_dbx_ls_req(p_path text, p_cursor text default null)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare tok text; req bigint;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_cursor is null and (p_path is null or p_path not like '/온더브라이드 백업/%') then
    raise exception '이 폴더는 읽을 수 없습니다';
  end if;
  tok := private.dbx_token();
  if tok is null then return jsonb_build_object('error', '드롭박스 연결이 준비되지 않았습니다.'); end if;
  select net.http_post(
    url := case when p_cursor is null then 'https://api.dropboxapi.com/2/files/list_folder'
                else 'https://api.dropboxapi.com/2/files/list_folder/continue' end,
    body := case when p_cursor is null then jsonb_build_object('path', p_path, 'limit', 2000)
                 else jsonb_build_object('cursor', p_cursor) end,
    headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
  ) into req;
  return jsonb_build_object('req', req);
end$fn$;
revoke all on function public.admin_dbx_ls_req(text, text) from public, anon;
grant execute on function public.admin_dbx_ls_req(text, text) to authenticated;

create or replace function public.admin_dbx_ls_res(p_req bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare st int; body jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select status_code, content::jsonb into st, body from net._http_response where id = p_req;
  if st is null then return jsonb_build_object('pending', true); end if;
  if st <> 200 then
    if body::text like '%not_found%' then return jsonb_build_object('missing', true); end if;
    return jsonb_build_object('error', coalesce(body->>'error_summary', st::text));
  end if;
  return jsonb_build_object(
    'entries', coalesce((select jsonb_agg(jsonb_build_object(
        'name', e->>'name', 'path', e->>'path_display', 'dir', (e->>'.tag') = 'folder'))
      from jsonb_array_elements(body->'entries') e), '[]'::jsonb),
    'cursor', body->>'cursor',
    'more', coalesce((body->>'has_more')::boolean, false));
end$fn$;
revoke all on function public.admin_dbx_ls_res(bigint) from public, anon;
grant execute on function public.admin_dbx_ls_res(bigint) to authenticated;

-- ── 복사 (한 번에 묶어서) ────────────────────────────────────
create or replace function public.admin_dbx_copy_req(p_booking_id uuid, p_dest text, p_files jsonb)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare tok text; req bigint; n int; bad int;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_dest is null or p_dest !~ '^/@ [0-9]{4} 셀렉파일/[^/]+$' then
    raise exception '넣는 곳은 "@ 연도 셀렉파일" 아래 폴더만 됩니다';
  end if;
  select count(*) into n from jsonb_array_elements_text(p_files);
  if n = 0 then raise exception '복사할 파일이 없습니다'; end if;
  if n > 500 then raise exception '한 번에 500장까지만 됩니다'; end if;
  -- 가져오는 곳이 백업 폴더 밖이면 통째로 거부
  select count(*) into bad from jsonb_array_elements_text(p_files) f
   where f not like '/온더브라이드 백업/%';
  if bad > 0 then raise exception '백업 폴더 밖의 파일은 다룰 수 없습니다'; end if;

  tok := private.dbx_token();
  if tok is null then return jsonb_build_object('error', '드롭박스 연결이 준비되지 않았습니다.'); end if;
  select net.http_post(
    url := 'https://api.dropboxapi.com/2/files/copy_batch_v2',
    body := jsonb_build_object(
      'autorename', true,                       -- 같은 이름이 있어도 덮지 않는다
      'entries', (select jsonb_agg(jsonb_build_object(
                    'from_path', f,
                    'to_path', p_dest || '/' || regexp_replace(f, '^.*/', '')))
                  from jsonb_array_elements_text(p_files) f)),
    headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
  ) into req;
  return jsonb_build_object('req', req, 'n', n);
end$fn$;
revoke all on function public.admin_dbx_copy_req(uuid, text, jsonb) from public, anon;
grant execute on function public.admin_dbx_copy_req(uuid, text, jsonb) to authenticated;

create or replace function public.admin_dbx_copy_res(p_req bigint, p_booking_id uuid, p_dest text, p_n int)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare st int; body jsonb; tag text; tok text; req2 bigint;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select status_code, content::jsonb into st, body from net._http_response where id = p_req;
  if st is null then return jsonb_build_object('pending', true); end if;
  if st <> 200 then return jsonb_build_object('error', coalesce(body->>'error_summary', st::text)); end if;

  tag := body->>'.tag';
  if tag = 'async_job_id' then
    -- 양이 많으면 드롭박스가 뒤에서 처리한다. 다 됐는지 물어볼 요청을 새로 띄운다
    tok := private.dbx_token();
    select net.http_post(
      url := 'https://api.dropboxapi.com/2/files/copy_batch/check_v2',
      body := jsonb_build_object('async_job_id', body->>'async_job_id'),
      headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
    ) into req2;
    return jsonb_build_object('again', req2);
  end if;
  if tag = 'in_progress' then return jsonb_build_object('pending', true); end if;

  insert into public.dropbox_copy_log (booking_id, dest, n_files) values (p_booking_id, p_dest, p_n);
  return jsonb_build_object('done', true, 'n', p_n, 'dest', p_dest);
end$fn$;
revoke all on function public.admin_dbx_copy_res(bigint, uuid, text, int) from public, anon;
grant execute on function public.admin_dbx_copy_res(bigint, uuid, text, int) to authenticated;
