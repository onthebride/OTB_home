/* 지정이 들어오면 바로 그 작가로 배정한다 (대표 2026-09-17
     «지정은 바로 그 작가로 배정되게 해줘»)

   ⚠⚠ 이것은 **배정을 자동으로 건드리는 코드**다. 원래 규칙은 「배정은 대표가 바꿀 때만」이고
     그래서 먼저 만들지 않고 여쭸다. 대표가 위와 같이 허락하셨다.
     못 하게 되었을 때 빠져나갈 길(admin_cancel_pick)을 같은 판에서 함께 만든다.

   ⚠ 계약금 전에도 배정된다. 지정은 그날 그 작가를 잡아두는 것이 값이라 그게 맞다.
     신청만 하고 안 오시면 대표가 취소하실 때 「배정 해제」가 한 통 더 나간다.

   이 파일은 살아 있는 정의를 읽어와 두 군데만 갈아 끼운 것이다 (_pinassign_patch.mjs). */
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

/* ── 빠져나갈 길 — 「작가 지정 취소」 (대표 2026-09-17
     «만약에 그 작가가 개인적인 일로 캘린더에 표시를 안해서 안된다고하면
       그 옵션을 취소도 할 수 있게 해줘»)

   ⚠ 배정은 건드리지 않는다. 지우는 것은 **돈 받은 옵션**이다.
     작가를 바꾸는 것은 대표가 바로 아래 고르개에서 하실 일이고,
     그래야 배정 이력에 «대표가 바꿨다» 로 남는다.
   ⚠ 총액은 남은 줄에서 다시 센다 — 지정비만 빼면 다른 데서 어긋난 값이 그대로 남는다.
   ⚠ 무슨 일이 있었는지 메모에 한 줄 남긴다. 줄을 지우면 아무 자취가 없다.
   ⚠ line_items 의 price 는 **만원 단위**, pick_fee_won 은 원 단위다 ── */
create or replace function public.admin_cancel_pick(p_id uuid)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $fn$
declare b public.bookings; li jsonb; tot int; fee int; nm text; was uuid; still boolean;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select * into b from public.bookings where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no_booking'); end if;
  if b.pick_pin is null then return jsonb_build_object('ok', false, 'reason', 'no_pick'); end if;

  was := b.pick_pin;                       -- 지우기 전에 붙잡아 둔다
  still := (b.assignee_id = was);          -- 아직 그 작가로 배정돼 있나
  select s.name into nm from public.staff s where s.id = was;
  fee := coalesce(b.pick_fee_won, 0);

  li := coalesce((select jsonb_agg(x) from jsonb_array_elements(coalesce(b.line_items, '[]'::jsonb)) x
                   where x->>'name' not like '작가 지정%'), '[]'::jsonb);
  if b.line_items is not null and jsonb_array_length(b.line_items) > 0 then
    tot := coalesce((select sum((it->>'price')::int) from jsonb_array_elements(li) it), 0);
  else
    -- 줄이 아예 없던 예약이면 지정비만 뺀다 (음수로 내려가지 않게)
    tot := greatest(coalesce(b.total_price, 0) - fee / 10000, 0);
  end if;

  update public.bookings set
    pick_pin = null,
    pick_fee_won = null,
    line_items = case when jsonb_array_length(li) > 0 then li else null end,
    total_price = tot,
    admin_note = coalesce(nullif(admin_note, '') || E'\n', '')
      || to_char(now() at time zone 'Asia/Seoul', 'YYYY-MM-DD')
      || ' 작가 지정 취소 — ' || coalesce(nm, '(알 수 없는 작가)')
      || ' · ' || to_char(fee, 'FM999,999') || '원 뺌'
   where id = p_id
   returning * into b;

  -- 예약 줄을 통째로 돌려준다 — 화면이 들고 있던 것을 그대로 갈아끼우게 (admin_update_booking 과 같은 결)
  return jsonb_build_object('ok', true, 'name', nm, 'fee', fee,
                            'total', tot, 'still_assigned', coalesce(still, false),
                            'b', to_jsonb(b));
end$fn$;

revoke all on function public.admin_cancel_pick(uuid) from public, anon;
grant execute on function public.admin_cancel_pick(uuid) to authenticated, service_role;
