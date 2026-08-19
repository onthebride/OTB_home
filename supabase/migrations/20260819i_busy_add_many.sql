-- 촬영 불가일을 여러 날 한 번에 등록.
-- 대표: "작가들 캘린더 촬영불가 날짜를 다중선택하고 설정하게 해줘"
--
-- 규칙은 한 날짜씩 등록하는 staff_busy_add 와 똑같다(배정된 날은 거부, 지난 날짜 거부).
-- 다만 여러 날을 한꺼번에 받으므로, 하나가 걸린다고 전부 물리면 쓰기 불편하다.
-- 되는 것만 넣고 걸린 날짜는 이유와 함께 돌려준다.
create or replace function public.staff_busy_add_many(p_staff_id uuid, p_dates date[])
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare d date; added int := 0; skipped jsonb := '[]'::jsonb;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and active) then
    raise exception 'staff not found';
  end if;
  if p_dates is null or array_length(p_dates, 1) is null then
    return jsonb_build_object('ok', 0, 'skipped', '[]'::jsonb);
  end if;
  if array_length(p_dates, 1) > 120 then raise exception '한 번에 120일까지만 됩니다'; end if;

  foreach d in array p_dates loop
    if d < current_date - 1 then
      skipped := skipped || jsonb_build_array(jsonb_build_object('d', d, 'why', '지난 날짜'));
      continue;
    end if;
    if exists (select 1 from public.bookings b
                where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
                  and b.status <> '취소' and b.wedding_date = d) then
      skipped := skipped || jsonb_build_array(jsonb_build_object('d', d, 'why', '배정된 예식'));
      continue;
    end if;
    -- 하루 전체 불가면 그날 다른 일정 기록은 의미가 없으니 정리 (staff_busy_add 와 같은 동작)
    delete from public.staff_busy where staff_id = p_staff_id and the_date = d;
    insert into public.staff_busy (staff_id, the_date, kind) values (p_staff_id, d, 'off');
    added := added + 1;
  end loop;

  return jsonb_build_object('ok', added, 'skipped', skipped);
end$fn$;
revoke all on function public.staff_busy_add_many(uuid, date[]) from public;
grant execute on function public.staff_busy_add_many(uuid, date[]) to anon, authenticated;
