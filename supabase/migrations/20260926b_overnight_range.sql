/* 밤을 넘기는 일정은 다음날 반복되면 안 된다
   (대표 2026-09-26 «하나의 행사가 시간을 넘기면서 오후 8시 부터 2시까지 인데
                      이게 다음날 반복되서 등되면 안되는거지»)

   ── 무슨 일이 있었나
   대표가 27일 밤 8시 ~ 28일 새벽 2시짜리 행사 하나를
     언제까지 = 10/28 · 시작 20:00 · 종료 02:00
   으로 넣으셨다. 그런데 「언제까지」 는 **같은 일정을 며칠간 반복하나** 라서
   27일 밤과 28일 밤, **두 밤**이 들어갔다.
     10/27  20:00 ~ 28일 02:00
     10/28  20:00 ~ 29일 02:00
   알림도 네 통 나가고, 28일 저녁 7시 예식까지 막혔다.

   ── 왜 대표 읽기가 맞나
   「언제까지」 라고 적혀 있고, 카드에도 「10/27~10/28 (2일)」 이라고 뜬다.
   밤을 넘기는 일정에서 그 둘을 나란히 보면 **한 행사의 끝 날짜**로 읽힌다.
   내가 어제 밤 넘기기를 붙이면서 이 칸의 뜻을 안 맞춰 둔 것이다.

   ── 이렇게 고친다
   밤을 넘기는 일정이면 「언제까지」 는 **마지막 새벽이 끝나는 날**로 읽는다.
   마지막 밤은 그 하루 전에 시작한다.
     27 ~ 28 (밤 넘김) → 27일 밤 하나          ← 대표가 원하신 것
     27 ~ 29 (밤 넘김) → 27일·28일 밤 둘        ← 여러 밤도 그대로 된다
     27 ~ 27 (밤 넘김) → 27일 밤 하나
     27 ~ 28 (밤 안 넘김) → 27일·28일 이틀      ← 예전 그대로
   ⚠ 밤을 안 넘기는 일정은 **한 줄도 안 바뀐다.** 지금 있는 자료가 전부 그쪽이다. */


CREATE OR REPLACE FUNCTION public.staff_busy_add_range(p_staff_id uuid, p_from date, p_to date, p_title text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_time text DEFAULT NULL::text, p_place text DEFAULT NULL::text, p_all_day boolean DEFAULT true, p_kind text DEFAULT 'personal'::text, p_end text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare d date; last_d date; n int := 0; gid uuid := gen_random_uuid(); skipped jsonb := '[]'::jsonb; k text; e text;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and active) then raise exception 'staff not found'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception '날짜 범위가 올바르지 않습니다'; end if;
  if p_to - p_from > 60 then raise exception '한 번에 60일까지만 됩니다'; end if;

  k := case when p_kind = 'busy' then 'busy' else 'personal' end;
  if k = 'busy' and not coalesce(p_all_day, true) and nullif(p_time, '') is null then
    raise exception '다른 촬영은 시간을 알려주셔야 해요 (하루 종일이면 종일로 해주세요)';
  end if;
  e := private.busy_end_ok(p_time, p_end, p_all_day);
  if e = '' then raise exception '끝나는 시각을 시작과 다르게 골라 주세요 (밤을 넘기면 다음날로 봅니다)'; end if;

  /* ⚠⚠ 밤을 넘기는 일정(끝이 시작보다 이른)이면 「언제까지」 는
       **마지막 새벽이 끝나는 날**이다. 마지막 밤은 그 하루 전에 시작한다.
       대표가 27일 밤 8시 ~ 28일 새벽 2시를 27~28 로 넣으셨더니
       27일 밤과 28일 밤, 두 밤이 들어갔다 (대표 «다음날 반복되서 등되면 안되는거지»).
         27 ~ 28 (밤 넘김) → 27일 밤 하나
         27 ~ 29 (밤 넘김) → 27일·28일 밤 둘 (29일 새벽에 끝난다)
         27 ~ 27 (밤 넘김) → 27일 밤 하나 — 하루만 고르신 것이니 빼지 않는다
       ⚠ 밤을 안 넘기면 예전 그대로다. e 는 busy_end_ok 를 거친 값이라
         종일이면 null 이 되어 이 갈래로 안 온다 */
  last_d := case when e is not null and nullif(p_time, '') is not null
                  and e::time < p_time::time and p_to > p_from
                 then p_to - 1 else p_to end;

  d := p_from;
  while d <= last_d loop
    if d < current_date - 1 then
      skipped := skipped || jsonb_build_object('d', d, 'why', '지난 날짜');
    elsif exists (select 1 from public.bookings b
                   where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
                     and b.status <> '취소' and b.wedding_date = d) then
      skipped := skipped || jsonb_build_object('d', d, 'why', '배정된 예식');
    else
      delete from public.staff_busy where staff_id = p_staff_id and the_date = d and kind = 'off';
      insert into public.staff_busy (staff_id, the_date, kind, at_time, end_time, place, note, title, all_day, group_id)
      values (p_staff_id, d, k,
              case when coalesce(p_all_day, true) then null else p_time end,
              e, nullif(p_place, ''), nullif(p_note, ''), nullif(p_title, ''),
              coalesce(p_all_day, true), gid);
      n := n + 1;
    end if;
    d := d + 1;
  end loop;

  return jsonb_build_object('ok', n > 0, 'n', n, 'group', gid, 'skipped', skipped, 'kind', k);
end$function$
;
