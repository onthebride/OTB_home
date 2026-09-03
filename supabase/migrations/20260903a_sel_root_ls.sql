-- 자동셀렉 폴더 안을 셀 수 있게 한다 (대표 2026-09-03
--   «드롭박스에 넘버링 되는거 되고 있는거 맞아?»)
--
-- 안 되고 있었다. 어제 만든 번호 붙이기가 한 번도 붙은 적이 없다.
--
-- 까닭: 폴더 목록을 읽는 admin_dbx_ls_req 는 **백업 폴더만** 읽게 막아 두었다.
--   if p_path not like '/온더브라이드 백업/%' then raise exception '이 폴더는 읽을 수 없습니다'
-- 번호를 매기려면 「2026 자동셀렉」 안을 세어야 하는데 거기서 막혔다.
-- 그리고 내가 «못 세면 번호 없이 간다» 로 만들어 둬서 **조용히** 번호 없이 나갔다.
--
-- ⚠ 그 빗장은 일부러 걸어둔 것이라 넓히지 않는다. 대신 **자동셀렉 폴더만** 읽는
--   길을 따로 낸다. 경로를 「/YYYY 자동셀렉」 꼴로만 받는다 — 그 밖은 못 읽는다.

drop function if exists public.admin_dbx_sel_ls_req(text);
create or replace function public.admin_dbx_sel_ls_req(p_path text)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp' as $$
declare tok text; req bigint;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  -- ⚠ 「/YYYY 자동셀렉」 하나만 받는다. 다른 폴더는 여기로 못 지나간다
  if p_path is null or p_path !~ '^/[0-9]{4} 자동셀렉$' then
    raise exception '자동셀렉 폴더만 읽을 수 있습니다';
  end if;
  tok := private.dbx_token();
  if tok is null then return jsonb_build_object('error', '드롭박스 연결이 준비되지 않았습니다.'); end if;
  select net.http_post(
    url := 'https://api.dropboxapi.com/2/files/list_folder',
    -- 번호를 매기는 데만 쓴다. 폴더 이름만 있으면 되므로 한 번에 다 받는다
    body := jsonb_build_object('path', p_path, 'limit', 2000),
    headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
  ) into req;
  return jsonb_build_object('req', req);
end$$;
revoke all on function public.admin_dbx_sel_ls_req(text) from public, anon;
grant execute on function public.admin_dbx_sel_ls_req(text) to authenticated;
