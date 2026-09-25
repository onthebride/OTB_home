/* 「다른 촬영」도 여러 날 한 번에 (대표 2026-09-25
     «지금 개인 일정은 여러날 선택할 수 있는 거를 다른촬영등록에서 설정할 수 있게해줘»)

   여러 날 등록은 **개인 일정에만** 있었다. staff_busy_add_range 가 kind 를
   'personal' 로 박아 넣고 있어서다. 다른 촬영이 이틀·사흘 이어지는 일은 흔한데
   그때마다 하루씩 따로 넣으셔야 했다.

   ⚠ 칸을 **맨 뒤에** 더한다. 앞에 끼우면 지금 부르는 자리가 조용히 어긋난다.
   ⚠ 칸을 더할 때는 drop function 을 같이 쓴다 (CLAUDE.md).
   ⚠ 'off'(하루 불가)는 안 받는다 — 그건 여러 날 찍는 다른 길(staff_busy_add_many)이 있다.
   ⚠ 다른 촬영은 **시간이 있어야 한다.** 시간을 알아야 우리 예식과 겹치는지 본다 —
     종일이 아니면 시간을 반드시 받는다. 그 검사는 앞단에도 있지만 여기서도 막는다. */

drop function if exists public.staff_busy_add_range(uuid, date, date, text, text, text, text, boolean);

create or replace function public.staff_busy_add_range(
  p_staff_id uuid, p_from date, p_to date,
  p_title text default null, p_note text default null,
  p_time text default null, p_place text default null,
  p_all_day boolean default true,
  p_kind text default 'personal')
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $fn$
declare d date; n int := 0; gid uuid := gen_random_uuid(); skipped jsonb := '[]'::jsonb; k text;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and active) then raise exception 'staff not found'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception '날짜 범위가 올바르지 않습니다'; end if;
  if p_to - p_from > 60 then raise exception '한 번에 60일까지만 됩니다'; end if;

  /* 개인 일정과 다른 촬영 둘만 받는다 (2026-09-25).
     ⚠ 모르는 값이 오면 예전처럼 개인 일정으로 둔다 — 조용히 엉뚱한 자리에 넣지 않는다 */
  k := case when p_kind = 'busy' then 'busy' else 'personal' end;
  if k = 'busy' and not coalesce(p_all_day, true) and nullif(p_time, '') is null then
    raise exception '다른 촬영은 시간을 알려주셔야 해요 (하루 종일이면 종일로 해주세요)';
  end if;

  d := p_from;
  while d <= p_to loop
    if d < current_date - 1 then
      skipped := skipped || jsonb_build_object('d', d, 'why', '지난 날짜');
    elsif exists (select 1 from public.bookings b
                   where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
                     and b.status <> '취소' and b.wedding_date = d) then
      skipped := skipped || jsonb_build_object('d', d, 'why', '배정된 예식');
    else
      delete from public.staff_busy where staff_id = p_staff_id and the_date = d and kind = 'off';
      insert into public.staff_busy (staff_id, the_date, kind, at_time, place, note, title, all_day, group_id)
      values (p_staff_id, d, k,
              case when coalesce(p_all_day, true) then null else p_time end,
              nullif(p_place, ''), nullif(p_note, ''), nullif(p_title, ''),
              coalesce(p_all_day, true), gid);
      n := n + 1;
    end if;
    d := d + 1;
  end loop;

  return jsonb_build_object('ok', n > 0, 'n', n, 'group', gid, 'skipped', skipped, 'kind', k);
end$fn$;

grant execute on function public.staff_busy_add_range(uuid, date, date, text, text, text, text, boolean, text)
  to anon, authenticated;
