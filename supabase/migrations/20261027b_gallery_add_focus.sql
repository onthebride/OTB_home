/* 갤러리 사진을 올릴 때 네모로 자를 자리도 같이 적는다 (대표 2026-10-27 «1번이 나을거 같은뎅» —
   새로 올리는 사진도 올리는 순간 얼굴 쪽으로 잘리게).

   관리자 화면이 올리기 전에 얼굴을 찾아(face-focus.js) focus_x·focus_y 를 실어 보낸다.
   ⚠ 이 값 때문에 사진 올리기가 실패하면 안 된다 — 0~100 정수 둘이 **다** 있을 때만 적고,
     아니면(없음 · 글자 · 소수 · 범위 밖) 둘 다 비운다 = 안 본 사진, 홈에서는 예전처럼 가운데.
     check 제약(gallery_focus_range)에 걸려 터지는 일이 없게 여기서 먼저 거른다.
   ⚠ 나머지(작가 확인 · 넣는 칸)는 20260825h 그대로다 */

create or replace function public.admin_gallery_add(payload jsonb)
returns public.gallery language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare r public.gallery; sid uuid; fx int; fy int;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  sid := nullif(payload->>'staff_id', '')::uuid;
  if sid is not null and not exists (select 1 from public.staff where id = sid) then
    raise exception 'staff not found';
  end if;
  if coalesce(payload->>'focus_x', '') ~ '^[0-9]{1,3}$' and coalesce(payload->>'focus_y', '') ~ '^[0-9]{1,3}$' then
    fx := (payload->>'focus_x')::int;
    fy := (payload->>'focus_y')::int;
    if fx > 100 or fy > 100 then fx := null; fy := null; end if;
  end if;
  insert into public.gallery (image_path, image_url, venue, sort, staff_id, focus_x, focus_y)
  values (payload->>'image_path', payload->>'image_url', nullif(payload->>'venue',''),
          coalesce((payload->>'sort')::int, 0), sid, fx, fy)
  returning * into r;
  return r;
end$$;
