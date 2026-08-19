-- 스토리지 목록 열람 차단.
--
-- 무엇이 문제였나. gallery 버킷에 손님이 올린 레퍼런스 사진이 refs/<예약ID>/ 로 들어간다.
-- 그런데 storage.objects 의 SELECT 정책이 anon 에게도 열려 있어서, 공개 키만 있으면
-- 목록을 통째로 받아올 수 있었다. 파일 경로에 예약ID가 들어 있으니 예약ID가 통째로 새고,
-- 예약ID는 손님 포털(portal_booking_info)·설문(survey_view)을 여는 열쇠다.
-- 즉 사진 유출이 아니라 고객 정보 전체가 열리는 경로였다. 실제로 재현 확인함.
--
-- 목록 열람은 관리자(authenticated)만 필요하다:
--   · 홈 갤러리는 gallery_list() 로 가져온다(security definer라 정책과 무관)
--   · 설문 화면은 업로드(INSERT)만 한다
--   · 관리자 화면만 .list() / .remove() 를 쓴다
-- 공개 버킷의 /object/public/... 직접 열람은 RLS를 타지 않으므로 그대로 동작한다.
-- (URL을 아는 사람은 여전히 볼 수 있다 — 그건 다음 단계에서 비공개 버킷으로 옮겨 막는다)

drop policy if exists "gallery_public_read" on storage.objects;

create policy "gallery_list_auth" on storage.objects
  for select to authenticated
  using (bucket_id = 'gallery');
