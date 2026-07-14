-- 20260714_storage_policies.sql
-- gallery 버킷의 storage.objects RLS 정책. (storage 스키마라 schema.sql에 없어 리전 이전 시 누락됐던 것 복원)
-- 관리자(authenticated) 업로드/삭제, 공개 읽기, 설문 참고이미지(anon, refs/ 경로) 업로드 허용.

drop policy if exists gallery_public_read on storage.objects;
create policy gallery_public_read on storage.objects
  for select to public using (bucket_id = 'gallery');

drop policy if exists gallery_auth_insert on storage.objects;
create policy gallery_auth_insert on storage.objects
  for insert to authenticated with check (bucket_id = 'gallery');

drop policy if exists gallery_auth_delete on storage.objects;
create policy gallery_auth_delete on storage.objects
  for delete to authenticated using (bucket_id = 'gallery');

drop policy if exists refs_anon_insert on storage.objects;
create policy refs_anon_insert on storage.objects
  for insert to anon with check (bucket_id = 'gallery' and name like 'refs/%');
