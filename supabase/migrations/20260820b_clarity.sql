-- 클래리티(Microsoft Clarity) 수치를 매일 받아 쌓는다.
--
-- 왜 쌓아두나. 클래리티 API 는 '최근 1~3일치' 만 내주고 하루 10번까지만 부를 수 있다.
-- 그냥 볼 때마다 부르면 3일보다 오래된 건 영영 못 본다. 매일 한 번 받아 우리 DB 에 남기면
-- 몇 달치 흐름을 볼 수 있다 — 클래리티 화면에서도 못 보는 것이다.
--
-- 가져오는 것: 세션·순방문자·평균 스크롤·머문 시간, 그리고 답답함의 흔적들
--   죽은 클릭(눌러도 아무 일 없는 곳을 누름) · 분노 클릭(같은 데를 연타) ·
--   빠른 이탈(들어왔다 바로 뒤로) · 스크립트 오류
-- 영상과 AI 요약은 API 로 나오지 않는다(클래리티 화면 전용).

create table if not exists public.clarity_daily (
  the_date    date primary key,           -- 이 수치가 대표하는 날(한국 기준, 받은 날의 전날)
  sessions    int,
  bots        int,
  users       int,
  pages_per   numeric(6,2),
  scroll_avg  numeric(5,2),
  total_time  int,                        -- 초
  active_time int,
  dead_pct    numeric(5,2), dead_cnt  int,
  rage_pct    numeric(5,2), rage_cnt  int,
  quick_pct   numeric(5,2), quick_cnt int,
  err_pct     numeric(5,2), err_cnt   int,
  raw         jsonb not null,             -- 원본 그대로. 나중에 다른 걸 보고 싶어질 때를 위해
  fetched_at  timestamptz not null default now()
);
alter table public.clarity_daily enable row level security;
revoke all on public.clarity_daily from anon, authenticated;

create table if not exists private.clarity (key text primary key, val text);

-- 응답에서 숫자 하나 꺼내기. 클래리티는 같은 값을 어떤 건 문자열로, 어떤 건 숫자로 준다.
create or replace function private.cl_num(p jsonb, p_metric text, p_field text)
returns numeric language sql immutable as $$
  select nullif((
    select x->'information'->0->>p_field
    from jsonb_array_elements(p) x
    where x->>'metricName' = p_metric
    limit 1), '')::numeric
$$;

-- 받아온 JSON 한 덩어리를 하루치 행으로 저장. 같은 날짜면 덮어쓴다.
create or replace function private.clarity_store(p_body jsonb, p_date date default null)
returns date language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare d date := coalesce(p_date, ((now() at time zone 'Asia/Seoul')::date - 1));
begin
  if p_body is null or jsonb_typeof(p_body) <> 'array' then raise exception 'bad body'; end if;
  insert into public.clarity_daily as t (the_date, sessions, bots, users, pages_per,
      scroll_avg, total_time, active_time,
      dead_pct, dead_cnt, rage_pct, rage_cnt, quick_pct, quick_cnt, err_pct, err_cnt, raw, fetched_at)
  values (d,
    private.cl_num(p_body, 'Traffic', 'totalSessionCount'),
    private.cl_num(p_body, 'Traffic', 'totalBotSessionCount'),
    private.cl_num(p_body, 'Traffic', 'distinctUserCount'),
    private.cl_num(p_body, 'Traffic', 'pagesPerSessionPercentage'),
    private.cl_num(p_body, 'ScrollDepth', 'averageScrollDepth'),
    private.cl_num(p_body, 'EngagementTime', 'totalTime'),
    private.cl_num(p_body, 'EngagementTime', 'activeTime'),
    private.cl_num(p_body, 'DeadClickCount', 'sessionsWithMetricPercentage'),
    private.cl_num(p_body, 'DeadClickCount', 'subTotal'),
    private.cl_num(p_body, 'RageClickCount', 'sessionsWithMetricPercentage'),
    private.cl_num(p_body, 'RageClickCount', 'subTotal'),
    private.cl_num(p_body, 'QuickbackClick', 'sessionsWithMetricPercentage'),
    private.cl_num(p_body, 'QuickbackClick', 'subTotal'),
    private.cl_num(p_body, 'ScriptErrorCount', 'sessionsWithMetricPercentage'),
    private.cl_num(p_body, 'ScriptErrorCount', 'subTotal'),
    p_body, now())
  on conflict (the_date) do update set
    sessions = excluded.sessions, bots = excluded.bots, users = excluded.users,
    pages_per = excluded.pages_per, scroll_avg = excluded.scroll_avg,
    total_time = excluded.total_time, active_time = excluded.active_time,
    dead_pct = excluded.dead_pct, dead_cnt = excluded.dead_cnt,
    rage_pct = excluded.rage_pct, rage_cnt = excluded.rage_cnt,
    quick_pct = excluded.quick_pct, quick_cnt = excluded.quick_cnt,
    err_pct = excluded.err_pct, err_cnt = excluded.err_cnt,
    raw = excluded.raw, fetched_at = now();
  return d;
end$fn$;

-- ① 요청 보내기 (pg_net 은 비동기라 여기서는 요청만 던진다)
create or replace function private.clarity_fetch()
returns bigint language plpgsql security definer set search_path = private, public, pg_temp as $fn$
declare tok text; req bigint;
begin
  select val into tok from private.clarity where key = 'token';
  if tok is null then return null; end if;
  select net.http_get(
    url := 'https://www.clarity.ms/export-data/api/v1/project-live-insights?numOfDays=1',
    headers := jsonb_build_object('Authorization', 'Bearer ' || tok)
  ) into req;
  insert into private.clarity (key, val) values ('last_req', req::text)
    on conflict (key) do update set val = excluded.val;
  return req;
end$fn$;

-- ② 응답 거두기 (다음 실행 때 지난 요청의 응답을 읽어 저장한다)
create or replace function private.clarity_collect()
returns date language plpgsql security definer set search_path = private, public, pg_temp as $fn$
declare rid bigint; st int; body jsonb; d date;
begin
  select val::bigint into rid from private.clarity where key = 'last_req';
  if rid is null then return null; end if;
  select status_code, content::jsonb into st, body from net._http_response where id = rid;
  if st is null then return null; end if;                      -- 아직 안 옴
  if st <> 200 then
    insert into private.clarity (key, val) values ('last_error', st || ' @ ' || now())
      on conflict (key) do update set val = excluded.val;
    return null;
  end if;
  d := private.clarity_store(body);
  delete from private.clarity where key = 'last_req';
  return d;
exception when others then
  insert into private.clarity (key, val) values ('last_error', sqlerrm || ' @ ' || now())
    on conflict (key) do update set val = excluded.val;
  return null;
end$fn$;

-- 하루 한 번: 먼저 지난 응답을 거두고, 새 요청을 던진다.
create or replace function private.clarity_daily_job()
returns text language plpgsql security definer set search_path = private, public, pg_temp as $fn$
declare got date; req bigint;
begin
  got := private.clarity_collect();
  req := private.clarity_fetch();
  return coalesce(got::text, '-') || ' / req ' || coalesce(req::text, '-');
end$fn$;

-- 관리자 화면용
create or replace function public.admin_clarity(p_days int default 30)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare n int := least(greatest(coalesce(p_days, 30), 1), 365); res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select jsonb_build_object(
    'latest', (select to_jsonb(x) - 'raw' from public.clarity_daily x order by the_date desc limit 1),
    'pages',  (select coalesce(jsonb_agg(p), '[]'::jsonb) from (
                 select p->>'url' as url, (p->>'visitsCount')::numeric as visits
                 from public.clarity_daily c,
                      jsonb_array_elements(c.raw) m,
                      jsonb_array_elements(m->'information') p
                 where c.the_date = (select max(the_date) from public.clarity_daily)
                   and m->>'metricName' = 'PopularPages'
                 order by (p->>'visitsCount')::numeric desc limit 8) p),
    'days',   (select coalesce(jsonb_agg(to_jsonb(y) - 'raw' order by y.the_date), '[]'::jsonb)
               from (select * from public.clarity_daily
                     where the_date >= (now() at time zone 'Asia/Seoul')::date - n) y)
  ) into res;
  return res;
end$fn$;
revoke all on function public.admin_clarity(int) from public, anon;
grant execute on function public.admin_clarity(int) to authenticated;
