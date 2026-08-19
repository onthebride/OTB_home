-- 촬영 후 설문 별점 5점 → 10점.
-- 대표: "별점이 5개밖에 없으니까 변별력이 좀 떨어지는 거 같은데 10개 어때?"
--
-- 기존 응답 4건은 ×2 로 옮긴다(5점 만점 5점 → 10점 만점 10점). 그래야 예전 응답과
-- 새 응답의 평균을 한 줄에 놓고 볼 수 있다. scale 칸에 그 응답이 몇 점 만점이었는지
-- 남겨서, 나중에 "이건 옛날 5점짜리를 환산한 것"임을 알 수 있게 한다.
-- 이미 이관했으면 아무것도 하지 않는다.
do $mig$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'feedback' and column_name = 'scale') then
    return;
  end if;

  alter table public.feedback
    drop constraint feedback_overall_check,
    drop constraint feedback_kindness_check,
    drop constraint feedback_requests_check,
    drop constraint feedback_flow_check;

  alter table public.feedback add column scale smallint;
  update public.feedback set
    overall  = overall  * 2,
    kindness = kindness * 2,
    requests = requests * 2,
    flow     = flow     * 2,
    scale    = 5;                       -- 원래 5점 만점으로 받은 응답
  alter table public.feedback alter column scale set default 10;
  update public.feedback set scale = 5 where scale is null;

  alter table public.feedback
    add constraint feedback_overall_check  check (overall  between 1 and 10),
    add constraint feedback_kindness_check check (kindness between 1 and 10),
    add constraint feedback_requests_check check (requests between 1 and 10),
    add constraint feedback_flow_check     check (flow     between 1 and 10);
end
$mig$;

-- 제출 — 10점으로 받는다. 낮은 점수 알림 기준도 같이 옮긴다(3점 이하 → 6점 이하).
create or replace function public.feedback_submit(p_booking_id uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare b public.bookings; r int;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found then raise exception 'booking not found'; end if;
  if b.status = '취소' then raise exception 'cancelled booking'; end if;
  if exists(select 1 from public.feedback where booking_id = p_booking_id) then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  insert into public.feedback (booking_id, staff_id, overall, arrival, kindness, requests, flow, issue, issue_text, message, scale)
  values (
    p_booking_id, b.assignee_id,
    (payload->>'overall')::smallint,
    coalesce(nullif(payload->>'arrival', ''), 'ontime'),
    (payload->>'kindness')::smallint,
    (payload->>'requests')::smallint,
    (payload->>'flow')::smallint,
    coalesce((payload->>'issue')::boolean, false),
    nullif(left(coalesce(payload->>'issue_text', ''), 1000), ''),
    nullif(left(coalesce(payload->>'message', ''), 1000), ''),
    10
  );

  -- 낮은 점수는 대표에게 바로 알림(놓치지 않게) — 10점 만점에서 6점 이하
  r := (payload->>'overall')::int;
  if r <= 6 then
    perform private.otb_push('⚠️ 촬영 설문 낮은 평가',
      coalesce(b.contractor_name, '') || ' · 전체 ' || r || '점 (10점 만점)', '/admin');
  end if;
  return jsonb_build_object('ok', true);
end; $$;
revoke all on function public.feedback_submit(uuid, jsonb) from public;
grant execute on function public.feedback_submit(uuid, jsonb) to anon, authenticated;
