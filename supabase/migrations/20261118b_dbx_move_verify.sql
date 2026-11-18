-- 2인 촬영 폴더 합치기 — 드롭박스가 «internal_error» 로 끝맺어도 실제로 옮겨졌는지 직접 읽어 확인한다.
-- (2026-11-18 대표 «드롭박스 보면 옮겨지긴 했는데 여긴 에러가 뜨네?» — 첫 실제 실행)
--
-- 옮기기(move_batch_v2)가 끝에 가서 폴더마다 «internal_error» 를 돌려줬는데 폴더는 이미 옮겨져 있었다.
-- 드롭박스 설명서가 이 오류를 «일이 끝났는지 직접 확인하고 안 됐으면 다시 하라» 는 뜻으로 적어 둔다.
-- 20261118a 의 화면은 그 말만 듣고 멈춰서, 옮겨 놓고도 링크 만들기까지 못 갔다.
--
-- 확인하는 법: 새 폴더 안과 그날 폴더 바로 밑을 드롭박스에 읽어 온다(list_folder, 읽기뿐).
--   «새 폴더 안에 있고 + 그날 폴더 바로 밑에는 없다» 일 때만 옮겨진 것으로 센다.
--   (못 본 것·더 있는 목록의 뒷부분은 «안 옮겨짐» 으로 센다 — 틀려도 안전한 쪽으로 틀린다)
--
-- 안전 규칙 — 20261118a 와 같다
--   · 드롭박스에 보내는 것은 폴더 목록 읽기뿐이다 (지우기·옮기기·만들기 없음)
--   · 폴더 경로가 «그 예식 날짜 폴더 바로 밑» 이고 이름에 이 예약의 이름이 든 것만 받는다
--   · 확인된 것만 public.dropbox_move_log 에 기록한다 (이미 기록한 것은 두 번 적지 않는다)

-- 옮기기 요청(admin_dbx_move_req)이 보는 것과 같은 검사를 한 곳에 — 확인 응답이 받는 경로도 같은 규칙으로 막는다
create or replace function private.dbx_move_args(p_booking_id uuid, p_parent text, p_from jsonb)
returns void language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare d date; ph text; day text; n int; f text;
begin
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
end$fn$;
revoke all on function private.dbx_move_args(uuid, text, jsonb) from public, anon, authenticated;

-- ── ① 확인 요청 — 새 폴더 안과 그날 폴더 바로 밑을 읽어 오게 한다 ──
create or replace function public.admin_dbx_move_verify_req(p_booking_id uuid, p_parent text)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare d date; ph text; day text; tok text; r_parent bigint; r_day bigint;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select wedding_date, photographer into d, ph from public.bookings where id = p_booking_id;
  if d is null then raise exception '예식일이 없습니다'; end if;
  if ph is distinct from '2인 촬영' then raise exception '2인 촬영 예약만 합칠 수 있습니다'; end if;
  day := private.dbx_day_path(d);
  if not private.dbx_day_child(day, p_parent) then
    raise exception '합칠 폴더는 그 예식 날짜 폴더 바로 아래여야 합니다';
  end if;
  if not private.dbx_names_hit(p_booking_id, regexp_replace(p_parent, '^.*/', '')) then
    raise exception '합칠 폴더 이름에 신랑·신부 이름이 들어 있어야 합니다';
  end if;

  tok := private.dbx_token();
  if tok is null then return jsonb_build_object('error', '드롭박스 연결이 준비되지 않았습니다.'); end if;
  select net.http_post(
    url := 'https://api.dropboxapi.com/2/files/list_folder',
    body := jsonb_build_object('path', p_parent, 'limit', 2000),
    headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
  ) into r_parent;
  select net.http_post(
    url := 'https://api.dropboxapi.com/2/files/list_folder',
    body := jsonb_build_object('path', day, 'limit', 2000),
    headers := jsonb_build_object('Authorization', 'Bearer ' || tok, 'Content-Type', 'application/json')
  ) into r_day;
  return jsonb_build_object('req_parent', r_parent, 'req_day', r_day);
end$fn$;
revoke all on function public.admin_dbx_move_verify_req(uuid, text) from public, anon;
grant execute on function public.admin_dbx_move_verify_req(uuid, text) to authenticated;

-- ── ② 확인 응답 — 폴더마다 옮겨졌는지 세고, 옮겨진 것만 기록 ──
create or replace function public.admin_dbx_move_verify_res(p_req_parent bigint, p_req_day bigint, p_booking_id uuid,
                                                            p_parent text, p_from jsonb)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare st1 int; st2 int; b1 jsonb; b2 jsonb; f text; base text; okn int := 0; rest text[] := '{}';
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  perform private.dbx_move_args(p_booking_id, p_parent, p_from);

  select status_code, content::jsonb into st1, b1 from net._http_response where id = p_req_parent;
  select status_code, content::jsonb into st2, b2 from net._http_response where id = p_req_day;
  if st1 is null or st2 is null then return jsonb_build_object('pending', true); end if;
  if st1 <> 200 then return jsonb_build_object('error', coalesce(b1->>'error_summary', st1::text)); end if;
  if st2 <> 200 then return jsonb_build_object('error', coalesce(b2->>'error_summary', st2::text)); end if;

  for f in select x from jsonb_array_elements_text(p_from) x loop
    base := regexp_replace(f, '^.*/', '');
    if exists (select 1 from jsonb_array_elements(b1->'entries') e
                where e->>'.tag' = 'folder' and lower(normalize(e->>'name', NFC)) = lower(normalize(base, NFC)))
       and not exists (select 1 from jsonb_array_elements(b2->'entries') e
                where e->>'.tag' = 'folder' and lower(normalize(e->>'name', NFC)) = lower(normalize(base, NFC))) then
      okn := okn + 1;
      insert into public.dropbox_move_log (booking_id, from_path, to_path)
      select p_booking_id, f, p_parent || '/' || base
       where not exists (select 1 from public.dropbox_move_log l
                          where l.booking_id = p_booking_id and l.from_path = f and l.to_path = p_parent || '/' || base);
    else
      rest := rest || base;
    end if;
  end loop;

  return jsonb_build_object('done', true, 'ok', okn, 'failed', coalesce(array_length(rest, 1), 0), 'left', to_jsonb(rest));
end$fn$;
revoke all on function public.admin_dbx_move_verify_res(bigint, bigint, uuid, text, jsonb) from public, anon;
grant execute on function public.admin_dbx_move_verify_res(bigint, bigint, uuid, text, jsonb) to authenticated;
