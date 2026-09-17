-- 예약 접수가 우선순위·지정을 같이 받는다 (대표 2026-09-17 «예약 폼 넣자»)
--
-- ⚠⚠ **지정비는 서버가 셈한다. 손님이 보낸 값은 안 믿는다.**
--   예약 폼은 로그인 전이라 payload 를 누구든 꾸며 보낼 수 있다.
--   그래서 고른 작가의 지금 금액을 **DB 에서 다시 읽어** 값을 만들고,
--   손님이 보낸 「작가 지정」 줄은 걷어내고 서버 값으로 다시 넣는다.
--   그래야 신부님이 보신 총액과 우리가 받은 총액이 같아진다.
--
-- ⚠⚠ **폼을 채우는 사이에 그 작가가 그날 찰 수 있다.**
--   그때는 조용히 넘기지 않고 「그 작가님이 그날 어려워지셨다」고 돌려준다 —
--   돈을 받는 자리라 어긋난 채로 접수되면 안 된다.
--
-- ⚠ 우선순위는 **약속이 아니다**(「가능한 맞춰드립니다»). 그래서 그날 되는지 안 본다.
--   없는 작가·서브 전용이 섞여 오면 조용히 걸러내기만 한다.
--
-- ⚠ 값은 모두 **만원 단위**다 (total_price 가 integer 만원, line_items 도 만원).
--   그래서 지정비도 만원 단위여야 한다 — 아래 제약으로 막는다.
--   6만5천원 같은 값이 들어오면 총액이 6.5 가 되어 정수 칸에 안 들어간다.

/* ===== 지정비는 만원 단위 ===== */
alter table public.staff drop constraint if exists staff_pick_fee_range;
alter table public.staff add constraint staff_pick_fee_range
  check (pick_fee is null or pick_fee = 0
         or (pick_fee >= 50000 and pick_fee <= 1000000 and pick_fee % 10000 = 0));

create or replace function public.staff_settings_set(p_staff_id uuid, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'private', 'pg_temp' as $$
declare e jsonb; r jsonb; fee int; cap int; fmin int;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and coalesce(active,false)) then
    raise exception 'staff not found';
  end if;
  if jsonb_typeof(p_patch) <> 'object' then raise exception 'bad patch'; end if;

  if p_patch ? 'accepting' then
    if jsonb_typeof(p_patch->'accepting') <> 'boolean' then raise exception 'bad accepting'; end if;
    update public.staff set accepting = (p_patch->>'accepting')::boolean where id = p_staff_id;
  end if;

  if p_patch ? 'pick_fee' then
    e := private.pick_eligible(p_staff_id);
    r := private.pick_rules();
    if not (e->>'ok')::boolean then
      raise exception 'not eligible: shots %/% reviews %/% gallery %/% accepting % can_main %',
        e->>'shots', e->>'need_shots', e->>'reviews', e->>'need_reviews',
        e->>'gallery', e->>'need_gallery', e->>'accepting', e->>'can_main';
    end if;
    fee := nullif(p_patch->>'pick_fee','')::int;
    if fee is not null and fee < 0 then raise exception 'bad fee'; end if;
    fmin := (r->>'fee_min')::int;
    if fee is not null and fee > 0 and fee < fmin then
      raise exception '지정 촬영비는 %원부터 정하실 수 있어요 (안 받으시려면 0)',
        to_char(fmin, 'FM999,999,999');
    end if;
    -- ⚠ 만원 단위. 예약 총액이 만원 단위 정수라 그 아래는 담을 곳이 없다
    if fee is not null and fee % 10000 <> 0 then
      raise exception '만원 단위로 정해주세요 (예: 50,000 · 60,000 · 100,000)';
    end if;
    cap := (e->>'fee_cap')::int;
    if fee is not null and fee > cap then
      raise exception '지금 한도는 %원입니다 (촬영 %회·후기 %개·사진 %장). 더 쌓이면 한도가 올라갑니다',
        to_char(cap, 'FM999,999,999'), e->>'shots', e->>'reviews', e->>'gallery';
    end if;
    update public.staff set pick_fee = fee, pick_fee_at = now() where id = p_staff_id;
  end if;

  return public.staff_settings(p_staff_id);
end$$;
revoke all on function public.staff_settings_set(uuid, jsonb) from public;
grant execute on function public.staff_settings_set(uuid, jsonb) to anon, authenticated;

/* ===== 접수 ===== */
create or replace function public.submit_booking_v2(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp
as $fn$
declare
  new_id uuid; li jsonb; tot int; ph text; wd date; dup_at timestamptz;
  wish uuid[]; pin uuid; pin_fee int; pin_name text;
begin
  -- ① 이미 들어온 것이 있나
  ph := private.fmt_phone(nullif(payload->>'contractor_phone',''));
  wd := nullif(payload->>'wedding_date','')::date;
  if not coalesce((payload->>'force')::boolean, false) and ph is not null and wd is not null then
    select b.created_at into dup_at from public.bookings b
     where b.contractor_phone = ph and b.wedding_date = wd
       and b.status in ('신규','확정')
     order by b.created_at limit 1;
    if dup_at is not null then
      return jsonb_build_object(
        'ok', false, 'reason', 'dup',
        'at', to_char(dup_at at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI'),
        'at_txt', to_char(dup_at at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI'));
    end if;
  end if;

  /* ② 작가 우선순위 — 셋까지. 없는 사람·서브 전용·쉬는 분은 **조용히 걸러낸다**
       (약속이 아니라 희망이라 「안 됩니다」 할 자리가 아니다).
     ⚠ 차례가 뜻이다. ordinality 로 들어온 순서를 지킨다 */
  select array_agg(x order by ord) into wish from (
    select distinct on (x) x, ord from
      jsonb_array_elements_text(coalesce(payload->'pick_wish', '[]'::jsonb))
        with ordinality as e(x, ord)
     where x ~ '^[0-9a-f-]{36}$'
       and exists (select 1 from public.staff s where s.id = x::uuid
                    and coalesce(s.active,false) and coalesce(s.can_main,true)
                    and coalesce(s.accepting,true))
     order by x, ord
  ) t2;
  wish := (select array_agg(w order by o) from (
      select w, min(o) o from unnest(wish) with ordinality u(w, o) group by w) z);
  if wish is not null and cardinality(wish) > 3 then wish := wish[1:3]; end if;

  /* ③ 작가 지정 — 한 명. **돈을 받는 자리라 어긋나면 접수하지 않는다** */
  pin := nullif(payload->>'pick_pin','')::uuid;
  if pin is not null then
    select s.name,
           case when s.pick_fee is null
                then (private.pick_rules()->>'pin_default')::int else s.pick_fee end
      into pin_name, pin_fee
      from public.staff s
     where s.id = pin and coalesce(s.active,false) and coalesce(s.can_main,true)
       and coalesce(s.accepting,true) and coalesce(s.pick_fee, 1) <> 0;
    if pin_name is null then
      return jsonb_build_object('ok', false, 'reason', 'pin_gone');
    end if;
    -- 폼을 채우는 사이에 그날이 찼을 수 있다
    if wd is not null and (
         exists (select 1 from public.staff_busy sb where sb.staff_id = pin and sb.the_date = wd)
      or exists (select 1 from public.bookings b
                  where (b.assignee_id = pin or b.sub_assignee_id = pin)
                    and b.status <> '취소' and b.wedding_date = wd)) then
      return jsonb_build_object('ok', false, 'reason', 'pin_taken', 'name', pin_name);
    end if;
    wish := null;   -- 지정을 고르면 우선순위는 비운다 (대표 «자동으로 빠진다»)
  end if;

  /* ④ 값 — 지정 줄은 **서버가 다시 만든다.** 손님이 보낸 금액은 안 믿는다 */
  li := coalesce(payload->'line_items', '[]'::jsonb);
  li := coalesce((select jsonb_agg(x) from jsonb_array_elements(li) x
                   where x->>'name' not like '작가 지정%'), '[]'::jsonb);
  if pin is not null then
    li := li || jsonb_build_array(jsonb_build_object(
      'group', '옵션', 'name', '작가 지정 · ' || pin_name, 'price', pin_fee / 10000));
  end if;
  tot := coalesce(
    (select sum((it->>'price')::int) from jsonb_array_elements(li) it),
    nullif(payload->>'total_price','')::int);

  insert into public.bookings (
    agree_available, agree_terms,
    contractor_name, contractor_phone, contractor_email,
    wedding_date, wedding_time, wedding_venue,
    groom_name, groom_phone, bride_name, bride_phone,
    package, travel_fee,
    option_album, option_reception, option_pyebaek, option_part2,
    photographer, rep_designation, photo_usage_agree, total_price, line_items, custom_options,
    pick_wish, pick_pin, pick_fee_won
  ) values (
    coalesce((payload->>'agree_available')::boolean, false),
    coalesce((payload->>'agree_terms')::boolean, false),
    nullif(payload->>'contractor_name',''), nullif(payload->>'contractor_phone',''), nullif(payload->>'contractor_email',''),
    wd, nullif(payload->>'wedding_time',''), nullif(payload->>'wedding_venue',''),
    nullif(payload->>'groom_name',''), nullif(payload->>'groom_phone',''), nullif(payload->>'bride_name',''), nullif(payload->>'bride_phone',''),
    case when coalesce((payload->>'basic')::boolean, true) then '베이직(데이터형)' else null end,
    coalesce((payload->>'travel_fee')::boolean, false),
    coalesce((payload->>'option_album')::boolean, false),
    coalesce((payload->>'option_reception')::boolean, false),
    coalesce((payload->>'option_pyebaek')::boolean, false),
    coalesce((payload->>'option_part2')::boolean, false),
    coalesce(nullif(payload->>'photographer',''), '기본'),
    coalesce((payload->>'rep_designation')::boolean, false),
    coalesce((payload->>'photo_usage_agree')::boolean, false),
    tot,
    case when jsonb_array_length(li) > 0 then li else null end,
    coalesce(payload->'custom_options', '[]'::jsonb),
    wish, pin, pin_fee
  ) returning id into new_id;

  perform private.otb_push('🔔 신규 예약',
    coalesce(nullif(payload->>'contractor_name',''),'')
    || coalesce(' · ' || nullif(payload->>'wedding_date',''), '')
    || coalesce(' · ' || nullif(payload->>'wedding_venue',''), '')
    -- 대표가 배정하실 때 알아야 할 것이라 알림에도 적는다
    || case when pin is not null then E'\n📌 작가 지정 — ' || pin_name
            when wish is not null and cardinality(wish) > 0 then
              E'\n📋 우선순위 — ' || (select string_agg(s.name, ' · ' order by u.o)
                                      from unnest(wish) with ordinality u(w, o)
                                      join public.staff s on s.id = u.w)
            else '' end
    || case when coalesce((payload->>'force')::boolean, false) then E'\n(같은 번호·같은 예식일로 이미 있는데 그래도 넣으신 것)' else '' end,
    '/admin');
  return jsonb_build_object('ok', true, 'id', new_id);
end;
$fn$;
revoke all on function public.submit_booking_v2(jsonb) from public;
grant execute on function public.submit_booking_v2(jsonb) to anon, authenticated;
