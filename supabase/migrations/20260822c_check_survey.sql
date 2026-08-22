-- 배정 확인에 «신부 설문 확인» 체크를 하나 더. (대표 요청 2026-08-22)
--
-- 지금 체크는 셋이다.
--   [ ] 참석 / 스케줄 확정
--   [ ] 도착 시간 숙지
--   [ ] 옵션 · 요청사항 숙지
-- 여기에 넷째를 붙인다.
--   [ ] 신부 설문 확인
--
-- ── 설문이 아직 안 들어온 예식은? ──────────────────────────
-- 읽을 게 없으니 이 체크로 막지 않는다. 화면에서는 «신부 설문 없음» 으로
-- 보여주고, 완료 판정에서도 빼준다.
--
-- ── 설문이 나중에 들어오면? ────────────────────────────────
-- 작가가 이미 확인을 마친 뒤에 신부가 설문을 내면, 그 예식은 다시 «미확인» 으로
-- 돌아간다. 새로 들어온 요청사항을 작가가 봐야 하기 때문이다.
-- 대표 화면의 미확인 목록에 다시 뜬다.
--
-- ── 이미 확인을 마친 56건은? ───────────────────────────────
-- 예전 규칙(셋)으로 이미 끝낸 것들이다. 넷째가 생겼다고 미확인으로 되돌리면
-- 지나간 예식까지 목록에 쏟아진다. 그래서 셋을 다 채운 기록은 넷째도 채워 둔다.

alter table public.assignment_checks
  add column if not exists survey boolean not null default false;

update public.assignment_checks
   set survey = true
 where attend and arrival and options and not survey;

-- ── 작가가 확인을 낼 때 ─────────────────────────────────────
create or replace function public.submit_assignment_check(payload jsonb)
returns void language plpgsql security definer set search_path = public, pg_temp as $fn$
declare bid uuid; sid uuid;
begin
  bid := nullif(payload->>'booking_id','')::uuid;
  sid := nullif(payload->>'staff_id','')::uuid;
  if bid is null or sid is null then raise exception 'bad request'; end if;
  if not exists(select 1 from public.bookings where id = bid and (assignee_id = sid or sub_assignee_id = sid)) then
    raise exception 'not assigned';
  end if;
  insert into public.assignment_checks (booking_id, staff_id, attend, arrival, options, survey, note, checked_at)
  values (bid, sid, coalesce((payload->>'attend')::boolean,false), coalesce((payload->>'arrival')::boolean,false),
          coalesce((payload->>'options')::boolean,false), coalesce((payload->>'survey')::boolean,false),
          nullif(payload->>'note',''), now())
  on conflict (booking_id, staff_id) do update set
    attend = excluded.attend, arrival = excluded.arrival, options = excluded.options,
    survey = excluded.survey, note = excluded.note, checked_at = now();
end$fn$;

-- ── 완료로 볼지 판정하는 한 곳 ──────────────────────────────
-- 세 군데(대표 미확인 목록·작가 화면 둘)가 같은 기준을 써야 해서 함수로 뺀다
create or replace function public.check_done(p_booking_id uuid, p_staff_id uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $fn$
  select exists(
    select 1 from public.assignment_checks c
     where c.booking_id = p_booking_id and c.staff_id = p_staff_id
       and c.attend and c.arrival and c.options
       -- 설문이 들어온 예식만 넷째를 따진다
       and (c.survey or not exists(select 1 from public.surveys sv where sv.booking_id = p_booking_id)));
$fn$;
revoke all on function public.check_done(uuid, uuid) from public;
grant execute on function public.check_done(uuid, uuid) to anon, authenticated;
