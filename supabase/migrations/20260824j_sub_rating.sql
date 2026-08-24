-- 서브 작가 별점 (대표 요청 2026-08-24)
--   "이게 촬영후 설문에 2인 촬영인데 서브작가에대한 불만을 적어버리면
--    메인이 피해를 볼거 같은데 어떻게 나눠야하나?"
--   "그냥 설문은 메인작가에대한 설문이라고 그냥 붙이자
--    서브작가가 있으면 서브 작가 문항을 하나 넣자 별점으로"
--
-- 지금은 설문 점수가 통째로 메인(assignee_id)에게 붙는다. 2인 촬영에서 서브가
-- 아쉬웠다고 적으면 그 점수를 메인이 뒤집어쓴다. 앞으로 올 2인 촬영이 29건이다.
--
-- 나누는 방법 —
--   · 지금 문항들은 «메인 작가에 대한 것» 이라고 화면에 못 박는다
--   · 서브가 배정된 예식에만 별점 한 칸을 더 둔다 (1~5)
-- 서브 점수를 메인의 100점 만점 점수와 섞지 않는다. 물어본 것이 다르기 때문이다.
-- 화면에서도 따로 보여준다.

alter table public.feedback add column if not exists sub_staff_id uuid references public.staff(id) on delete set null;
alter table public.feedback add column if not exists sub_stars smallint;
do $$ begin
  alter table public.feedback add constraint feedback_sub_stars_range check (sub_stars is null or sub_stars between 1 and 5);
exception when duplicate_object then null; end $$;
create index if not exists feedback_sub_staff_idx on public.feedback (sub_staff_id);

comment on column public.feedback.sub_staff_id is '응답 시점의 서브 작가(2인 촬영). 이후 배정이 바뀌어도 보존';
comment on column public.feedback.sub_stars  is '서브 작가 별점 1~5. 메인의 100점 만점 점수와 섞지 않는다';

-- ── 설문 화면이 쓰는 정보 — 서브 작가 이름을 함께 준다 ──────
create or replace function public.feedback_ctx(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare b public.bookings; sname text; subname text;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found then return null; end if;
  select name into sname   from public.staff where id = b.assignee_id;
  select name into subname from public.staff where id = b.sub_assignee_id;
  return jsonb_build_object(
    'contractor_name', b.contractor_name,
    'wedding_date', b.wedding_date,
    'wedding_venue', b.wedding_venue,
    'staff_name', sname,
    -- 서브가 배정돼 있을 때만 별점 문항을 띄운다. 배정이 없으면 물어볼 대상이 없다
    'sub_name', subname,
    'cancelled', b.status = '취소',
    'done', exists(select 1 from public.feedback f where f.booking_id = p_booking_id)
  );
end; $fn$;
revoke all on function public.feedback_ctx(uuid) from public;
grant execute on function public.feedback_ctx(uuid) to anon, authenticated;

-- ── 제출 — 서브 별점을 함께 받는다 ───────────────────────────
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
  if sub is not null and (sub < 1 or sub > 5) then sub := null; end if;

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
  -- 서브 별점이 낮으면 그것도 알린다. 메인 점수만 보면 안 보이는 것이다
  if sub is not null and sub <= 2 then
    select name into subname from public.staff where id = b.sub_assignee_id;
    perform private.otb_push('⚠️ 서브 작가 낮은 평가',
      coalesce(b.contractor_name, '') || ' · ' || coalesce(subname, '서브') || ' ' || sub || '점 (5점 만점)', '/admin');
  end if;

  return jsonb_build_object('ok', true);
end$fn$;
revoke all on function public.feedback_submit(uuid, jsonb) from public;
grant execute on function public.feedback_submit(uuid, jsonb) to anon, authenticated;
