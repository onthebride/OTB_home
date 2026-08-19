-- 배정된 예식이 있는 날은 작가가 스스로 '촬영 불가'로 바꿀 수 없다.
-- 대표 지시: "우리 스케줄이 있을때 불가 처리는 안되게 해줘 무조건 나한테 허락받고 내가 빼는걸로"
-- 다른 촬영(busy)은 그대로 등록할 수 있다. 4시간 규칙으로 판단하면 되기 때문.
create or replace function public.staff_busy_add(p_staff_id uuid, p_date date, p_kind text,
                                                 p_time text default null, p_place text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare newid bigint;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and active) then raise exception 'staff not found'; end if;
  if p_kind not in ('off', 'busy') then raise exception 'bad kind'; end if;
  if p_date < current_date - 1 then raise exception '지난 날짜는 등록할 수 없습니다'; end if;
  if p_kind = 'busy' and (p_time is null or p_time !~ '^[0-2][0-9]:[0-5][0-9]$') then
    raise exception '시간을 HH:MM 형식으로 입력해 주세요';
  end if;

  if p_kind = 'off' then
    if exists (select 1 from public.bookings b
                where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
                  and b.status <> '취소' and b.wedding_date = p_date) then
      raise exception '배정된 예식이 있는 날입니다. 대표에게 연락해 주세요';
    end if;
    -- 하루 전체 불가면 그날 다른 일정 기록은 의미가 없으니 정리
    delete from public.staff_busy where staff_id = p_staff_id and the_date = p_date;
    insert into public.staff_busy (staff_id, the_date, kind, note) values (p_staff_id, p_date, 'off', nullif(p_note,''))
    returning id into newid;
  else
    delete from public.staff_busy where staff_id = p_staff_id and the_date = p_date and kind = 'off';
    insert into public.staff_busy (staff_id, the_date, kind, at_time, place, note)
    values (p_staff_id, p_date, 'busy', p_time, nullif(p_place,''), nullif(p_note,''))
    returning id into newid;
  end if;
  return jsonb_build_object('ok', true, 'id', newid);
end$fn$;
revoke all on function public.staff_busy_add(uuid, date, text, text, text, text) from public;
grant execute on function public.staff_busy_add(uuid, date, text, text, text, text) to anon, authenticated;
