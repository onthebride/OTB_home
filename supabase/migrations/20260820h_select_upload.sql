-- 신부가 보낸 JPG 도 셀렉 폴더에 같이 넣는다.
--
-- 지금까지는 이름만 읽었다. 이제 파일도 올려야 하는데, 파일을 우리 서버로 받았다가
-- 다시 올리면 느리고 쓸데없다. 드롭박스가 '임시 업로드 링크'를 내주므로,
-- 서버는 경로를 정해 링크만 발급하고 파일은 대표 PC 에서 드롭박스로 곧장 간다.
--   · 토큰은 서버 밖으로 안 나간다 — 링크는 그 경로 한 곳에만 쓸 수 있고 4시간 뒤 만료
--   · 경로는 서버가 정한다. 화면이 아무 데나 쓰라고 시킬 수 없다
--   · mode=add + autorename 이라 이미 있는 파일을 덮지 않는다
--
-- 한 번에 여러 장을 받되 8개까지만 — 40개를 한꺼번에 요청하면 드롭박스가 막는다(429, 확인함).

create or replace function public.admin_dbx_up_req(p_dest text, p_names jsonb)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare tok text; n int; nm text; req bigint; out jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  -- 넣는 곳은 '…셀렉파일' 폴더 바로 아래 한 칸 (복사와 같은 규칙)
  if p_dest is null or p_dest !~ '^/[^/]*셀렉파일/[^/]+$' then
    raise exception '넣는 곳은 "셀렉파일" 폴더 바로 아래만 됩니다';
  end if;
  select count(*) into n from jsonb_array_elements_text(p_names);
  if n = 0 then raise exception '올릴 파일이 없습니다'; end if;
  if n > 8 then raise exception '한 번에 8장까지만 됩니다'; end if;

  tok := private.dbx_token();
  if tok is null then return jsonb_build_object('error', '드롭박스 연결이 준비되지 않았습니다.'); end if;

  for nm in select * from jsonb_array_elements_text(p_names) loop
    -- 파일 이름에 경로를 섞어 다른 폴더로 새는 것을 막는다
    if nm is null or nm = '' or nm like '%/%' or nm like '%\%' or nm = '.' or nm = '..' then
      raise exception '파일 이름이 올바르지 않습니다: %', nm;
    end if;
    select net.http_post(
      url := 'https://api.dropboxapi.com/2/files/get_temporary_upload_link',
      body := jsonb_build_object('commit_info', jsonb_build_object(
        'path', p_dest || '/' || nm, 'mode', 'add', 'autorename', true)),
      headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
    ) into req;
    out := out || jsonb_build_object('name', nm, 'req', req);
  end loop;
  return jsonb_build_object('reqs', out);
end$fn$;
revoke all on function public.admin_dbx_up_req(text, jsonb) from public, anon;
grant execute on function public.admin_dbx_up_req(text, jsonb) to authenticated;

create or replace function public.admin_dbx_up_res(p_reqs jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare e jsonb; st int; body jsonb; out jsonb := '[]'::jsonb; pend boolean := false;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  for e in select * from jsonb_array_elements(p_reqs) loop
    select status_code, content::jsonb into st, body
      from net._http_response where id = (e->>'req')::bigint;
    if st is null then pend := true;
    elsif st = 200 then out := out || jsonb_build_object('name', e->>'name', 'url', body->>'link');
    else out := out || jsonb_build_object('name', e->>'name',
                         'error', coalesce(body->>'error_summary', st::text));
    end if;
  end loop;
  if pend then return jsonb_build_object('pending', true); end if;
  return jsonb_build_object('links', out);
end$fn$;
revoke all on function public.admin_dbx_up_res(jsonb) from public, anon;
grant execute on function public.admin_dbx_up_res(jsonb) to authenticated;

-- 올린 것도 기록에 남긴다 — 뭘 넣었는지 나중에 봐야 하니까
alter table public.dropbox_copy_log add column if not exists n_uploaded int not null default 0;

create or replace function public.admin_dbx_up_log(p_booking_id uuid, p_dest text, p_n int)
returns void language plpgsql security definer set search_path = public, pg_temp as $fn$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  insert into public.dropbox_copy_log (booking_id, dest, n_files, n_uploaded)
  values (p_booking_id, p_dest, 0, greatest(coalesce(p_n, 0), 0));
end$fn$;
revoke all on function public.admin_dbx_up_log(uuid, text, int) from public, anon;
grant execute on function public.admin_dbx_up_log(uuid, text, int) to authenticated;

create or replace function public.admin_dbx_copy_recent()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $fn$
  select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'at', l.created_at, 'dest', l.dest, 'n', l.n_files, 'up', l.n_uploaded,
      'who', b.contractor_name, 'day', b.wedding_date) x
    from public.dropbox_copy_log l
    left join public.bookings b on b.id = l.booking_id
    where auth.uid() is not null
    order by l.created_at desc limit 12) s;
$fn$;
revoke all on function public.admin_dbx_copy_recent() from public, anon;
grant execute on function public.admin_dbx_copy_recent() to authenticated;

-- 한 번 넣은 것은 기록도 한 줄로. 복사할 때 올린 장수도 같이 적는다.
-- (기본값이 붙은 매개변수를 더하면 예전 판과 헷갈리므로 먼저 지운다)
drop function if exists public.admin_dbx_copy_res(bigint, uuid, text, int, text);

create or replace function public.admin_dbx_copy_res(p_req bigint, p_booking_id uuid, p_dest text,
                                                     p_n int, p_job text default null,
                                                     p_up int default 0)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare st int; body jsonb; tag text; tok text; req2 bigint; job text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select status_code, content::jsonb into st, body from net._http_response where id = p_req;
  if st is null then return jsonb_build_object('pending', true); end if;
  if st <> 200 then return jsonb_build_object('error', coalesce(body->>'error_summary', st::text)); end if;

  tag := body->>'.tag';

  -- 다 됐다
  if tag = 'complete' or body ? 'entries' then
    insert into public.dropbox_copy_log (booking_id, dest, n_files, n_uploaded)
    values (p_booking_id, p_dest, p_n, greatest(coalesce(p_up, 0), 0));
    return jsonb_build_object('done', true, 'n', p_n, 'dest', p_dest);
  end if;

  -- 아직이면 다시 물어본다. in_progress 응답에는 작업번호가 안 담겨 오므로 받아 둔 것을 다시 쓴다
  if tag = 'async_job_id' or tag = 'in_progress' then
    job := coalesce(body->>'async_job_id', p_job);
    if job is null then return jsonb_build_object('error', '복사 상태를 확인할 수 없습니다.'); end if;
    tok := private.dbx_token();
    if tok is null then return jsonb_build_object('error', '드롭박스 연결이 끊겼습니다.'); end if;
    select net.http_post(
      url := 'https://api.dropboxapi.com/2/files/copy_batch/check_v2',
      body := jsonb_build_object('async_job_id', job),
      headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
    ) into req2;
    return jsonb_build_object('again', req2, 'job', job);
  end if;

  return jsonb_build_object('error', '알 수 없는 응답: ' || coalesce(tag, '?'));
end$fn$;
revoke all on function public.admin_dbx_copy_res(bigint, uuid, text, int, text, int) from public, anon;
grant execute on function public.admin_dbx_copy_res(bigint, uuid, text, int, text, int) to authenticated;
