-- 20260817_pageviews.sql
-- 자체 방문 집계 — 관리자 '통계' 탭에서 바로 보기 위한 최소 기록.
-- 개인 식별 정보를 저장하지 않는다: IP·UserAgent 원문·쿠키 없음.
--   path   : 방문한 경로(쿼리스트링 제거, 200자 제한)
--   ref    : 유입 도메인만 (예: 'search.naver.com'). 전체 URL 아님. 내부 이동은 null
--   mobile : 화면 폭 기준 모바일 여부
--   sid    : 브라우저 세션 동안만 유지되는 난수(sessionStorage). 사람을 식별하지 못하며
--            "방문 수(세션)"와 "페이지뷰"를 구분하기 위해서만 쓴다.

create table if not exists public.pageviews (
  id      bigserial primary key,
  ts      timestamptz not null default now(),
  path    text        not null,
  ref     text,
  mobile  boolean     not null default false,
  sid     text
);

create index if not exists pageviews_ts_idx on public.pageviews (ts);

-- 직접 접근 전면 차단(읽기·쓰기 모두). 기록은 아래 SECURITY DEFINER 함수로만.
alter table public.pageviews enable row level security;
revoke all on public.pageviews from anon, authenticated;
revoke all on sequence public.pageviews_id_seq from anon, authenticated;

-- 손님 브라우저가 호출하는 기록 함수. 값이 없거나 이상하면 조용히 무시(에러로 화면 깨지지 않게).
create or replace function public.log_pageview(p_path text, p_ref text, p_mobile boolean, p_sid text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_path is null or length(p_path) = 0 or length(p_path) > 200 then return; end if;
  insert into public.pageviews (path, ref, mobile, sid)
  values (
    left(split_part(p_path, '?', 1), 200),
    nullif(left(coalesce(p_ref, ''), 100), ''),
    coalesce(p_mobile, false),
    nullif(left(coalesce(p_sid, ''), 40), '')
  );
end; $$;
revoke all on function public.log_pageview(text, text, boolean, text) from public;
grant execute on function public.log_pageview(text, text, boolean, text) to anon, authenticated;

-- 관리자 통계 조회. 방문 수는 세션(sid) 기준, sid 가 없으면 행 1건을 1방문으로 센다.
create or replace function public.admin_analytics(p_days int default 30)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  n_days int := least(greatest(coalesce(p_days, 30), 1), 365);
  kst_today date := (now() at time zone 'Asia/Seoul')::date;
  res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;

  with v as (
    select (ts at time zone 'Asia/Seoul')::date as vday, path, ref, mobile,
           coalesce(sid, 'row-' || id::text) as s
    from public.pageviews
    where ts >= (kst_today - (n_days - 1))::timestamp at time zone 'Asia/Seoul'
  )
  select jsonb_build_object(
    'days', n_days,
    'today',  jsonb_build_object('visits', (select count(distinct s) from v where vday = kst_today),
                                 'views',  (select count(*) from v where vday = kst_today)),
    'week',   jsonb_build_object('visits', (select count(distinct s) from v where vday > kst_today - 7),
                                 'views',  (select count(*) from v where vday > kst_today - 7)),
    'range',  jsonb_build_object('visits', (select count(distinct s) from v),
                                 'views',  (select count(*) from v)),
    'mobile_pct', coalesce((select round(100.0 * count(*) filter (where mobile) / nullif(count(*), 0)) from v), 0),
    -- 일자별 (기록 없는 날도 0으로 채워 그래프가 끊기지 않게)
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object('d', g.day, 'visits', x.visits, 'views', x.views) order by g.day)
      from generate_series(kst_today - (n_days - 1), kst_today, '1 day') as g(day)
      left join lateral (
        select count(distinct s) as visits, count(*) as views from v where v.vday = g.day
      ) x on true), '[]'::jsonb),
    'pages', coalesce((
      select jsonb_agg(t) from (
        select path, count(*) as views, count(distinct s) as visits
        from v group by path order by count(*) desc limit 10) t), '[]'::jsonb),
    'refs', coalesce((
      select jsonb_agg(t) from (
        select coalesce(ref, '(직접 · 즐겨찾기)') as ref, count(distinct s) as visits
        from v group by 1 order by count(distinct s) desc limit 10) t), '[]'::jsonb)
  ) into res;
  return res;
end; $$;
revoke all on function public.admin_analytics(int) from public, anon;
grant execute on function public.admin_analytics(int) to authenticated;

-- 오래된 기록 정리: 180일 초과분 매일 삭제 (pg_cron 있을 때만)
create or replace function private.pageviews_prune()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  delete from public.pageviews where ts < now() - interval '180 days';
  get diagnostics n = row_count;
  return n;
end; $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'otb-pageviews-prune') then
      perform cron.unschedule('otb-pageviews-prune');
    end if;
    perform cron.schedule('otb-pageviews-prune', '20 18 * * *', 'select private.pageviews_prune();');  -- 매일 03:20 KST
  else
    raise notice 'pg_cron 미설치 — 오래된 방문기록 자동정리는 등록되지 않음';
  end if;
end $$;
