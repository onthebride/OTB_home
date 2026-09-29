/* 예식장 샘플보기 전체 공개 (대표 2026-09-29 «전체 공개 가자»)

   20260929a 에서 대표 캘린더에만 켜 두었다 (대표 «일단 내 캘린더에만 적용해서 보여주고 전체 공개»).
   대표가 써 보시고 단추 자리(포스팅 가능 아래·상품 줄 오른쪽 끝)와 글자(「예식장 샘플보기」)를
   정하신 뒤 전체 공개를 정하셨다.

   ⚠ 바뀌는 것은 「대표만」 한 줄뿐이다. 누구에게 보일지는 여전히 이 함수 한 곳에서 정한다 —
     장수 세기(staff_gal_counts)와 사진 목록(staff_gal_samples)이 둘 다 이것을 본다.
   ⚠ 쉬는 분(active = false)은 여전히 안 보인다.
   ⚠ 남의 예식·지난 예식·취소한 예식을 안 주는 것은 그대로다 (두 함수 안에서 따로 막는다) */

create or replace function private.gal_sample_on(p_staff_id uuid)
returns boolean language sql stable
set search_path to 'public', 'pg_temp' as $$
  select exists (select 1 from public.staff s
                 where s.id = p_staff_id and coalesce(s.active, false))
$$;
revoke all on function private.gal_sample_on(uuid) from public, anon, authenticated;
