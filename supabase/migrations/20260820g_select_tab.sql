-- 셀렉 전용 탭 — 예약을 찾아 들어가지 않고 한 곳에서 끝낸다.
--
-- 넣는 곳 규칙을 실제 드롭박스에 맞춘다. 처음엔 '/@ 연도 셀렉파일' 만 허용했는데,
-- 실제로는 '2024 셀렉파일'(@ 없음)도 있고, 무엇보다 연도가 예식 연도가 아니었다.
-- '@ 2026 셀렉파일' 안에 2025년 예식 231개, 2026년 예식 85개가 같이 들어 있다 —
-- 예식 연도가 아니라 '지금 작업하는 폴더'였다. 그래서 연도를 코드가 정하지 않고
-- 실제 있는 폴더 중에서 고르게 한다.
--
-- 대신 범위는 여전히 좁게 잠근다: 맨 위 칸의 '…셀렉파일' 폴더 바로 아래 한 칸까지만.

create or replace function public.admin_dbx_copy_req(p_booking_id uuid, p_dest text, p_files jsonb)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare tok text; req bigint; n int; bad int;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  -- 맨 위 칸이 '…셀렉파일' 인 폴더의 바로 아래 한 칸에만 넣는다
  if p_dest is null or p_dest !~ '^/[^/]*셀렉파일/[^/]+$' then
    raise exception '넣는 곳은 "셀렉파일" 폴더 바로 아래만 됩니다';
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

-- ── 넣을 수 있는 셀렉파일 폴더 목록 ──────────────────────────
-- 맨 위 칸만 읽는다. 다른 폴더 이름은 돌려주지 않는다.
create or replace function public.admin_dbx_roots_req()
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare tok text; req bigint;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  tok := private.dbx_token();
  if tok is null then return jsonb_build_object('error', '드롭박스 연결이 준비되지 않았습니다.'); end if;
  select net.http_post(
    url := 'https://api.dropboxapi.com/2/files/list_folder',
    body := jsonb_build_object('path', '', 'limit', 200),
    headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
  ) into req;
  return jsonb_build_object('req', req);
end$fn$;
revoke all on function public.admin_dbx_roots_req() from public, anon;
grant execute on function public.admin_dbx_roots_req() to authenticated;

create or replace function public.admin_dbx_roots_res(p_req bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare st int; body jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select status_code, content::jsonb into st, body from net._http_response where id = p_req;
  if st is null then return jsonb_build_object('pending', true); end if;
  if st <> 200 then return jsonb_build_object('error', coalesce(body->>'error_summary', st::text)); end if;
  -- 연도가 큰 것부터. 이름순으로 하면 '@ 2026 셀렉파일' 이 '2024 셀렉파일' 뒤로 밀린다
  return jsonb_build_object('roots', coalesce((
    select jsonb_agg(e->>'path_display'
             order by nullif(regexp_replace(e->>'name', '[^0-9]', '', 'g'), '')::int desc nulls last,
                      e->>'name' desc)
    from jsonb_array_elements(body->'entries') e
    where e->>'.tag' = 'folder' and e->>'name' like '%셀렉파일'), '[]'::jsonb));
end$fn$;
revoke all on function public.admin_dbx_roots_res(bigint) from public, anon;
grant execute on function public.admin_dbx_roots_res(bigint) to authenticated;

-- ── 최근에 복사한 것 ─────────────────────────────────────────
create or replace function public.admin_dbx_copy_recent()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $fn$
  select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'at', l.created_at, 'dest', l.dest, 'n', l.n_files,
      'who', b.contractor_name, 'day', b.wedding_date) x
    from public.dropbox_copy_log l
    left join public.bookings b on b.id = l.booking_id
    where auth.uid() is not null
    order by l.created_at desc limit 12) s;
$fn$;
revoke all on function public.admin_dbx_copy_recent() from public, anon;
grant execute on function public.admin_dbx_copy_recent() to authenticated;
