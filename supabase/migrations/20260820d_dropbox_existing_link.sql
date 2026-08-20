-- 이미 공유 링크가 있는 폴더 처리.
--
-- 드롭박스는 링크가 이미 있으면 만들기를 거부하는데, 그 응답에 기존 링크를 담아주지 않는다.
--   {"error": {".tag": "shared_link_already_exists"}, "error_summary": "shared_link_already_exists/"}
-- 그래서 그때는 목록을 따로 물어서 기존 링크를 꺼내 쓴다.
-- 한 번 공유한 예식을 다시 눌렀을 때(폴더를 바꿔 다시 만들 때 등) 걸리는 경우다.
create or replace function public.admin_dbx_share_res(p_req bigint, p_booking_id uuid, p_path text)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare st int; body jsonb; link text; tok text; req2 bigint;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select status_code, content::jsonb into st, body from net._http_response where id = p_req;
  if st is null then return jsonb_build_object('pending', true); end if;

  if st = 200 then
    -- 만들기 응답이면 url, 목록 응답이면 links[0].url
    link := coalesce(body->>'url', body #>> '{links,0,url}');
  elsif body::text like '%shared_link_already_exists%' then
    -- 기존 링크를 물어보고, 화면은 그 요청을 이어서 기다린다
    tok := private.dbx_token();
    if tok is null then return jsonb_build_object('error', '드롭박스 연결이 끊겼습니다. 잠시 후 다시 눌러주세요.'); end if;
    select net.http_post(
      url := 'https://api.dropboxapi.com/2/sharing/list_shared_links',
      body := jsonb_build_object('path', p_path, 'direct_only', true),
      headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
    ) into req2;
    return jsonb_build_object('relist', req2);
  end if;

  if link is null then return jsonb_build_object('error', coalesce(body->>'error_summary', st::text)); end if;

  -- dl=1 로 바꾸지 않는다. 폴더 전체를 zip 으로 묶다 대용량에서 실패한다.
  update public.bookings set download_link = link where id = p_booking_id;
  insert into public.dropbox_links (booking_id, path, url) values (p_booking_id, p_path, link)
    on conflict (booking_id) do update set path = excluded.path, url = excluded.url, created_at = now();
  return jsonb_build_object('url', link);
end$fn$;
revoke all on function public.admin_dbx_share_res(bigint, uuid, text) from public, anon;
grant execute on function public.admin_dbx_share_res(bigint, uuid, text) to authenticated;
