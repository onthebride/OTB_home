-- 촬영 후 설문에 «추천 의향» 문항을 넣는다 (0~10). 대표 요청 2026-08-25.
--
-- 왜 넣나 — 지금 별점으로는 작가 순위를 못 매긴다. 응답 13건을 문항별로 보면:
--   도착   13/13 전부 「제시간」   ← 갈린 게 하나도 없다
--   친절   13/13 전부 10점        ← 역시 하나도 없다
--   전체·요청·진행  12건 10점 + 1건 9점
-- 지금 문항들이 「문제가 없었나」를 묻기 때문이다. 문제가 없으면 전부 만점이 된다.
-- 사고(지각·불친절)를 잡는 데는 좋지만, 잘하는 작가끼리 줄을 세우는 데는 못 쓴다.
-- 추천 의향은 만족한 분들 안에서도 8·9·10으로 갈린다. 그래서 지정 근거가 된다.
--
-- 100점 가중점수(private.fb_score)에는 **넣지 않는다.**
-- 옛 응답 13건에는 이 칸이 없어서, 넣으면 새 응답만 점수가 내려간다.
-- 같은 잣대로 못 견주게 되므로 따로 보여준다.

alter table public.feedback add column if not exists recommend smallint;
alter table public.feedback drop constraint if exists feedback_recommend_ck;
alter table public.feedback add constraint feedback_recommend_ck
  check (recommend is null or recommend between 0 and 10);

comment on column public.feedback.recommend is
  '다른 신부에게 이 작가를 추천하겠는가 (0~10). 지정 근거. fb_score 에는 안 들어간다';


-- ===== 저장 =====
create or replace function public.feedback_submit(p_booking_id uuid, payload jsonb)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare b public.bookings; r int; rec int; sub int; subname text;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found then raise exception 'booking not found'; end if;
  if b.status = '취소' then raise exception 'cancelled booking'; end if;
  if exists(select 1 from public.feedback where booking_id = p_booking_id) then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  -- 0 도 뜻이 있는 답이라 nullif 로 «빈 문자열» 만 걸러야 한다.
  -- 범위를 벗어나면 버린다 (안 받은 것으로 본다)
  rec := nullif(payload->>'recommend', '')::int;
  if rec is not null and (rec < 0 or rec > 10) then rec := null; end if;

  -- 서브가 배정된 예식일 때만 받는다. 배정이 없으면 별점이 와도 버린다
  sub := case when b.sub_assignee_id is null then null
              else nullif(payload->>'sub_stars', '')::int end;
  if sub is not null and (sub < 1 or sub > 10) then sub := null; end if;

  insert into public.feedback (booking_id, staff_id, overall, arrival, kindness, requests, flow,
                               family, recommend, next_req, issue, issue_text, message, scale,
                               sub_staff_id, sub_stars)
  values (
    p_booking_id, b.assignee_id,
    (payload->>'overall')::smallint,
    coalesce(nullif(payload->>'arrival', ''), 'ontime'),
    (payload->>'kindness')::smallint,
    (payload->>'requests')::smallint,
    (payload->>'flow')::smallint,
    nullif(payload->>'family', '')::smallint,
    rec,
    -- 화면에서도 다듬지만 서버에서도 다듬는다. 빈칸만 적어 보내면 «없음» 으로 봐야 한다
    nullif(left(trim(coalesce(payload->>'next_req', '')), 1000), ''),
    coalesce((payload->>'issue')::boolean, false),
    nullif(left(trim(coalesce(payload->>'issue_text', '')), 1000), ''),
    nullif(left(trim(coalesce(payload->>'message', '')), 1000), ''),
    10,
    case when sub is null then null else b.sub_assignee_id end,
    sub
  );

  -- 낮은 점수는 대표에게 바로 알림(놓치지 않게) — 10점 만점에서 6점 이하
  r := (payload->>'overall')::int;
  if r <= 6 then
    perform private.otb_push('⚠️ 촬영 설문 낮은 평가',
      coalesce(b.contractor_name, '') || ' · 전체 ' || r || '점 (10점 만점)', '/admin');
  end if;
  -- 별점은 높은데 추천은 안 하겠다는 경우 — 지금 문항들이 못 잡는 자리가 여기다.
  -- 「불만은 없지만 다시 부르진 않겠다」 가 지정 근거에서 제일 중요한 신호다.
  -- 전체 점수가 이미 낮으면 위에서 알렸으니 두 번 울리지 않는다
  if rec is not null and rec <= 6 and r > 6 then
    perform private.otb_push('⚠️ 추천 의향 낮음',
      coalesce(b.contractor_name, '') || ' · 전체는 ' || r || '점인데 추천은 ' || rec || '점', '/admin');
  end if;
  -- 「다음에 부탁드리고 싶은 것」 이 적혀 오면 대표가 바로 보게 한다.
  -- 점수는 만점인데 여기에만 적히는 경우가 있을 것이다 — 그게 이 항목을 넣은 이유다
  if nullif(trim(coalesce(payload->>'next_req', '')), '') is not null then
    perform private.otb_push('📝 촬영 설문 — 다음 촬영 요청',
      coalesce(b.contractor_name, '') || ' · ' || left(trim(payload->>'next_req'), 60), '/admin');
  end if;
  -- 서브 별점이 낮으면 그것도 알린다. 메인 점수만 보면 안 보이는 것이다.
  -- 10점 만점이 됐으니 메인과 같은 기준(6점 이하)으로 본다
  if sub is not null and sub <= 6 then
    select name into subname from public.staff where id = b.sub_assignee_id;
    perform private.otb_push('⚠️ 서브 작가 낮은 평가',
      coalesce(b.contractor_name, '') || ' · ' || coalesce(subname, '서브') || ' ' || sub || '점 (10점 만점)', '/admin');
  end if;

  return jsonb_build_object('ok', true);
end$$;


-- ===== 관리자 목록 =====
create or replace function public.admin_feedback(p_days integer default 365)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare n_days int := least(greatest(coalesce(p_days, 365), 1), 3650); res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  with f as (
    select fb.*, private.fb_score(fb.*) as score,
           s.name as staff_name, s2.name as sub_staff_name,
           b.contractor_name, b.bride_name, b.wedding_date, b.wedding_venue
    from public.feedback fb
    join public.bookings b on b.id = fb.booking_id
    left join public.staff s on s.id = fb.staff_id
    left join public.staff s2 on s2.id = fb.sub_staff_id
    where fb.created_at >= now() - (n_days || ' days')::interval
  ),
  -- 서브로 참여해 받은 별점. 메인 점수와 따로 센다 (1~10)
  subq as (
    select coalesce(sub_staff_name, '(이름 없음)') as staff_name,
           count(*) as n, round(avg(sub_stars)::numeric, 1) as avg
    from f where sub_stars is not null group by 1
  ),
  -- 설문을 받을 수 있었던 예식 (분모)
  tgt as (
    select coalesce(s.name, '(배정 없음)') as staff_name, count(*) as n
    from public.bookings b
    left join public.staff s on s.id = b.assignee_id
    where b.status <> '취소' and b.wedding_date is not null
      and b.wedding_date < (now() at time zone 'Asia/Seoul')::date
      and b.wedding_date >= (now() at time zone 'Asia/Seoul')::date - n_days
    group by 1
  )
  select jsonb_build_object(
    'count', (select count(*) from f),
    'avg_overall', (select round(avg(overall)::numeric, 2) from f),
    'avg_family', (select round(avg(family)::numeric, 2) from f),
    'avg_score', (select round(avg(score)::numeric, 1) from f),
    -- 추천 의향 — 지정 근거. 점수와 달리 갈리는 값이라 따로 낸다
    'avg_rec', (select round(avg(recommend)::numeric, 1) from f),
    'rec_n', (select count(*) from f where recommend is not null),
    -- 전체 응답률
    'target', (select coalesce(sum(n), 0) from tgt),
    'rate', (select case when coalesce(sum(t.n), 0) = 0 then null
                    else least(100, round(100.0 * (select count(*) from f) / sum(t.n))) end from tgt t),
    -- 묶어서 센 뒤에 분모를 붙인다. 묶는 자리에서 바로 붙이면
    -- count(*) 와 g.n 을 한 줄에 못 써서 «group by 에 있어야 한다» 로 막힌다
    'staff', coalesce((select jsonb_agg(t order by t.avg_score desc nulls last) from (
        select a.*, g.n as target,
               case when coalesce(g.n, 0) = 0 then null
                    else least(100, round(100.0 * a.n / g.n)) end as rate,
               q.n as sub_n, q.avg as sub_avg
        from (
          select coalesce(staff_name, '(배정 없음)') as staff_name,
                 count(*) as n,
                 round(avg(score)::numeric, 1)    as avg_score,
                 round(avg(overall)::numeric, 2)  as avg_overall,
                 round(avg(kindness)::numeric, 2) as avg_kindness,
                 round(avg(requests)::numeric, 2) as avg_requests,
                 round(avg(flow)::numeric, 2)     as avg_flow,
                 round(avg(family)::numeric, 2)   as avg_family,
                 round(avg(recommend)::numeric, 1) as avg_rec,
                 count(*) filter (where recommend is not null) as rec_n,
                 count(*) filter (where arrival <> 'ontime') as late_n,
                 count(*) filter (where issue)               as issue_n,
                 count(*) filter (where next_req is not null) as req_n
          from f group by 1) a
        left join tgt g on g.staff_name = a.staff_name
        left join subq q on q.staff_name = a.staff_name) t), '[]'::jsonb),
    -- 서브로만 참여한 작가는 위 목록에 아예 안 뜬다 (메인 응답이 없어서). 따로 준다
    'subs', coalesce((select jsonb_agg(t order by t.avg desc nulls last) from (
        select q.staff_name, q.n, q.avg from subq q) t), '[]'::jsonb),
    -- 설문이 한 번도 안 온 작가도 보여준다. 만점으로 채우지 않고 «평가 없음» 으로 남긴다 —
    -- 무응답은 «만족» 이 아니라 «모른다» 이고, 안 찍힌 작가가 100점이 되면 그건 거짓 숫자다
    'silent', coalesce((select jsonb_agg(t order by t.n desc) from (
        select g.staff_name, g.n from tgt g
        where not exists (select 1 from f where coalesce(f.staff_name, '(배정 없음)') = g.staff_name)
          and g.staff_name <> '(배정 없음)') t), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(t order by t.created_at desc) from (
        select booking_id, created_at, coalesce(staff_name, '(배정 없음)') as staff_name,
               contractor_name, bride_name, wedding_date, wedding_venue,
               overall, arrival, kindness, requests, flow,
               family, recommend, next_req, score,
               sub_staff_name, sub_stars,
               issue, issue_text, message
        from f) t), '[]'::jsonb)
  ) into res;
  return res;
end$$;
