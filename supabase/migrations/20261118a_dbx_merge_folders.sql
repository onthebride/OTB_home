-- 2인 촬영 — 메인·서브 폴더가 따로 떨어져 있으면 한 폴더로 합쳐 링크 하나로 보낸다.
-- (2026-11-18 대표 «그 해당날짜에 폴더를 만들어서 메인 서브 촬영 폴더를 거기로 옮긴뒤 링크를 만들어 보내는건 어때?» → «그걸 로직으로 돌리자»)
--
-- 한 예약에는 다운로드 링크가 하나뿐이라, 폴더가 둘이면 한쪽만 신부에게 갔다 (9/5 · 10/24).
-- 그날 폴더 안에 새 폴더를 만들고 두 폴더를 그 안으로 옮긴 뒤, 그 폴더로 링크를 만든다.
--
-- 안전 규칙
--   · 지우는 명령은 없다. 새 폴더 만들기(create_folder_v2)와 옮기기(move_batch_v2)뿐이다
--     (앱 권한에 지우기는 없다 — 이 파일이 잘못돼도 파일이 지워지지 않는다)
--   · 만들 곳·옮길 폴더·옮겨 갈 곳이 모두 «그 예식 날짜 폴더 바로 밑» 이어야 한다
--     (/온더브라이드 백업/YYYY년/MM월/YY.MM.DD/<이름>) — 다른 날·더 깊은 곳·백업 밖은 거부
--   · 2인 촬영 예약만, 옮기는 폴더 이름에 그 예약의 신랑·신부·계약자 이름이 들어 있어야 한다
--   · autorename 을 끈다 — 같은 이름이 있으면 덮거나 옆에 새로 만들지 않고 실패한다
--   · 옮길 때마다 기록을 남긴다 (public.dropbox_move_log) — 되돌릴 때 어디서 어디로 갔는지 본다
--   · 옮긴 폴더에 이미 만든 공유 링크는 드롭박스가 그대로 살려 둔다 (이미 나간 링크가 안 깨진다)

create table if not exists public.dropbox_move_log (
  id          bigserial primary key,
  booking_id  uuid references public.bookings(id) on delete set null,
  from_path   text not null,
  to_path     text not null,
  created_at  timestamptz not null default now()
);
alter table public.dropbox_move_log enable row level security;
revoke all on public.dropbox_move_log from anon, authenticated;

-- 그 예식 날짜 폴더 «바로 밑» 의 폴더 경로인가 (이름에 / 가 없고 비어 있지 않다)
create or replace function private.dbx_day_child(p_day text, p_path text)
returns boolean language sql immutable as $$
  select p_path is not null and p_day is not null
     and left(p_path, length(p_day) + 1) = p_day || '/'
     and length(p_path) > length(p_day) + 1
     and position('/' in substr(p_path, length(p_day) + 2)) = 0
$$;

-- 이 예약의 이름들 (신랑·신부·계약자) — 폴더 이름에 이 중 하나가 들어 있어야 한다
create or replace function private.dbx_names_hit(p_booking_id uuid, p_folder text)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.bookings b,
      lateral unnest(array[b.contractor_name, b.bride_name, b.groom_name]) n
    where b.id = p_booking_id and n is not null and btrim(n) <> ''
      and position(normalize(btrim(n), NFC) in normalize(p_folder, NFC)) > 0)
$$;
revoke all on function private.dbx_names_hit(uuid, text) from public, anon, authenticated;

-- ── ① 새 폴더 만들기 요청 ────────────────────────────────────
create or replace function public.admin_dbx_mkdir_req(p_booking_id uuid, p_name text)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare d date; ph text; tok text; req bigint; nm text; path text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select wedding_date, photographer into d, ph from public.bookings where id = p_booking_id;
  if d is null then raise exception '예식일이 없습니다'; end if;
  if ph is distinct from '2인 촬영' then raise exception '2인 촬영 예약만 합칠 수 있습니다'; end if;

  nm := btrim(coalesce(p_name, ''));
  if nm = '' or length(nm) > 120 or nm ~ '[/\\:*?"<>|]' or nm ~ '^\.' or nm ~ '[ .]$' then
    raise exception '폴더 이름이 올바르지 않습니다';
  end if;
  if not private.dbx_names_hit(p_booking_id, nm) then
    raise exception '폴더 이름에 신랑·신부 이름이 들어 있어야 합니다';
  end if;

  path := private.dbx_day_path(d) || '/' || nm;
  tok := private.dbx_token();
  if tok is null then return jsonb_build_object('error', '드롭박스 연결이 준비되지 않았습니다.'); end if;
  select net.http_post(
    url := 'https://api.dropboxapi.com/2/files/create_folder_v2',
    body := jsonb_build_object('path', path, 'autorename', false),
    headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
  ) into req;
  return jsonb_build_object('req', req, 'path', path);
end$fn$;
revoke all on function public.admin_dbx_mkdir_req(uuid, text) from public, anon;
grant execute on function public.admin_dbx_mkdir_req(uuid, text) to authenticated;

-- ── ② 새 폴더 응답 ───────────────────────────────────────────
-- 이미 같은 이름의 «폴더» 가 있으면 그대로 쓴다(앞서 만들다 끊긴 경우). 파일이면 거부.
create or replace function public.admin_dbx_mkdir_res(p_req bigint, p_path text)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare st int; body jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select status_code, content::jsonb into st, body from net._http_response where id = p_req;
  if st is null then return jsonb_build_object('pending', true); end if;
  if st = 200 then
    return jsonb_build_object('done', true, 'path', coalesce(body->'metadata'->>'path_display', p_path));
  end if;
  if coalesce(body->>'error_summary', '') like 'path/conflict/folder%' then
    return jsonb_build_object('done', true, 'exists', true, 'path', p_path);
  end if;
  return jsonb_build_object('error', coalesce(body->>'error_summary', st::text));
end$fn$;
revoke all on function public.admin_dbx_mkdir_res(bigint, text) from public, anon;
grant execute on function public.admin_dbx_mkdir_res(bigint, text) to authenticated;

-- ── ③ 폴더 옮기기 요청 (한 번에 묶어서) ──────────────────────
create or replace function public.admin_dbx_move_req(p_booking_id uuid, p_parent text, p_from jsonb)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare d date; ph text; day text; tok text; req bigint; n int; f text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select wedding_date, photographer into d, ph from public.bookings where id = p_booking_id;
  if d is null then raise exception '예식일이 없습니다'; end if;
  if ph is distinct from '2인 촬영' then raise exception '2인 촬영 예약만 합칠 수 있습니다'; end if;
  day := private.dbx_day_path(d);

  if jsonb_typeof(p_from) is distinct from 'array' then raise exception '옮길 폴더 목록이 올바르지 않습니다'; end if;
  select count(*) into n from jsonb_array_elements_text(p_from);
  if n < 1 or n > 4 then raise exception '한 번에 옮길 폴더는 1~4개입니다'; end if;
  if (select count(distinct lower(x)) from jsonb_array_elements_text(p_from) x) <> n then
    raise exception '같은 폴더가 두 번 들어 있습니다';
  end if;

  if not private.dbx_day_child(day, p_parent) then
    raise exception '합칠 폴더는 그 예식 날짜 폴더 바로 아래여야 합니다';
  end if;
  if not private.dbx_names_hit(p_booking_id, regexp_replace(p_parent, '^.*/', '')) then
    raise exception '합칠 폴더 이름에 신랑·신부 이름이 들어 있어야 합니다';
  end if;
  for f in select x from jsonb_array_elements_text(p_from) x loop
    if not private.dbx_day_child(day, f) then
      raise exception '옮길 폴더는 그 예식 날짜 폴더 바로 아래여야 합니다';
    end if;
    if lower(f) = lower(p_parent) then raise exception '폴더를 자기 안으로 옮길 수 없습니다'; end if;
    if not private.dbx_names_hit(p_booking_id, regexp_replace(f, '^.*/', '')) then
      raise exception '이 예약과 이름이 맞지 않는 폴더는 옮길 수 없습니다';
    end if;
  end loop;

  tok := private.dbx_token();
  if tok is null then return jsonb_build_object('error', '드롭박스 연결이 준비되지 않았습니다.'); end if;
  select net.http_post(
    url := 'https://api.dropboxapi.com/2/files/move_batch_v2',
    body := jsonb_build_object(
      'autorename', false,                       -- 같은 이름이 있어도 덮지 않는다
      'allow_ownership_transfer', false,
      'entries', (select jsonb_agg(jsonb_build_object(
                    'from_path', x, 'to_path', p_parent || '/' || regexp_replace(x, '^.*/', '')))
                  from jsonb_array_elements_text(p_from) x)),
    headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
  ) into req;
  return jsonb_build_object('req', req, 'n', n);
end$fn$;
revoke all on function public.admin_dbx_move_req(uuid, text, jsonb) from public, anon;
grant execute on function public.admin_dbx_move_req(uuid, text, jsonb) to authenticated;

-- ── ④ 옮기기 응답 — 폴더마다 성공했는지 세고, 성공한 것만 기록 ─
create or replace function public.admin_dbx_move_res(p_req bigint, p_booking_id uuid, p_parent text,
                                                     p_from jsonb, p_job text default null)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare st int; body jsonb; tag text; tok text; req2 bigint; job text; okn int; bad int; why text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select status_code, content::jsonb into st, body from net._http_response where id = p_req;
  if st is null then return jsonb_build_object('pending', true); end if;
  if st <> 200 then return jsonb_build_object('error', coalesce(body->>'error_summary', st::text)); end if;

  tag := body->>'.tag';

  -- 작업 전체가 실패했다
  if tag = 'failed' then
    return jsonb_build_object('error', '옮기지 못했습니다: ' || coalesce(body #>> '{failed,.tag}', body::text));
  end if;

  -- 다 됐다 — 폴더마다 본다. 요청한 차례 그대로 결과가 온다
  if tag = 'complete' or body ? 'entries' then
    select count(*) filter (where e->>'.tag' = 'success'),
           count(*) filter (where e->>'.tag' <> 'success'),
           min(coalesce(e #>> '{failure,relocation_error,.tag}', e #>> '{failure,.tag}')
               || coalesce('/' || (e #>> '{failure,relocation_error,from_lookup,.tag}'), ''))
             filter (where e->>'.tag' <> 'success')
      into okn, bad, why
      from jsonb_array_elements(body->'entries') e;

    -- 성공한 것만 기록한다 (결과는 요청한 차례 그대로 온다)
    insert into public.dropbox_move_log (booking_id, from_path, to_path)
    select p_booking_id, f.x, p_parent || '/' || regexp_replace(f.x, '^.*/', '')
      from jsonb_array_elements_text(p_from) with ordinality as f(x, i)
      join jsonb_array_elements(body->'entries') with ordinality as t(e, i) on t.i = f.i
     where t.e->>'.tag' = 'success';

    return jsonb_build_object('done', true, 'ok', coalesce(okn, 0), 'failed', coalesce(bad, 0), 'why', why);
  end if;

  -- 아직이면 다시 물어본다. in_progress 응답에는 작업번호가 안 담겨 오므로 받아 둔 것을 다시 쓴다
  if tag = 'async_job_id' or tag = 'in_progress' then
    job := coalesce(body->>'async_job_id', p_job);
    if job is null then return jsonb_build_object('error', '옮기기 상태를 확인할 수 없습니다.'); end if;
    tok := private.dbx_token();
    if tok is null then return jsonb_build_object('error', '드롭박스 연결이 끊겼습니다.'); end if;
    select net.http_post(
      url := 'https://api.dropboxapi.com/2/files/move_batch/check_v2',
      body := jsonb_build_object('async_job_id', job),
      headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
    ) into req2;
    return jsonb_build_object('again', req2, 'job', job);
  end if;

  return jsonb_build_object('error', '알 수 없는 응답: ' || coalesce(tag, '?'));
end$fn$;
revoke all on function public.admin_dbx_move_res(bigint, uuid, text, jsonb, text) from public, anon;
grant execute on function public.admin_dbx_move_res(bigint, uuid, text, jsonb, text) to authenticated;
