/* 대표를 「작가 우선순위」에서 뺀다 (대표 2026-09-17 «그래 우선순위에사 나는 빼자»)

   왜 — 대표 「무료로하면 다 특정작가만 123지망 하면 뭔가 느낌이 쎄한데」.
     앞으로 오는 예식 115건 중 대표님이 49건(43%)을 이미 맡고 계신다.
     무료 1순위까지 받으면 더 쏠린다.
   그리고 홈 글이 이미 그렇게 말한다 — «대표 지정의 차이는 확정에 있습니다 /
     추가금은 제가 카메라를 드는 값이 아니라 그 시간과 일정을 확정하는 값입니다».
     대표님을 원하시면 지정으로 확정하시는 것, 그게 원래 쓰신 이야기다.

   ⚠ **지정(can_pin)에서는 안 뺀다.** 대표님은 지정 목록에 35만원으로 그대로 계신다.
   ⚠ 아무것도 안 고르신 손님께는 그대로 랜덤 배정된다 — 대표님이 촬영하실 일이 없어지는 게 아니다.
   ⚠ 앞단만 막으면 안 된다. 예약 폼은 로그인 전이라 payload 를 누구든 꾸며 보낼 수 있다 —
     submit_booking_v2 에서도 거른다. 조용히 걸러낸다(약속이 아니라 희망이라).

   ⚠ 대표가 유료화(3만원·환불)는 «한 달 숫자를 보고» 로 미루셨다. 셈하는 길은 안 만들었다.

   이 파일은 살아 있는 정의를 읽어와 세 군데만 갈아 끼운 것이다 (_norepwish_patch.mjs). */
CREATE OR REPLACE FUNCTION public.pick_staff_list(p_wedding_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
  with r as (select private.pick_rules() j),
  base as (
    select s.id, s.name,
      case when s.pick_fee is null then (select (j->>'pin_default')::int from r)
           else s.pick_fee end as fee,
      s.pick_fee as own_fee,
      coalesce(s.is_rep, false) as is_rep,
      (select round(avg(private.fb_score(f.*)), 1) from public.feedback f where f.staff_id = s.id) as score,
      (select count(*)::int from public.feedback f where f.staff_id = s.id) as n,
      /* 우리와 찍은 횟수 — private.pick_eligible 의 n_shot 과 같은 셈이다 */
      ((select count(*) from public.bookings b
         where b.assignee_id = s.id and b.status <> '취소'
           and b.wedding_date < (now() at time zone 'Asia/Seoul')::date)
     + (select count(*) from public.staff_history h
         where h.staff_id = s.id and not coalesce(h.as_sub, false)))::int as took,
      coalesce((select jsonb_agg(g.image_url order by g.sort, g.id)
                  from (select image_url, sort, id from public.gallery
                         where staff_id = s.id and image_url is not null
                         order by sort, id limit 10) g), '[]'::jsonb) as shots,
      /* 그날 되나 — admin_staff_availability 와 같은 규칙.
         날짜를 안 주면 아무도 안 뺀다 (아직 안 고르신 것이다) */
      (p_wedding_date is null
       or not exists (select 1 from public.staff_busy sb
                       where sb.staff_id = s.id and sb.the_date = p_wedding_date)
      and not exists (select 1 from public.bookings b
                       where (b.assignee_id = s.id or b.sub_assignee_id = s.id)
                         and b.status <> '취소' and b.wedding_date = p_wedding_date)
      ) as free_that_day
    from public.staff s
    where coalesce(s.active, false)
      and coalesce(s.can_main, true)          -- 서브 전용은 안 나온다 (대표 «서브는 빼고»)
      and coalesce(s.accepting, true)          -- 쉬는 중인 분도 안 나온다
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'name', name,
      'fee', fee,
      -- 지정을 고를 수 있나. 0 으로 두신 분은 아예 못 고른다
      'can_pin', (coalesce(own_fee, 1) <> 0) and free_that_day,
      /* 우선순위로 고를 수 있나 — 대표는 빠진다 (대표 2026-09-17 «우선순위에사 나는 빼자»).
         앞으로 오는 예식의 43%를 이미 맡고 계셔서 무료 1순위까지 받으면 더 쏠린다.
         그리고 홈 글이 «대표 지정의 차이는 확정에 있습니다» 라고 말한다 —
         대표님을 원하시면 지정으로 확정하시는 것이 원래 이야기다.
         ⚠ 지정(can_pin)에서는 안 뺀다. 아무것도 안 고르신 손님께는 그대로 랜덤 배정된다 */
      'can_wish', not is_rep,
      'score', score, 'n', n,
      'took', took,
      'shots', shots)
    -- ★ 차례는 **섞는다** (대표 2026-09-17 «그냥 랜덤으로 하자»)
    order by random())
    , '[]'::jsonb)
  from base;
$function$
;

grant execute on function public.pick_staff_list(date) to anon, authenticated;

CREATE OR REPLACE FUNCTION public.submit_booking_v2(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
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
                    and coalesce(s.accepting,true)
                    -- 대표는 우선순위로 못 고른다 (대표 2026-09-17 «우선순위에사 나는 빼자»)
                    and not coalesce(s.is_rep,false))
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

  /* 지정은 돈을 받은 약속이라 **바로 그 작가로 배정한다** (대표 2026-09-17
       «지정은 바로 그 작가로 배정되게 해줘»).
     위에서 그날 비어 있는지 이미 확인했다. 배정되면 작가 캘린더에 알림이 남고
     3분 뒤 폰으로도 간다. 대표가 나중에 바꾸시면 배정 이력에 그대로 남는다.
     ⚠ INSERT 에 같이 넣지 않고 따로 UPDATE 하는 까닭 —
       배정 이력 트리거(trg_assignment_audit_upd)가 UPDATE 에만 걸려 있다 */
  if pin is not null then
    update public.bookings set assignee_id = pin where id = new_id;
  end if;

  perform private.otb_push('🔔 신규 예약',
    coalesce(nullif(payload->>'contractor_name',''),'')
    || coalesce(' · ' || nullif(payload->>'wedding_date',''), '')
    || coalesce(' · ' || nullif(payload->>'wedding_venue',''), '')
    -- 대표가 배정하실 때 알아야 할 것이라 알림에도 적는다
    || case when pin is not null then E'\n📌 작가 지정 — ' || pin_name || ' (바로 배정했습니다)'
            when wish is not null and cardinality(wish) > 0 then
              E'\n📋 우선순위 — ' || (select string_agg(s.name, ' · ' order by u.o)
                                      from unnest(wish) with ordinality u(w, o)
                                      join public.staff s on s.id = u.w)
            else '' end
    || case when coalesce((payload->>'force')::boolean, false) then E'\n(같은 번호·같은 예식일로 이미 있는데 그래도 넣으신 것)' else '' end,
    '/admin');
  return jsonb_build_object('ok', true, 'id', new_id);
end;
$function$
;

grant execute on function public.submit_booking_v2(jsonb) to anon, authenticated;
