/* 홈 갤러리 네모 썸네일 — 얼굴이 잘리지 않게 자르는 자리 (대표 2026-10-27
   «이 갤러리 섬네일이 좀 자기 맘대로넹 얼굴 위주로 되게 안되나?»)

   무엇이 문제였나 — 썸네일은 사진 한가운데를 네모로 자른다(object-fit: cover).
   세로로 긴 사진(2:3, 354장)은 위아래 18%씩 잘려 나가서, 얼굴이 위쪽에 있으면 머리가 잘렸다.

   사진마다 얼굴을 찾아(OpenCV YuNet, 이 PC 에서 돌린다) 자를 자리를 적어 둔다:
   · focus_x · focus_y — CSS object-position 의 % (0~100). 50·50 = 한가운데 = 예전과 같다
   · **얼굴이 잘릴 때만** 옮긴다. 나머지는 50·50 — 작가가 잡은 그대로 둔다
     (예식장별로 고르는 갤러리라 샹들리에·홀이 보이는 게 값이다)
   · null = 아직 안 본 사진. 화면은 한가운데로 자른다 (예전과 같다)

   ⚠ 사진 자체는 안 건드린다. 크게 보기(라이트박스)는 그대로 전체가 보인다.
   ⚠ gallery_public 은 손님(anon)이 부른다. 늘어난 두 칸은 숫자뿐이다 */

alter table public.gallery add column if not exists focus_x smallint;
alter table public.gallery add column if not exists focus_y smallint;
do $$ begin
  alter table public.gallery add constraint gallery_focus_range
    check (focus_x between 0 and 100 and focus_y between 0 and 100);
exception when duplicate_object then null; end $$;

comment on column public.gallery.focus_x is
  '네모 썸네일을 자를 가로 자리(%, object-position). 50 = 가운데. null = 아직 얼굴을 안 본 사진';
comment on column public.gallery.focus_y is
  '네모 썸네일을 자를 세로 자리(%, object-position). 0 = 맨 위. 얼굴이 잘릴 때만 50 에서 옮긴다';

-- 돌려주는 칸이 늘어나므로 create or replace 로는 안 된다 — 먼저 지운다
drop function if exists public.gallery_public();
create or replace function public.gallery_public()
returns table(id uuid, image_url text, venue text, staff_name text, focus_x smallint, focus_y smallint)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select g.id, g.image_url, g.venue, s.name, g.focus_x, g.focus_y
  from public.gallery g
  left join public.staff s on s.id = g.staff_id
  order by g.sort asc, g.created_at desc
$$;
revoke all on function public.gallery_public() from public;
grant execute on function public.gallery_public() to anon, authenticated;
