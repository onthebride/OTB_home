-- 배정할 때 안 되는 작가를 표시하기 위한 조회.
-- 기간 안의 예식마다, '문제가 있는 작가만' 골라서 돌려준다(문제 없으면 목록에 없음).
--   off   : 작가가 그날을 촬영 불가로 찍음
--   tight : 같은 날 다른 일정과 4시간 안에 붙음 (우리 예식 + 작가 본인이 적은 다른 촬영)
-- 자기 자신(그 예식)은 비교 대상에서 뺀다. 안 그러면 이미 배정된 작가가 늘 겹침으로 나온다.
create or replace function public.admin_assign_conflicts(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad range'; end if;

  select coalesce(jsonb_object_agg(bid, staff), '{}'::jsonb) into res
  from (
    select b.id::text as bid,
           coalesce(jsonb_object_agg(x.sid, jsonb_build_object('s', x.st, 'd', x.detail))
                    filter (where x.st is not null), '{}'::jsonb) as staff
    from public.bookings b
    cross join lateral (
      select s.id::text as sid,
        case
          when exists (select 1 from public.staff_busy sb
                        where sb.staff_id = s.id and sb.the_date = b.wedding_date and sb.kind = 'off')
            then 'off'
          when exists (select 1 from public.bookings o
                        where o.id <> b.id and o.status <> '취소' and o.wedding_date = b.wedding_date
                          and (o.assignee_id = s.id or o.sub_assignee_id = s.id)
                          and private.too_close(o.wedding_time, b.wedding_time))
            then 'tight'
          when exists (select 1 from public.staff_busy sb
                        where sb.staff_id = s.id and sb.the_date = b.wedding_date and sb.kind = 'busy'
                          and private.too_close(sb.at_time, b.wedding_time))
            then 'tight'
        end as st,
        (select string_agg(z.txt, ' / ' order by z.txt) from (
            select coalesce(public.fmt_ktime(o.wedding_time), '시간미정')
                   || coalesce(' ' || nullif(o.wedding_venue, ''), '') as txt
            from public.bookings o
            where o.id <> b.id and o.status <> '취소' and o.wedding_date = b.wedding_date
              and (o.assignee_id = s.id or o.sub_assignee_id = s.id)
              and private.too_close(o.wedding_time, b.wedding_time)
            union all
            select coalesce(public.fmt_ktime(sb.at_time), '')
                   || coalesce(' ' || nullif(sb.place, ''), '') || ' (작가 등록)'
            from public.staff_busy sb
            where sb.staff_id = s.id and sb.the_date = b.wedding_date and sb.kind = 'busy'
              and private.too_close(sb.at_time, b.wedding_time)
          ) z) as detail
      from public.staff s
      where s.active
    ) x
    where b.wedding_date between p_from and p_to and b.status <> '취소'
    group by b.id
  ) t;
  return res;
end$fn$;
revoke all on function public.admin_assign_conflicts(date, date) from public, anon;
grant execute on function public.admin_assign_conflicts(date, date) to authenticated;
