-- 작가가 자기 갤러리 사진을 캘린더에서 본다 (대표 2026-09-09
--   «우리 갤러리에 나오는것들 작가들은 자기 사진을 작가 캘린더에서 볼 수 있게 해줄 수 있어?»
--   «크게보이게만 해줘»)
--
-- ⚠ 새로 여는 것이 아니다. 이 사진들은 이미 홈 갤러리에 공개돼 있다(gallery_public).
--   여기서는 **자기 것만** 골라 보여줄 뿐이다.
-- ⚠ 작가는 로그인 없이 링크로 연다. 그래서 anon 이 부를 수 있어야 한다 —
--   다른 staff_* 함수들과 같다.
-- ⚠ 남의 사진이 섞이면 안 된다. staff_id 로만 고른다.
-- ⚠ 「크게 보이게만」 — 내려받기는 안 연다. 내려받을 거리(원본 경로 image_path)를
--   따로 주지 않는다. 화면에 쓰는 주소만 준다.

create or replace function public.staff_gallery(p_staff_id uuid)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp' as $$
declare st public.staff; res jsonb;
begin
  select * into st from public.staff where id = p_staff_id and coalesce(active, false);
  if not found then raise exception 'staff not found'; end if;

  select jsonb_build_object(
    'n', (select count(*) from public.gallery g where g.staff_id = p_staff_id),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('id', g.id, 'image_url', g.image_url, 'venue', g.venue)
             order by g.sort asc, g.created_at desc)
        from public.gallery g where g.staff_id = p_staff_id), '[]'::jsonb))
  into res;
  return res;
end$$;
revoke all on function public.staff_gallery(uuid) from public;
grant execute on function public.staff_gallery(uuid) to anon, authenticated;
