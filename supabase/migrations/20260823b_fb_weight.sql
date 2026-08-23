-- 작가 평가 점수에 항목별 가중치. (대표가 정함 2026-08-23)
--
-- 지금까지는 「1번 전체 만족도」 하나만 봤다. 나머지는 받아만 두고 순위에 안 썼다.
-- 대표 뜻: 기본을 지키는 것에 점수를 많이, 주관적인 것은 소극적으로.
--
--   1번 전체 만족도   제외   ← 제일 주관적이고 나머지와 겹친다
--   2번 도착시간      25점
--   3번 친절          25점
--   4번 요청 반영     15점
--   5번 진행          15점
--   6번 가족·하객     20점
--                    ─────
--                     100점
--
-- 도착은 별점이 아니라 셋 중 하나라 따로 환산한다.
--   제시간   25점
--   조금 늦음 20점 (-5)
--   많이 늦음 15점 (-10)
--
-- 처음엔 12.5 / 0 으로 뒀는데 너무 셌다. 신부님들이 별점은 웬만하면 8~10점을 주셔서
-- 별점 항목은 실제로 2~5점밖에 안 움직이는데, 「조금 늦음」 체크 하나가 12.5점을 가져갔다.
-- 지각을 무겁게 보되 한 번으로 바닥까지 가지는 않게 대표가 다시 정했다.
--
-- ── 답이 없는 항목은? ──────────────────────────────────────
-- 6번은 2026-08-23 에 생겼다. 그 전 응답에는 없다.
-- 없는 항목은 «만점» 으로 치지 않고 분모에서 뺀다 — 만점으로 치면 옛 응답이 유리해진다.
-- 그래서 옛 응답은 80점 만점을 100점으로 환산한 값이 된다.
--
-- 1번은 점수에서 빠지지만 「6점 이하면 대표에게 알림」 에는 계속 쓴다.

create or replace function private.fb_score(f public.feedback)
returns numeric language sql immutable as $fn$
  select case when tot = 0 then null else round(got / tot * 100, 1) end
  from (
    select
      (case f.arrival when 'ontime' then 25 when 'late_small' then 20 else 15 end)
        + coalesce(f.kindness, 0) / 10.0 * 25
        + coalesce(f.requests, 0) / 10.0 * 15
        + coalesce(f.flow,     0) / 10.0 * 15
        + coalesce(f.family,   0) / 10.0 * 20                       as got,
      25                                                            -- 도착은 늘 값이 있다
        + (case when f.kindness is null then 0 else 25 end)
        + (case when f.requests is null then 0 else 15 end)
        + (case when f.flow     is null then 0 else 15 end)
        + (case when f.family   is null then 0 else 20 end)::numeric as tot
  ) w;
$fn$;
create or replace function public.admin_day_check(p_date date, p_time text DEFAULT NULL::text)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$

declare av jsonb; res jsonb; t text := nullif(btrim(coalesce(p_time, '')), '');
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_date is null then raise exception '날짜를 선택해 주세요'; end if;
  if t is not null and t !~ '^[0-2][0-9]:[0-5][0-9]$' then
    raise exception '시간을 HH:MM 형식으로 입력해 주세요';
  end if;

  av := public.admin_staff_availability(p_date, t);

  with a as (
    select * from jsonb_to_recordset(av) as x(id uuid, name text, status text, detail text)
  ), fb as (
    select staff_id, count(*)::int as n,
           round(avg(private.fb_score(f.*))::numeric, 1) as avg
    from public.feedback f group by staff_id
  ), ld as (      -- 앞뒤 90일 배정 건수 — 평점이 같거나 없을 때 고르게 나누기 위한 참고
    select s.id, count(b.*)::int as n
    from public.staff s
    left join public.bookings b
      on (b.assignee_id = s.id or b.sub_assignee_id = s.id)
     and b.status <> '취소'
     and b.wedding_date between p_date - 90 and p_date + 90
    group by s.id
  ), t2 as (
    select a.id, a.name, a.status, a.detail, st.can_main, st.can_sub,
           fb.avg as fb_avg, coalesce(fb.n, 0) as fb_n, coalesce(ld.n, 0) as load_n
    from a
    join public.staff st on st.id = a.id
    left join fb on fb.staff_id = a.id
    left join ld on ld.id = a.id
  )
  select jsonb_build_object(
    'the_date', p_date,
    'at_time', t,
    'ok_n',     (select count(*) from t2 where status = 'ok' and can_main),
    'ok_sub_n', (select count(*) from t2 where status = 'ok' and can_sub),
    'total_n',  (select count(*) from t2 where can_main),
    'fb_total', (select count(*) from public.feedback),
    'weddings', coalesce((select jsonb_agg(w order by w.wedding_time nulls last) from (
        select b.id, b.contractor_name, b.wedding_time, b.wedding_venue,
               ms.name as main_name, ss.name as sub_name
        from public.bookings b
        left join public.staff ms on ms.id = b.assignee_id
        left join public.staff ss on ss.id = b.sub_assignee_id
        where b.wedding_date = p_date and b.status <> '취소'
      ) w), '[]'::jsonb),
    -- 메인 가능한 작가가 먼저, 그 안에서 가능 → 평점 → 최근 배정 적은 순
    'staff', coalesce((select jsonb_agg(to_jsonb(x) order by
        (not x.can_main), (x.status <> 'ok'), x.fb_avg desc nulls last, x.load_n, x.name) from t2 x), '[]'::jsonb)
  ) into res;
  return res;
end$fn$;
revoke all on function public.admin_day_check(date, text) from public, anon;
grant execute on function public.admin_day_check(date, text) to authenticated;

-- 통계 화면에도 가중 점수를 함께 낸다 (기존 항목별 평균은 그대로 둔다)
create or replace function public.admin_feedback(p_days int default 365)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare n_days int := least(greatest(coalesce(p_days, 365), 1), 3650); res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  with f as (
    select fb.*, private.fb_score(fb.*) as score,
           s.name as staff_name, b.contractor_name, b.bride_name, b.wedding_date, b.wedding_venue
    from public.feedback fb
    join public.bookings b on b.id = fb.booking_id
    left join public.staff s on s.id = fb.staff_id
    where fb.created_at >= now() - (n_days || ' days')::interval
  )
  select jsonb_build_object(
    'count', (select count(*) from f),
    'avg_overall', (select round(avg(overall)::numeric, 2) from f),
    'avg_family', (select round(avg(family)::numeric, 2) from f),
    'avg_score', (select round(avg(score)::numeric, 1) from f),
    'staff', coalesce((select jsonb_agg(t order by t.avg_score desc nulls last) from (
        select coalesce(staff_name, '(배정 없음)') as staff_name,
               count(*) as n,
               round(avg(score)::numeric, 1)    as avg_score,
               round(avg(overall)::numeric, 2)  as avg_overall,
               round(avg(kindness)::numeric, 2) as avg_kindness,
               round(avg(requests)::numeric, 2) as avg_requests,
               round(avg(flow)::numeric, 2)     as avg_flow,
               round(avg(family)::numeric, 2)   as avg_family,
               count(*) filter (where arrival <> 'ontime') as late_n,
               count(*) filter (where issue)               as issue_n,
               count(*) filter (where next_req is not null) as req_n
        from f group by 1) t), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(t order by t.created_at desc) from (
        select booking_id, created_at, coalesce(staff_name, '(배정 없음)') as staff_name,
               contractor_name, bride_name, wedding_date, wedding_venue,
               overall, arrival, kindness, requests, flow,
               family, next_req, score,
               issue, issue_text, message
        from f) t), '[]'::jsonb)
  ) into res;
  return res;
end$fn$;
revoke all on function public.admin_feedback(int) from public, anon;
grant execute on function public.admin_feedback(int) to authenticated;
