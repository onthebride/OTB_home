-- 복사가 일부 실패해도 «다 됐다» 고 말하던 것을 고친다.
--
-- files/copy_batch_v2 는 여러 장을 한 번에 옮기고, 끝나면 장마다 결과를 준다.
--   { ".tag": "complete", "entries": [ {".tag":"success",…}, {".tag":"failure", "failure":{…}}, … ] }
-- 그런데 우리는 'complete' 만 보고 요청한 장수를 그대로 «복사했습니다» 로 돌려주고 있었다.
-- 한 장이 실패해도 화면에는 «40장 복사했습니다» 라고 떴다. 나중에 폴더를 열어봐야 안다.
--
-- 이제 장마다 세어서, 실패한 게 있으면 그 수와 첫 사유를 함께 돌려준다.

create or replace function public.admin_dbx_copy_res(p_req bigint, p_booking_id uuid, p_dest text,
                                                     p_n int, p_job text default null,
                                                     p_up int default 0)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare st int; body jsonb; tag text; tok text; req2 bigint; job text;
        okn int; bad int; why text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select status_code, content::jsonb into st, body from net._http_response where id = p_req;
  if st is null then return jsonb_build_object('pending', true); end if;
  if st <> 200 then return jsonb_build_object('error', coalesce(body->>'error_summary', st::text)); end if;

  tag := body->>'.tag';

  -- 다 됐다 — 장마다 성공했는지 본다
  if tag = 'complete' or body ? 'entries' then
    select count(*) filter (where e->>'.tag' = 'success'),
           count(*) filter (where e->>'.tag' <> 'success'),
           min(e->'failure'->>'.tag') filter (where e->>'.tag' <> 'success')
      into okn, bad, why
      from jsonb_array_elements(body->'entries') e;

    okn := coalesce(okn, p_n);
    bad := coalesce(bad, 0);

    insert into public.dropbox_copy_log (booking_id, dest, n_files, n_uploaded)
    values (p_booking_id, p_dest, okn, greatest(coalesce(p_up, 0), 0));

    return jsonb_build_object('done', true, 'n', okn, 'dest', p_dest,
                              'failed', bad, 'why', why);
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
