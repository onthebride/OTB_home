-- 방문자 행동(클래리티)이 8/18 이후 한 줄도 안 쌓였다 (대표 2026-09-04
--   «우리 방문자 행동이 업데이트가 안되는거 같아»)
--
-- ═══ 무슨 일이 있었나 ═══
-- 하루 한 번 도는 `clarity_daily_job()` 이 이 차례로 일했다.
--   ① clarity_collect() — **어제** 보낸 요청의 답을 읽어 저장
--   ② clarity_fetch()   — **오늘** 요청을 새로 보내고 그 번호를 적어둠
-- 그런데 pg_net 은 받은 답을 `pg_net.ttl = 6시간` 만 두고 지운다.
-- ①이 읽으려는 답은 **24시간 전** 것이라 이미 지워지고 없다.
-- 없으면 `st is null` 로 「아직 안 왔다」 로 보고 조용히 물러났다 —
-- 오류도 안 남기고, 번호도 안 지우고. 그래서 **17일 동안 아무도 몰랐다.**
-- 8/18 한 줄은 만들던 날 손으로 돌려서 남은 것이다. 자동으로는 **한 번도 성공한 적이 없다.**
--
-- ⚠ 토큰은 멀쩡하다. 2026-09-04 에 실제로 불러봤고 200 이 왔다.
--
-- ═══ 어떻게 고치나 ═══
-- 보내는 일과 받는 일을 **크론 둘로 갈라** 10분 뒤에 읽는다. 6시간 안이라 답이 살아 있다.
-- 그리고 답이 없으면 **오류로 남긴다.** 조용히 물러나는 것이 이 사고의 진짜 원인이었다.

/* ── 받아서 저장하기 ──
   ⚠ 이제 이 함수는 보낸 지 10분 뒤에 돈다. 그러니 「없다」는 «아직»이 아니라 «못 받았다» 다.
     조용히 물러나지 말고 적어둔다 — 다음에 또 이러면 바로 보이게 */
create or replace function private.clarity_collect()
returns date language plpgsql security definer
set search_path to 'private', 'public', 'pg_temp' as $$
declare rid bigint; st int; body jsonb; d date;
begin
  select val::bigint into rid from private.clarity where key = 'last_req';
  if rid is null then
    insert into private.clarity (key, val) values ('last_error', '보낸 기록이 없다 @ ' || now())
      on conflict (key) do update set val = excluded.val;
    return null;
  end if;

  select status_code, content::jsonb into st, body from net._http_response where id = rid;

  if st is null then
    -- pg_net 이 6시간 뒤 지운다. 10분 뒤에 없으면 못 받은 것이다
    insert into private.clarity (key, val)
      values ('last_error', '답이 없다 (요청 ' || rid || ') @ ' || now())
      on conflict (key) do update set val = excluded.val;
    delete from private.clarity where key = 'last_req';   -- 붙들고 있어봐야 소용없다
    return null;
  end if;

  if st <> 200 then
    insert into private.clarity (key, val) values ('last_error', st || ' @ ' || now())
      on conflict (key) do update set val = excluded.val;
    delete from private.clarity where key = 'last_req';
    return null;
  end if;

  d := private.clarity_store(body);
  delete from private.clarity where key = 'last_req';
  delete from private.clarity where key = 'last_error';    -- 잘 됐으면 지운다
  return d;
exception when others then
  insert into private.clarity (key, val) values ('last_error', sqlerrm || ' @ ' || now())
    on conflict (key) do update set val = excluded.val;
  return null;
end$$;
revoke all on function private.clarity_collect() from public, anon, authenticated;

/* ── 화면이 「며칠째 안 들어왔는지」를 같이 받게 한다 ──
   대표가 8/18 이 떠 있는 것을 보고 알아채셨다. 다음엔 화면이 스스로 말하게 한다.
   ⚠ 있던 것을 갈아엎지 않는다. `latest`·`pages`·`days` 는 **그대로 두고** 두 칸만 더한다 —
     `days` 는 아래 꺾은선이 쓰고, `pages` 는 PopularPages 를 추려낸 것이다 */
create or replace function public.admin_clarity(p_days integer default 30)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'private', 'pg_temp' as $$
declare n int := least(greatest(coalesce(p_days, 30), 1), 365); res jsonb; last_d date; err text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select max(the_date) into last_d from public.clarity_daily;
  select val into err from private.clarity where key = 'last_error';
  select jsonb_build_object(
    'latest', (select to_jsonb(x) - 'raw' from public.clarity_daily x order by the_date desc limit 1),
    'pages',  (select coalesce(jsonb_agg(p), '[]'::jsonb) from (
                 select p->>'url' as url, (p->>'visitsCount')::numeric as visits
                 from public.clarity_daily c,
                      jsonb_array_elements(c.raw) m,
                      jsonb_array_elements(m->'information') p
                 where c.the_date = last_d
                   and m->>'metricName' = 'PopularPages'
                 order by (p->>'visitsCount')::numeric desc limit 8) p),
    'days',   (select coalesce(jsonb_agg(to_jsonb(y) - 'raw' order by y.the_date), '[]'::jsonb)
               from (select * from public.clarity_daily
                     where the_date >= (now() at time zone 'Asia/Seoul')::date - n) y),
    -- 며칠치가 비었나. 0 이면 어제 것까지 들어와 있다는 뜻
    'stale_days', case when last_d is null then null
                       else ((now() at time zone 'Asia/Seoul')::date - last_d - 1) end,
    'last_error', err
  ) into res;
  return res;
end$$;
revoke all on function public.admin_clarity(integer) from public, anon;
grant execute on function public.admin_clarity(integer) to authenticated;

/* ── 크론을 둘로 가른다 ──
   ⚠ 한 job 안에서 보내고 바로 읽을 수는 없다. pg_net 은 트랜잭션이 끝나야 실제로 보낸다.
     그래서 시각을 벌려 둘로 나눈다. 10분이면 넉넉하다 (실제로는 3초 안에 왔다) */
do $do$
declare jid bigint;
begin
  -- 예전 것: 하나로 붙어 있던 job. 이제 «보내기» 만 한다
  select jobid into jid from cron.job where jobname = 'otb-clarity-daily';
  if jid is null then
    perform cron.schedule('otb-clarity-daily', '30 0 * * *', 'select private.clarity_fetch();');
  else
    perform cron.alter_job(jid, schedule => '30 0 * * *', command => 'select private.clarity_fetch();');
  end if;

  -- 새 것: 10분 뒤에 «받아서 저장»
  select jobid into jid from cron.job where jobname = 'otb-clarity-store';
  if jid is null then
    perform cron.schedule('otb-clarity-store', '40 0 * * *', 'select private.clarity_collect();');
  else
    perform cron.alter_job(jid, schedule => '40 0 * * *', command => 'select private.clarity_collect();');
  end if;
  raise notice '클래리티 — 보내기 00:30(KST 09:30) · 받기 00:40(KST 09:40)';
end$do$;

-- 이제 안 쓴다. 한 job 안에서 보내고 받으려던 것이 이 사고의 원인이었다
drop function if exists private.clarity_daily_job();

/* ── 셋의 권한을 맞춘다 ──
   collect 는 닫혀 있는데 fetch·store 는 로그인한 사람에게 열려 있었다. 셋 다 크론만 쓴다.
   ⚠ private 스키마는 PostgREST 가 안 내보내므로 브라우저에서 닿지는 않았다.
     그래도 셋이 제각각인 것은 다음 사람을 헷갈리게 한다.
   ⚠ collect 가 이것들을 부르지만 collect 는 security definer 라 주인 권한으로 돈다 —
     여기서 회수해도 크론은 그대로 돈다 */
revoke all on function private.clarity_fetch() from public, anon, authenticated;
revoke all on function private.clarity_store(jsonb, date) from public, anon, authenticated;
