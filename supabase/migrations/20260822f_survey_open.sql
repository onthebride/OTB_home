-- 내 예약 확인의 «예식 전 설문» 을 예식 한 달 전부터 열어준다. (대표 요청 2026-08-22)
--
-- 지금은 예약하자마자 설문 칸이 열려 있다. 예식이 1년 뒤인 분에게 지금 물어봐야
-- 그때 가서 다 바뀐다. 담당 작가를 예식 일주일 전부터 보여주는 것과 같은 결이다.
--
--   survey_open     지금 열려 있는지
--   survey_open_at  언제부터 열리는지 (화면에 «9월 12일부터» 라고 알려주려고)
--
-- 이미 낸 분은 계속 열어둔다 — 낸 것을 못 고치게 막으면 안 된다.
-- 화면에서만 잠근다. 대표가 «미리 좀 써주세요» 하고 링크를 따로 보낼 수도 있어서
-- 설문 저장 자체는 막지 않는다.

create or replace function public.portal_booking_info(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$

declare b public.bookings; bd public.event_buddy; rv public.event_review;
  has_s boolean; total int; buddy jsonb; pname text;
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

  -- 짝꿍 상태 (활성 1건)
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

  select * into rv from public.event_review where booking_id = p_booking_id;

  -- 승인된 이벤트 혜택만 금액/옵션에 반영
  if bd.id is not null and bd.status = 'approved' and my_reward is not null then
    rewards := rewards || jsonb_build_object('type','짝꿍','reward', my_reward);
    if my_reward = '할인' then discount := discount + 1; end if;
  end if;
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
    'review', case when rv.id is null then null else
      jsonb_build_object('link', rv.link, 'reward', rv.reward, 'status', rv.status) end
  );
end$fn$;
revoke all on function public.portal_booking_info(uuid) from public;
grant execute on function public.portal_booking_info(uuid) to anon, authenticated;
