-- 자동으로 넣는 폴더 이름을 «YYYY 자동셀렉» 으로. (대표 요청)
--
-- 손으로 하던 셀렉과 프로그램이 만든 셀렉을 폴더 이름으로 갈라둔다.
--   손으로  : @ 2026 셀렉파일 / @ 2025 셀렉파일 / 2024 셀렉파일
--   자동으로: 2026 자동셀렉   (해가 바뀌면 2027 자동셀렉)
--
-- 넣는 곳 규칙과 폴더 목록에 '자동셀렉' 을 함께 받아준다.
-- 예전 '셀렉파일' 도 그대로 둔다 — 이미 넣어둔 것들이 있고, 대표가 골라 쓸 수 있어야 한다.

create or replace function public.admin_dbx_copy_req(p_booking_id uuid, p_dest text, p_files jsonb)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare tok text; req bigint; n int; bad int;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  -- 맨 위 칸이 '…셀렉파일' 이나 '…자동셀렉' 인 폴더의 바로 아래 한 칸에만 넣는다
  if p_dest is null or p_dest !~ '^/[^/]*(셀렉파일|자동셀렉)/[^/]+$' then
    raise exception '넣는 곳은 "셀렉파일" 또는 "자동셀렉" 폴더 바로 아래만 됩니다';
  end if;
  select count(*) into n from jsonb_array_elements_text(p_files);
  if n = 0 then raise exception '복사할 파일이 없습니다'; end if;
  if n > 500 then raise exception '한 번에 500장까지만 됩니다'; end if;
  select count(*) into bad from jsonb_array_elements_text(p_files) f
   where f not like '/온더브라이드 백업/%';
  if bad > 0 then raise exception '백업 폴더 밖의 파일은 다룰 수 없습니다'; end if;

  tok := private.dbx_token();
  if tok is null then return jsonb_build_object('error', '드롭박스 연결이 준비되지 않았습니다.'); end if;
  select net.http_post(
    url := 'https://api.dropboxapi.com/2/files/copy_batch_v2',
    body := jsonb_build_object(
      'autorename', true,
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

create or replace function public.admin_dbx_up_req(p_dest text, p_names jsonb)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare tok text; n int; nm text; req bigint; out jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_dest is null or p_dest !~ '^/[^/]*(셀렉파일|자동셀렉)/[^/]+$' then
    raise exception '넣는 곳은 "셀렉파일" 또는 "자동셀렉" 폴더 바로 아래만 됩니다';
  end if;
  select count(*) into n from jsonb_array_elements_text(p_names);
  if n = 0 then raise exception '올릴 파일이 없습니다'; end if;
  if n > 8 then raise exception '한 번에 8장까지만 됩니다'; end if;

  tok := private.dbx_token();
  if tok is null then return jsonb_build_object('error', '드롭박스 연결이 준비되지 않았습니다.'); end if;

  for nm in select * from jsonb_array_elements_text(p_names) loop
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

-- 폴더 목록에도 '자동셀렉' 을 넣는다. 자동 폴더가 위로 오게 둔다.
create or replace function public.admin_dbx_roots_res(p_req bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare st int; body jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select status_code, content::jsonb into st, body from net._http_response where id = p_req;
  if st is null then return jsonb_build_object('pending', true); end if;
  if st <> 200 then return jsonb_build_object('error', coalesce(body->>'error_summary', st::text)); end if;
  -- 자동셀렉이 먼저, 그 안에서 연도가 큰 것부터.
  -- 이름순으로만 하면 '@ 2026 셀렉파일' 이 '2024 셀렉파일' 뒤로 밀린다
  return jsonb_build_object('roots', coalesce((
    select jsonb_agg(e->>'path_display'
             order by (e->>'name' not like '%자동셀렉'),
                      nullif(regexp_replace(e->>'name', '[^0-9]', '', 'g'), '')::int desc nulls last,
                      e->>'name' desc)
    from jsonb_array_elements(body->'entries') e
    where e->>'.tag' = 'folder'
      and (e->>'name' like '%셀렉파일' or e->>'name' like '%자동셀렉')), '[]'::jsonb));
end$fn$;
revoke all on function public.admin_dbx_roots_res(bigint) from public, anon;
grant execute on function public.admin_dbx_roots_res(bigint) to authenticated;
