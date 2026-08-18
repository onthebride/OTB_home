-- 20260817_feedback.sql
-- 촬영 후 설문 — 예식 다음날 오전에 계약자에게 알림톡으로 보내는 '작가 촬영 태도' 평가.
-- 사진 결과물은 아직 받기 전이므로 현장 태도만 묻는다.
-- 평가 대상은 메인 작가 1명(2인 촬영이어도 메인만). 응답은 관리자만 열람한다.

create table if not exists public.feedback (
  booking_id  uuid primary key references public.bookings(id) on delete cascade,
  staff_id    uuid references public.staff(id) on delete set null,  -- 응답 시점의 메인 작가(이후 배정이 바뀌어도 보존)
  overall     smallint not null check (overall between 1 and 5),    -- 1. 전체적으로 어떠셨나요
  arrival     text     not null check (arrival in ('ontime', 'late_small', 'late_big')),  -- 2. 도착 시간
  kindness    smallint not null check (kindness between 1 and 5),   -- 3. 친절·예의
  requests    smallint not null check (requests between 1 and 5),   -- 4. 요청 반영
  flow        smallint not null check (flow between 1 and 5),       -- 5. 진행 매끄러움
  issue       boolean  not null default false,                      -- 6. 불편한 점 있었는지
  issue_text  text,
  message     text,                                                 -- 7. 작가님께 한마디
  created_at  timestamptz not null default now()
);
create index if not exists feedback_staff_idx on public.feedback (staff_id);

alter table public.feedback enable row level security;
revoke all on public.feedback from anon, authenticated;

-- ── 손님용 (링크: /f?b=<예약ID>) ──────────────────────────────
-- 설문 화면에 필요한 최소 정보만. 연락처 등 다른 개인정보는 내보내지 않는다.
create or replace function public.feedback_ctx(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare b public.bookings; sname text;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found then return null; end if;
  select name into sname from public.staff where id = b.assignee_id;
  return jsonb_build_object(
    'contractor_name', b.contractor_name,
    'wedding_date', b.wedding_date,
    'wedding_venue', b.wedding_venue,
    'staff_name', sname,
    'cancelled', b.status = '취소',
    'done', exists(select 1 from public.feedback f where f.booking_id = p_booking_id)
  );
end; $$;
revoke all on function public.feedback_ctx(uuid) from public;
grant execute on function public.feedback_ctx(uuid) to anon, authenticated;

-- 제출. 한 예약당 1회(이미 있으면 조용히 무시 — 손님에게는 '이미 참여' 화면).
create or replace function public.feedback_submit(p_booking_id uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare b public.bookings; r5 int;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found then raise exception 'booking not found'; end if;
  if b.status = '취소' then raise exception 'cancelled booking'; end if;
  if exists(select 1 from public.feedback where booking_id = p_booking_id) then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  insert into public.feedback (booking_id, staff_id, overall, arrival, kindness, requests, flow, issue, issue_text, message)
  values (
    p_booking_id, b.assignee_id,
    (payload->>'overall')::smallint,
    coalesce(nullif(payload->>'arrival', ''), 'ontime'),
    (payload->>'kindness')::smallint,
    (payload->>'requests')::smallint,
    (payload->>'flow')::smallint,
    coalesce((payload->>'issue')::boolean, false),
    nullif(left(coalesce(payload->>'issue_text', ''), 1000), ''),
    nullif(left(coalesce(payload->>'message', ''), 1000), '')
  );

  -- 낮은 점수는 대표에게 바로 알림(놓치지 않게)
  r5 := (payload->>'overall')::int;
  if r5 <= 3 then
    perform private.otb_push('⚠️ 촬영 설문 낮은 평가',
      coalesce(b.contractor_name, '') || ' · 전체 ' || r5 || '점', '/admin');
  end if;
  return jsonb_build_object('ok', true);
end; $$;
revoke all on function public.feedback_submit(uuid, jsonb) from public;
grant execute on function public.feedback_submit(uuid, jsonb) to anon, authenticated;

-- ── 관리자용 ─────────────────────────────────────────────────
-- 작가별 집계 + 응답 목록(최근순). 대표만 열람하며, 작가에게 자동으로 가지 않는다.
create or replace function public.admin_feedback(p_days int default 365)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare n_days int := least(greatest(coalesce(p_days, 365), 1), 3650); res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  with f as (
    select fb.*, s.name as staff_name, b.contractor_name, b.wedding_date, b.wedding_venue
    from public.feedback fb
    join public.bookings b on b.id = fb.booking_id
    left join public.staff s on s.id = fb.staff_id
    where fb.created_at >= now() - (n_days || ' days')::interval
  )
  select jsonb_build_object(
    'count', (select count(*) from f),
    'avg_overall', (select round(avg(overall)::numeric, 2) from f),
    'staff', coalesce((select jsonb_agg(t order by t.avg_overall desc nulls last) from (
        select coalesce(staff_name, '(배정 없음)') as staff_name,
               count(*) as n,
               round(avg(overall)::numeric, 2)  as avg_overall,
               round(avg(kindness)::numeric, 2) as avg_kindness,
               round(avg(requests)::numeric, 2) as avg_requests,
               round(avg(flow)::numeric, 2)     as avg_flow,
               count(*) filter (where arrival <> 'ontime') as late_n,
               count(*) filter (where issue)               as issue_n
        from f group by 1) t), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(t order by t.created_at desc) from (
        select booking_id, created_at, coalesce(staff_name, '(배정 없음)') as staff_name,
               contractor_name, wedding_date, wedding_venue,
               overall, arrival, kindness, requests, flow, issue, issue_text, message
        from f) t), '[]'::jsonb)
  ) into res;
  return res;
end; $$;
revoke all on function public.admin_feedback(int) from public, anon;
grant execute on function public.admin_feedback(int) to authenticated;

-- 아직 설문을 안 보낸 지난 예식 목록(수동 발송·링크 복사용)
create or replace function public.admin_feedback_pending()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(t order by t.wedding_date desc), '[]'::jsonb) into res from (
    select b.id, b.contractor_name, b.wedding_date, b.wedding_venue,
           s.name as staff_name,
           (coalesce(b.alimtalk_sent, '{}'::jsonb) -> 'G') is not null as sent,
           exists(select 1 from public.feedback f where f.booking_id = b.id) as done
    from public.bookings b
    left join public.staff s on s.id = b.assignee_id
    where b.status <> '취소'
      and b.wedding_date is not null
      and b.wedding_date < current_date
      and b.wedding_date >= current_date - 60
  ) t;
  return res;
end; $$;
revoke all on function public.admin_feedback_pending() from public, anon;
grant execute on function public.admin_feedback_pending() to authenticated;

-- ── 알림톡 G (촬영 설문 요청) ────────────────────────────────
-- 예식 다음날 오전 10시 자동발송. 기존 일일 크론(otb-alimtalk-daily, 01:00 UTC = 10:00 KST)에 얹는다.
create or replace function private.alimtalk_send_scheduled()
returns int language plpgsql security definer set search_path=private, public, extensions, pg_temp as $$
declare r record; n int := 0; vars jsonb; req bigint;
begin
  for r in
    select b.id, b.contractor_name, b.contractor_phone, x.tpl
    from public.bookings b
    cross join (values ('B', (current_date + 30)), ('C', (current_date + 7)), ('D', (current_date + 1)),
                       ('G', (current_date - 1))) as x(tpl, dday)   -- G: 예식 다음날 촬영 설문
    where b.status <> '취소' and coalesce(b.deposit_paid,false)
      and b.wedding_date = x.dday
      and b.contractor_phone is not null
      and (coalesce(b.alimtalk_sent,'{}'::jsonb) -> x.tpl) is null
  loop
    vars := jsonb_build_object('#{고객명}', coalesce(r.contractor_name,''), '#{예약ID}', r.id::text);
    req := private.alimtalk_dispatch(r.id, r.tpl, r.contractor_phone, vars);
    update public.bookings set alimtalk_sent = coalesce(alimtalk_sent,'{}'::jsonb) || jsonb_build_object(r.tpl, to_jsonb(now())) where id = r.id;
    n := n + 1;
  end loop;
  return n;
end$$;

-- 관리자 수동 발송에도 G 허용
create or replace function public.admin_send_alimtalk(p_booking_id uuid, p_template text)
returns jsonb language plpgsql security definer set search_path=public, private, extensions, pg_temp as $$
declare b public.bookings; vars jsonb; req bigint;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select * into b from public.bookings where id = p_booking_id; if not found then raise exception 'booking not found'; end if;
  if b.contractor_phone is null then raise exception '연락처가 없습니다'; end if;
  if p_template not in ('A','B','C','D','E','F','G') then raise exception 'bad template'; end if;
  if p_template = 'E' and b.download_link is null then raise exception '다운로드 링크를 먼저 입력하세요'; end if;

  vars := jsonb_build_object('#{고객명}', coalesce(b.contractor_name,''), '#{예약ID}', b.id::text);
  req := private.alimtalk_dispatch(p_booking_id, p_template, b.contractor_phone, vars);
  update public.bookings set alimtalk_sent = coalesce(alimtalk_sent,'{}'::jsonb) || jsonb_build_object(p_template, to_jsonb(now())) where id = p_booking_id;
  return jsonb_build_object('ok', true, 'req', req);
end$$;
revoke all on function public.admin_send_alimtalk(uuid, text) from public, anon;
grant execute on function public.admin_send_alimtalk(uuid, text) to authenticated;

-- 실패 알림 문구에 G 이름 (기존 함수의 인자명 p 를 그대로 써야 replace 가능)
create or replace function private.atk_kname(p text) returns text language sql immutable as $fn$
  select case p when 'A' then '계약안내' when 'B' then '한달전' when 'C' then '잔금안내' when 'D' then '최종안내'
                when 'E' then '링크안내' when 'F' then '입금확인' when 'G' then '촬영 설문' else p end;
$fn$;

-- 2026-08-18: 관리자 목록 표시 변경(신부이름 추가)
-- 관리자 작가평가 목록에 신부 이름 추가 (표시를 "작가 (신부이름 예식날짜)" 로 바꾸기 위함)
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
    'staff', coalesce((select jsonb_agg(t order by t.avg_overall desc nulls last) from (
        select coalesce(staff_name, '(배정 없음)') as staff_name,
               count(*) as n,
               round(avg(overall)::numeric, 2)  as avg_overall,
               round(avg(kindness)::numeric, 2) as avg_kindness,
               round(avg(requests)::numeric, 2) as avg_requests,
               round(avg(flow)::numeric, 2)     as avg_flow,
               count(*) filter (where arrival <> 'ontime') as late_n,
               count(*) filter (where issue)               as issue_n
        from f group by 1) t), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(t order by t.created_at desc) from (
        select booking_id, created_at, coalesce(staff_name, '(배정 없음)') as staff_name,
               contractor_name, bride_name, wedding_date, wedding_venue,
               overall, arrival, kindness, requests, flow, issue, issue_text, message
        from f) t), '[]'::jsonb)
  ) into res;
  return res;
end; $fn$;
revoke all on function public.admin_feedback(int) from public, anon;
grant execute on function public.admin_feedback(int) to authenticated;
