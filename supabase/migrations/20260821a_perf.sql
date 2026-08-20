-- 효율 점검 후속 ①⑤ — 실제로 재보고 고치는 두 가지.
--
-- ① 홈 갤러리 목록이 671장 통째로 178KB(841ms). 화면엔 16장만 나오는데도 매번 다 받는다.
--    관리자는 지우기 버튼에 image_path 가 필요하므로 gallery_list() 는 그대로 두고,
--    홈에는 꼭 필요한 것(사진 주소·예식장)만 주는 창구를 따로 낸다 → 178KB → 107KB (실측)
--
-- ⑤ cron.job_run_details 가 12MB. DB 전체 27MB 의 44% 를 크론 실행기록이 차지하고 있었다.
--    pg_cron 은 이걸 스스로 지우지 않는다. 하루 2,000줄씩 는다. 7일치만 남긴다.

-- ── ① 홈 갤러리 전용 (가벼운 판) ─────────────────────────────
create or replace function public.gallery_public()
returns table (id uuid, image_url text, venue text)
language sql stable security definer set search_path = public, pg_temp as $fn$
  select g.id, g.image_url, g.venue from public.gallery g
  order by g.sort asc, g.created_at desc
$fn$;
revoke all on function public.gallery_public() from public;
grant execute on function public.gallery_public() to anon, authenticated;

-- ── ⑤ 크론 실행기록 청소 ─────────────────────────────────────
create or replace function private.cron_log_prune()
returns int language plpgsql security definer set search_path = cron, private, pg_temp as $fn$
declare n int;
begin
  delete from cron.job_run_details where end_time < now() - interval '7 days';
  get diagnostics n = row_count;
  return n;
end$fn$;

select cron.schedule('otb-cron-log-prune', '40 18 * * *', $$select private.cron_log_prune()$$);
