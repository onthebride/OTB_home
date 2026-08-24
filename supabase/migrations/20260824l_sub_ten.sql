-- 서브 작가 별점을 10점 만점으로 (대표 요청 2026-08-24)
--   "ㅇㅋ 서브 항목도 10점만점으로 해줘"
--
-- 처음엔 5점으로 뒀다. 메인 문항(10점)과 섞이지 않게 하려던 것인데,
-- 대표가 같은 잣대로 보길 원한다. 잣대가 같아야 «누가 더 나은가» 를 바로 견준다.
-- 아직 들어온 서브 별점이 한 건도 없어서 지금 바꾸면 손볼 자료가 없다.
--
-- 그래도 메인 점수(100점 만점 가중)와는 여전히 따로 센다 — 물어본 것이 다르다.
-- 메인은 다섯 항목을 무게 지어 100점으로 낸 것이고, 서브는 한 항목 10점이다.

alter table public.feedback drop constraint if exists feedback_sub_stars_range;
alter table public.feedback add constraint feedback_sub_stars_range
  check (sub_stars is null or sub_stars between 1 and 10);
comment on column public.feedback.sub_stars is
  '서브 작가 별점 1~10. 메인의 100점 만점 가중 점수와는 따로 센다';

create or replace function public.feedback_submit(p_booking_id uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare b public.bookings; r int; sub int; subname text;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found then raise exception 'booking not found'; end if;
  if b.status = '취소' then raise exception 'cancelled booking'; end if;
  if exists(select 1 from public.feedback where booking_id = p_booking_id) then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  -- 서브가 배정된 예식일 때만 받는다. 배정이 없으면 별점이 와도 버린다
  sub := case when b.sub_assignee_id is null then null
              else nullif(payload->>'sub_stars', '')::int end;
  if sub is not null and (sub < 1 or sub > 10) then sub := null; end if;

  insert into public.feedback (booking_id, staff_id, overall, arrival, kindness, requests, flow,
                               family, next_req, issue, issue_text, message, scale,
                               sub_staff_id, sub_stars)
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
end$fn$;
revoke all on function public.feedback_submit(uuid, jsonb) from public;
grant execute on function public.feedback_submit(uuid, jsonb) to anon, authenticated;
