-- 30일·90일에서는 오늘을 빼고 센다 (대표 2026-09-05
--   «30일 90일은 오늘 수치 빼도 될꺼같은데»)
--
-- 왜 — 오늘은 아직 안 끝난 날이다. 아침에 보면 막대 하나가 늘 짧게 서 있고,
--   그 반쪽짜리 하루가 합계에도 섞인다. 30일·90일은 «흐름»을 보는 자리라
--   끝난 날들만 세는 게 맞다.
-- 7일은 그대로 둔다. 짧게 보는 자리는 오늘이 어떤지가 궁금한 자리다.
--
-- ⚠ 막대만 지우면 안 된다. 합계(range)·평균이 오늘을 품은 채 남으면
--   그림과 숫자가 어긋난다. 창을 통째로 하루 당긴다.
-- ⚠ 칸을 더하므로 옛 서식을 먼저 지운다.

drop function if exists public.admin_analytics(integer);
drop function if exists public.admin_analytics(integer, boolean);

create or replace function public.admin_analytics(p_days integer default 30,
                                                  p_skip_today boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  n_days int := least(greatest(coalesce(p_days, 30), 1), 365);
  kst_today date := (now() at time zone 'Asia/Seoul')::date;
  -- 세는 마지막 날. 오늘을 빼면 어제까지다
  last_day date := case when coalesce(p_skip_today, false) then kst_today - 1 else kst_today end;
  first_day date := last_day - (n_days - 1);
  res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;

  with v as (
    select (ts at time zone 'Asia/Seoul')::date as vday, path, ref, mobile,
           coalesce(sid, 'row-' || id::text) as s
    from public.pageviews
    where ts >= first_day::timestamp at time zone 'Asia/Seoul'
      and ts <  (last_day + 1)::timestamp at time zone 'Asia/Seoul'
  )
  select jsonb_build_object(
    'days', n_days,
    'skip_today', coalesce(p_skip_today, false),
    -- 마지막으로 센 날. 화면이 「9/4까지」 라고 적을 수 있게
    'last_day', last_day,
    /* ⚠ 오늘·이번 주는 창과 상관없이 «지금» 을 보여주는 자리다.
         오늘을 빼고 세더라도 이 둘은 진짜 오늘을 봐야 한다 — 따로 센다 */
    'today',  (select jsonb_build_object('visits', count(distinct coalesce(sid, 'row-' || id::text)),
                                         'views', count(*))
                 from public.pageviews
                where (ts at time zone 'Asia/Seoul')::date = kst_today),
    'week',   (select jsonb_build_object('visits', count(distinct coalesce(sid, 'row-' || id::text)),
                                         'views', count(*))
                 from public.pageviews
                where (ts at time zone 'Asia/Seoul')::date > kst_today - 7),
    'range',  jsonb_build_object('visits', (select count(distinct s) from v),
                                 'views',  (select count(*) from v)),
    'mobile_pct', coalesce((select round(100.0 * count(*) filter (where mobile) / nullif(count(*), 0)) from v), 0),
    -- 일자별 (기록 없는 날도 0으로 채워 그래프가 끊기지 않게)
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object('d', g.day::date, 'visits', x.visits, 'views', x.views) order by g.day)
      from generate_series(first_day, last_day, '1 day') as g(day)
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
end$$;
revoke all on function public.admin_analytics(integer, boolean) from public, anon;
grant execute on function public.admin_analytics(integer, boolean) to authenticated;
