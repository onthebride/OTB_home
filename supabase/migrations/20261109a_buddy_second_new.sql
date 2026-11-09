-- 두 번째 짝꿍은 새 예약 고객만 (대표 2026-11-09 «우리 2번째 짝궁은 신규예약자만 가능하게 하자 예약 후 일주일 이내 고객만»)
--   새 예약 고객 = 예약한 날부터 일주일 안. 한국 날짜로 센다 — 3일에 예약했으면 10일까지 된다.
--   이번 짝꿍이 어느 쪽에게든 두 번째가 되면, 그쪽의 상대가 새 예약 고객이어야 맺을 수 있다.
--     · 내게 두 번째   → 상대가 새 예약이어야 한다
--     · 상대에게 두 번째 → 내가 새 예약이어야 한다
--   첫 번째 짝꿍은 예전 그대로 조건이 없다.
--   이미 맺은 짝꿍은 그대로 둔다 — 새로 신청하는 것부터.
--   관리자가 직접 넣는 짝꿍(admin_buddy_slot)은 막지 않는다 — 예외는 대표가 정한다.
--   상대의 확인(buddy_confirm)·관리자 승인도 그대로 — 신청할 때 한 번만 본다.
--   시험: .backups/tests/pgrun/buddynew.test.mjs
create or replace function public.buddy_register(p_requester uuid, p_partner_name text, p_partner_date date, p_reward text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare pid uuid; cnt int; my_n int; their_n int;
  today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if not exists(select 1 from public.bookings where id = p_requester) then raise exception 'booking not found'; end if;
  -- 두 분이 같은 때 눌러 세 번째가 끼어들지 않게 줄을 세운다 (짝꿍 신청은 드물다)
  perform pg_advisory_xact_lock(hashtext('public.event_buddy'));
  -- 본인이 이미 두 분과 맺었는지
  select count(*) into my_n from public.event_buddy where status in ('waiting','matched','approved')
     and (requester_id = p_requester or partner_id = p_requester);
  if my_n >= 2 then
    raise exception '짝꿍은 두 분까지 맺으실 수 있어요';
  end if;
  -- 상대 예약 찾기 (예식일 + 계약자명). 취소된 예약은 빼고 본다
  select count(*) into cnt from public.bookings
   where wedding_date = p_partner_date and contractor_name = p_partner_name and status is distinct from '취소';
  if cnt = 0 then raise exception '상대 예약을 찾을 수 없어요. 예식일과 계약자명을 확인해주세요'; end if;
  if cnt > 1 then raise exception '동일 정보의 예약이 여러 건이라 자동 매칭이 어려워요. 관리자에게 문의해주세요'; end if;
  select id into pid from public.bookings
   where wedding_date = p_partner_date and contractor_name = p_partner_name and status is distinct from '취소' limit 1;
  if pid = p_requester then raise exception '본인은 짝꿍이 될 수 없어요'; end if;
  -- 같은 두 분은 한 번만 (누가 먼저 신청했든)
  if exists(select 1 from public.event_buddy where status in ('waiting','matched','approved')
            and ((requester_id = p_requester and partner_id = pid) or (requester_id = pid and partner_id = p_requester))) then
    raise exception '이미 짝꿍으로 맺으신 분이에요';
  end if;
  -- 상대가 이미 두 분과 맺었는지
  select count(*) into their_n from public.event_buddy where status in ('waiting','matched','approved')
     and (requester_id = pid or partner_id = pid);
  if their_n >= 2 then
    raise exception '상대 분은 이미 짝꿍을 두 분과 맺으셨어요';
  end if;
  -- 두 번째 짝꿍은 새 예약 고객만 — 예약한 날부터 일주일 안 (대표 2026-11-09)
  if my_n = 1 and (select today - (b.created_at at time zone 'Asia/Seoul')::date
                     from public.bookings b where b.id = pid) > 7 then
    raise exception '두 번째 짝꿍은 예약하신 지 일주일 이내인 신규 예약 고객과만 맺으실 수 있어요';
  end if;
  if their_n = 1 and (select today - (b.created_at at time zone 'Asia/Seoul')::date
                        from public.bookings b where b.id = p_requester) > 7 then
    raise exception '상대 분께는 이번이 두 번째 짝꿍이에요. 두 번째 짝꿍은 예약하신 지 일주일 이내인 신규 예약 고객만 가능해요';
  end if;
  insert into public.event_buddy(requester_id, partner_id, partner_name, partner_date, reward, status)
    values (p_requester, pid, p_partner_name, p_partner_date, nullif(p_reward,''), 'waiting');
  return jsonb_build_object('ok', true);
end$function$;
