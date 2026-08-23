-- 작가 평가 설문에 두 항목 추가. (대표 요청 2026-08-23)
--
-- 지금까지 9건이 들어왔는데 전 항목이 10점이다(진행 9점 하나 빼고).
-- 만족도를 물으면 웬만하면 만점을 주신다. 항목을 더 늘려도 10점이 하나 더 생길 뿐이라,
-- «갈리는 것» 과 «사실» 을 묻는 쪽으로 골랐다.
--
--   family    가족·하객분들을 편하게 이끌어 주셨나요 (1~10)
--             원판·단체사진에서 실제로 갈리고, 신부님이 제일 잘 보는 자리다
--   next_req  다음에 또 촬영하신다면 미리 부탁드리고 싶은 것 (자유, 선택)
--             불만이 아니라 «부탁» 을 묻는다. 같은 정보가 나오는데
--             신부님도 편히 쓰시고, 작가에게 전할 때도 지적이 아니라 부탁이 된다
--
-- ── 없앤 것 ────────────────────────────────────────────────
-- 「불편하거나 부담스러운 점이 있었나요」(issue) 를 설문에서 뺀다.
-- 9건 중 0건. 문턱이 너무 높아 아무도 안 누른다.
-- 칸은 지우지 않는다 — 지난 답이 들어 있고, 되살릴 수도 있다.

alter table public.feedback
  add column if not exists family smallint,
  add column if not exists next_req text;

create or replace function public.feedback_submit(p_booking_id uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare b public.bookings; r int;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found then raise exception 'booking not found'; end if;
  if b.status = '취소' then raise exception 'cancelled booking'; end if;
  if exists(select 1 from public.feedback where booking_id = p_booking_id) then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  insert into public.feedback (booking_id, staff_id, overall, arrival, kindness, requests, flow,
                               family, next_req, issue, issue_text, message, scale)
  values (
    p_booking_id, b.assignee_id,
    (payload->>'overall')::smallint,
    coalesce(nullif(payload->>'arrival', ''), 'ontime'),
    (payload->>'kindness')::smallint,
    (payload->>'requests')::smallint,
    (payload->>'flow')::smallint,
    nullif(payload->>'family', '')::smallint,
    -- 화면에서도 다듬지만 서버에서도 다듬는다. 빈칸만 적어 보내면 «없음» 으로 봐야 한다
    nullif(left(trim(coalesce(payload->>'next_req', '')), 1000), ''),
    coalesce((payload->>'issue')::boolean, false),
    nullif(left(trim(coalesce(payload->>'issue_text', '')), 1000), ''),
    nullif(left(trim(coalesce(payload->>'message', '')), 1000), ''),
    10
  );

  -- 낮은 점수는 대표에게 바로 알림(놓치지 않게) — 10점 만점에서 6점 이하
  r := (payload->>'overall')::int;
  if r <= 6 then
    perform private.otb_push('⚠️ 촬영 설문 낮은 평가',
      coalesce(b.contractor_name, '') || ' · 전체 ' || r || '점 (10점 만점)', '/admin');
  end if;
  -- 「다음에 부탁드리고 싶은 것」 이 적혀 오면 대표가 바로 보게 한다.
  -- 점수는 만점인데 여기에만 적히는 경우가 있을 것이다 — 그게 이 항목을 넣은 이유다
  if nullif(trim(coalesce(payload->>'next_req', '')), '') is not null then
    perform private.otb_push('📝 촬영 설문 — 다음 촬영 요청',
      coalesce(b.contractor_name, '') || ' · ' || left(trim(payload->>'next_req'), 60), '/admin');
  end if;
  return jsonb_build_object('ok', true);
end$fn$;
revoke all on function public.feedback_submit(uuid, jsonb) from public;
grant execute on function public.feedback_submit(uuid, jsonb) to anon, authenticated;

-- ── 관리자 화면이 새 항목도 보게 ───────────────────────────
-- 원래 것(20260817_feedback.sql)을 그대로 두고 새 칸만 얹는다.
-- 돌려주는 이름(count·items·issue_n·booking_id …)은 화면이 그대로 쓰고 있으므로 손대지 않는다.
create or replace function public.admin_feedback(p_days int default 365)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare n_days int := least(greatest(coalesce(p_days, 365), 1), 3650); res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  with f as (
    select fb.*, s.name as staff_name, b.contractor_name, b.bride_name, b.wedding_date, b.wedding_venue
    from public.feedback fb
    join public.bookings b on b.id = fb.booking_id
    left join public.staff s on s.id = fb.staff_id
    where fb.created_at >= now() - (n_days || ' days')::interval
  )
  select jsonb_build_object(
    'count', (select count(*) from f),
    'avg_overall', (select round(avg(overall)::numeric, 2) from f),
    'avg_family', (select round(avg(family)::numeric, 2) from f),
    'staff', coalesce((select jsonb_agg(t order by t.avg_overall desc nulls last) from (
        select coalesce(staff_name, '(배정 없음)') as staff_name,
               count(*) as n,
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
               family, next_req,
               issue, issue_text, message
        from f) t), '[]'::jsonb)
  ) into res;
  return res;
end$fn$;
revoke all on function public.admin_feedback(int) from public, anon;
grant execute on function public.admin_feedback(int) to authenticated;
