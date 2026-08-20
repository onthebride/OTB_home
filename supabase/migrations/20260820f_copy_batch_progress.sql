-- 복사가 오래 걸릴 때 이어서 확인하기.
--
-- 드롭박스는 여러 장을 복사하면 async_job_id 를 주고 뒤에서 처리한다. 확인해보면 한동안 in_progress 다.
-- 그런데 in_progress 응답에는 job id 가 안 담겨 온다. 그래서 job id 를 화면에 돌려주고,
-- 다음 확인 때 다시 받아 쓴다. 안 그러면 같은 응답만 계속 읽으며 제자리를 돈다.
create or replace function public.admin_dbx_copy_res(p_req bigint, p_booking_id uuid, p_dest text,
                                                     p_n int, p_job text default null)
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
    insert into public.dropbox_copy_log (booking_id, dest, n_files) values (p_booking_id, p_dest, p_n);
    return jsonb_build_object('done', true, 'n', p_n, 'dest', p_dest);
  end if;

  -- 아직이면 다시 물어본다
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
revoke all on function public.admin_dbx_copy_res(bigint, uuid, text, int, text) from public, anon;
grant execute on function public.admin_dbx_copy_res(bigint, uuid, text, int, text) to authenticated;
