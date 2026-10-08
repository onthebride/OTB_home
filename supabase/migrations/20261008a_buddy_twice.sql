-- 짝꿍 두 번까지 (대표 2026-10-08 «ㅇㅋ 그대로 하고 짝궁 2번까지해서 전반적으로 고쳐줘»)
--   후기는 그대로 1회 — 한 분이 받을 수 있는 혜택은 최대 셋(짝꿍 둘 + 후기 하나).
--   두 번째 짝꿍도 혜택 하나 더(1만원 할인 또는 앨범 1권). 이미 한 번 하신 분도 바로 열린다.
--   「한 번」 을 전제로 짠 자리를 고친다:
--     ① buddy_register — 활성 1건이면 막던 것을 2건으로. 같은 두 분은 두 번 못 맺는다.
--        취소된 예약과는 못 맺는다 (취소하면 짝꿍이 풀리는 것과 맞춘다)
--     ② buddy_set_reward — 「최근 1건」 을 고르던 것을 짝꿍 id 로. 옛 앞단은 id 없이 불러도 그대로 돈다
--     ③ admin_buddy_slot (새로) — 관리자 예약 상세의 「짝꿍 1 · 짝꿍 2」 한 줄씩.
--        옛 admin_set_buddy 는 그대로 둔다 — 캐시된 옛 관리자 화면이 부른다
--     ④ portal_booking_info — 맺은 짝꿍 전부(buddies)와 잔금 할인·혜택을 전부 센다.
--        옛 buddy(최근 1건)는 남긴다 — 캐시된 옛 손님 화면이 본다
--   admin_event_discounts 는 이미 짝꿍마다 더하고 있어 안 고친다.
--   ⚠ 이 파일은 .backups/tests/pgrun/_buddy_twice_patch.mjs 가 라이브 정의에서 만든다 (④)

-- ① 신청 — 두 분까지
create or replace function public.buddy_register(p_requester uuid, p_partner_name text, p_partner_date date, p_reward text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare pid uuid; cnt int;
begin
  if not exists(select 1 from public.bookings where id = p_requester) then raise exception 'booking not found'; end if;
  -- 두 분이 같은 때 눌러 세 번째가 끼어들지 않게 줄을 세운다 (짝꿍 신청은 드물다)
  perform pg_advisory_xact_lock(hashtext('public.event_buddy'));
  -- 본인이 이미 두 분과 맺었는지
  if (select count(*) from public.event_buddy where status in ('waiting','matched','approved')
        and (requester_id = p_requester or partner_id = p_requester)) >= 2 then
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
  if (select count(*) from public.event_buddy where status in ('waiting','matched','approved')
        and (requester_id = pid or partner_id = pid)) >= 2 then
    raise exception '상대 분은 이미 짝꿍을 두 분과 맺으셨어요';
  end if;
  insert into public.event_buddy(requester_id, partner_id, partner_name, partner_date, reward, status)
    values (p_requester, pid, p_partner_name, p_partner_date, nullif(p_reward,''), 'waiting');
  return jsonb_build_object('ok', true);
end$function$;

-- ② 혜택 바꾸기 — 어느 짝꿍인지 id 로 (칸을 더하니 옛것을 먼저 지운다 — 안 지우면 이름이 겹쳐 부를 때 터진다)
drop function if exists public.buddy_set_reward(uuid, text);
create or replace function public.buddy_set_reward(p_booking uuid, p_reward text, p_buddy_id uuid default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare bd public.event_buddy;
begin
  if p_reward not in ('할인','앨범') then raise exception 'bad reward'; end if;
  select * into bd from public.event_buddy
   where status in ('waiting','matched','approved') and (requester_id = p_booking or partner_id = p_booking)
     and (p_buddy_id is null or id = p_buddy_id)
   order by created_at desc, id desc limit 1;
  if not found then raise exception '짝꿍 참여 내역이 없어요'; end if;
  if bd.requester_id = p_booking then
    update public.event_buddy set reward = p_reward where id = bd.id;
  else
    update public.event_buddy set partner_reward = p_reward where id = bd.id;
  end if;
  return jsonb_build_object('ok', true);
end$function$;
revoke all on function public.buddy_set_reward(uuid, text, uuid) from public;
grant execute on function public.buddy_set_reward(uuid, text, uuid) to anon, authenticated, service_role;

-- ③ 관리자 — 짝꿍 한 줄씩 켜고 끈다
--   p_buddy_id 가 있으면 그 짝꿍을 승인(혜택과 함께) 하거나 취소한다.
--   없고 켜면 관리자가 직접 넣는 짝꿍(상대 없음)을 하나 만든다 — 두 분이 찼으면 막는다.
create or replace function public.admin_buddy_slot(p_booking uuid, p_buddy_id uuid, p_on boolean, p_reward text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare bd public.event_buddy; n int;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_on and p_reward is distinct from '할인' and p_reward is distinct from '앨범' then raise exception 'bad reward'; end if;
  perform pg_advisory_xact_lock(hashtext('public.event_buddy'));
  if p_buddy_id is not null then
    select * into bd from public.event_buddy
     where id = p_buddy_id and status in ('waiting','matched','approved')
       and (requester_id = p_booking or partner_id = p_booking);
    if not found then raise exception '짝꿍 정보를 찾을 수 없어요'; end if;
    if p_on then
      update public.event_buddy set status = 'approved', approved_at = coalesce(approved_at, now()),
        reward = case when requester_id = p_booking then p_reward else reward end,
        partner_reward = case when partner_id = p_booking then p_reward else partner_reward end
      where id = bd.id;
    else
      update public.event_buddy set status = 'canceled' where id = bd.id;
    end if;
  elsif p_on then
    select count(*) into n from public.event_buddy
     where status in ('waiting','matched','approved') and (requester_id = p_booking or partner_id = p_booking);
    if n >= 2 then raise exception '짝꿍은 두 분까지예요'; end if;
    insert into public.event_buddy(requester_id, partner_id, reward, status, approved_at)
      values (p_booking, null, p_reward, 'approved', now());
  end if;
  return jsonb_build_object('ok', true);
end$function$;
revoke all on function public.admin_buddy_slot(uuid, uuid, boolean, text) from public, anon;
grant execute on function public.admin_buddy_slot(uuid, uuid, boolean, text) to authenticated, service_role;

-- ④ 손님 페이지 — 맺은 짝꿍 전부 · 혜택 전부
CREATE OR REPLACE FUNCTION public.portal_booking_info(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$

declare b public.bookings; bd public.event_buddy; rv public.event_review;
  has_s boolean; total int; buddy jsonb; pname text; buddies jsonb := '[]'::jsonb; bx record;
  my_reward text; my_role text; rewards jsonb := '[]'::jsonb; discount int := 0; eff_total int;
  photog jsonb; reveal boolean; pm_name text; pm_phone text; ps_name text; ps_phone text;
  sv_open boolean; sv_from date;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found then return null; end if;
  select exists(select 1 from public.surveys where booking_id = p_booking_id) into has_s;

  -- 예식 전 설문은 예식 한 달 전부터 열어준다 (대표 요청 2026-08-22).
  -- 너무 일찍 물으면 그때 정해지지 않은 것들이라 다시 고쳐야 한다.
  -- 이미 낸 분은 언제든 고칠 수 있게 계속 열어둔다.
  sv_from := b.wedding_date - 30;
  sv_open := b.wedding_date is null or has_s or current_date >= sv_from;

  -- 담당 작가: 예식 일주일 전부터만 공개 (그 전엔 숨김)
  reveal := b.wedding_date is not null and b.wedding_date <= (current_date + 7);
  if reveal then
    select name, phone into pm_name, pm_phone from public.staff where id = b.assignee_id;
    -- 서브작가는 2인 촬영일 때만 노출 (2인→기본 변경 후 잔존 sub_assignee_id 방지)
    if b.photographer = '2인 촬영' then
      select name, phone into ps_name, ps_phone from public.staff where id = b.sub_assignee_id;
    end if;
  end if;
  photog := jsonb_build_object('reveal', reveal, 'main_name', pm_name, 'main_phone', pm_phone, 'sub_name', ps_name, 'sub_phone', ps_phone);
  total := coalesce(b.total_price, 0);

  -- 짝꿍 상태 — 최근 1건(buddy)은 캐시된 옛 화면용. 전부는 아래 buddies (2026-10-08 짝꿍 두 번까지)
  select * into bd from public.event_buddy
   where status in ('waiting','matched','approved')
     and (requester_id = p_booking_id or partner_id = p_booking_id)
   order by created_at desc limit 1;
  if not found then
    buddy := jsonb_build_object('state','none');
  elsif bd.requester_id = p_booking_id then
    select contractor_name into pname from public.bookings where id = bd.partner_id;
    my_role := 'requester'; my_reward := bd.reward;
    buddy := jsonb_build_object('state',
      case bd.status when 'waiting' then 'sent_waiting' when 'matched' then 'matched' else 'approved' end,
      'partner_name', coalesce(pname, bd.partner_name), 'reward', my_reward, 'id', bd.id);
  else  -- partner_id = me
    select contractor_name into pname from public.bookings where id = bd.requester_id;
    my_role := 'partner'; my_reward := bd.partner_reward;
    buddy := jsonb_build_object('state',
      case bd.status when 'waiting' then 'incoming_confirm' when 'matched' then 'matched' else 'approved' end,
      'partner_name', pname, 'reward', my_reward, 'id', bd.id);
  end if;

  -- 맺은 짝꿍 전부 — 맺은 차례대로 (대표 2026-10-08 «짝궁 2번까지»)
  select coalesce(jsonb_agg(x.j order by x.created_at, x.id), '[]'::jsonb) into buddies
  from (
    select e.created_at, e.id, jsonb_build_object(
      'id', e.id,
      'my_role', case when e.requester_id = p_booking_id then 'requester' else 'partner' end,
      'state', case
        when e.status = 'approved' then 'approved'
        when e.status = 'matched' then 'matched'
        when e.requester_id = p_booking_id then 'sent_waiting'
        else 'incoming_confirm' end,
      'partner_name', case when e.requester_id = p_booking_id
        then coalesce((select o.contractor_name from public.bookings o where o.id = e.partner_id), e.partner_name)
        else (select o.contractor_name from public.bookings o where o.id = e.requester_id) end,
      'reward', case when e.requester_id = p_booking_id then e.reward else e.partner_reward end) j
    from public.event_buddy e
    where e.status in ('waiting','matched','approved')
      and (e.requester_id = p_booking_id or e.partner_id = p_booking_id)
  ) x;

  select * into rv from public.event_review where booking_id = p_booking_id;

  -- 승인된 이벤트 혜택만 금액/옵션에 반영
  -- 짝꿍은 승인된 것 전부 (두 분까지) — 한 분마다 혜택 하나
  for bx in
    select case when e.requester_id = p_booking_id then e.reward else e.partner_reward end as rw
    from public.event_buddy e
    where e.status = 'approved' and (e.requester_id = p_booking_id or e.partner_id = p_booking_id)
    order by e.created_at, e.id
  loop
    if bx.rw is not null then
      rewards := rewards || jsonb_build_object('type','짝꿍','reward', bx.rw);
      if bx.rw = '할인' then discount := discount + 1; end if;
    end if;
  end loop;
  if rv.id is not null and rv.status = 'approved' and rv.reward is not null then
    rewards := rewards || jsonb_build_object('type','후기','reward', rv.reward);
    if rv.reward = '할인' then discount := discount + 1; end if;
  end if;
  eff_total := total - discount;

  return jsonb_build_object(
    'contractor_name', b.contractor_name,
    'wedding_date', b.wedding_date,
    'wedding_time', public.fmt_ktime(b.wedding_time),
    'wedding_venue', b.wedding_venue,
    'package', b.package,
    'items', public.booking_options_struct(b.id),
    'total_price', total,
    'event_rewards', rewards,
    'discount', discount,
    'effective_total', eff_total,
    'deposit', 10,
    'balance', eff_total - 10,
    'deposit_paid', coalesce(b.deposit_paid, false),
    'balance_paid', coalesce(b.balance_paid, false),
    -- 원본 다운로드: 잔금 입금 확인 시에만 링크 노출(서버측 게이트)
    'download_ready', (coalesce(b.balance_paid, false) and b.download_link is not null),
    'download_link', case when coalesce(b.balance_paid, false) then b.download_link else null end,
    'status', b.status,
    'survey_done', has_s,
    'survey_open', sv_open,
    'survey_open_at', sv_from,
    'photographer', photog,
    'buddy', buddy || jsonb_build_object('my_role', my_role),
    'buddies', buddies,
    'buddy_max', 2,
    'review', case when rv.id is null then null else
      jsonb_build_object('link', rv.link, 'reward', rv.reward, 'status', rv.status) end
  );
end$function$;
