/* 「그날 1건」에도 시간·장소를 적는다 (대표 2026-09-17
     «여기 그날 1건 있는거 장소랑 시간은 알 수 있음 하는데
       그래야 배정을 할수 있을지 없을지 알거 같아»)

   무슨 일이었나 — detail 은 **겹치는 것만** 모았다(too_close 인 것).
   그래서 겹침(tight)·불가(off)에는 「오전 11:50 더메뉴지서울」이 붙었지만,
   겹치진 않는 같은 날 일정(same)은 detail 이 늘 null 이라 「그날 1건」 넉 자로 끝났다.
   그 넉 자로는 배정을 할지 말지 정할 수가 없다.

   그래서 그날 걸린 것을 **전부** 모은 칸(sd)을 따로 하나 더 낸다.
     d  — 왜 막혔나 (겹치는 것만) · 지금까지와 똑같다
     sd — 그날 뭐가 있나 (겹치든 안 겹치든 전부) · s='same' 일 때만 싣는다

   ⚠ d 를 건드리지 않는 이유 — 겹침 줄에 안 겹치는 것까지 섞어 적으면
     16자에서 잘리며 **진짜 겹치는 것이 가려질 수 있다.**
   ⚠ 차례는 시각으로 세운다. 글자로 세우면 「오전 11:50」이 「오전 9:00」 앞에 온다. */

create or replace function public.admin_assign_conflicts(p_from date, p_to date)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad range'; end if;

  select coalesce(jsonb_object_agg(bid, staff), '{}'::jsonb) into res
  from (
    select b.id::text as bid,
           -- ⚠ 있던 칸(s·d·n)은 모양 그대로 둔다. sd 만 새로 더한다
           coalesce(jsonb_object_agg(x.sid, jsonb_build_object(
                      's', x.st, 'd', x.detail, 'n', x.n,
                      -- 겹치진 않지만 그날 뭔가 있는 자리에만 싣는다 (표를 쓸데없이 불리지 않는다)
                      'sd', case when x.st = 'same' then x.sameday end))
                    filter (where x.st is not null), '{}'::jsonb) as staff
    from public.bookings b
    cross join lateral (
      select s.id::text as sid,
        -- 그날 그 작가에게 걸린 것이 몇 건인가 (이 예식은 뺀다)
        (select count(*)::int from public.bookings o
          where o.id <> b.id and o.status <> '취소' and o.wedding_date = b.wedding_date
            and (o.assignee_id = s.id or o.sub_assignee_id = s.id))
        + (select count(*)::int from public.staff_busy sb
          where sb.staff_id = s.id and sb.the_date = b.wedding_date) as n,
        case
          -- 촬영불가·개인일정은 그날을 막는다
          when exists (select 1 from public.staff_busy sb
                        where sb.staff_id = s.id and sb.the_date = b.wedding_date
                          and sb.kind in ('off', 'personal'))
            then 'off'
          when exists (select 1 from public.bookings o
                        where o.id <> b.id and o.status <> '취소' and o.wedding_date = b.wedding_date
                          and (o.assignee_id = s.id or o.sub_assignee_id = s.id)
                          and private.too_close(o.wedding_time, b.wedding_time))
            then 'tight'
          when exists (select 1 from public.staff_busy sb
                        where sb.staff_id = s.id and sb.the_date = b.wedding_date and sb.kind = 'busy'
                          -- 종일 촬영은 시간을 따질 수 없으니 그날은 걸린 것으로 본다
                          and (sb.all_day or private.too_close(sb.at_time, b.wedding_time)))
            then 'tight'
          -- 겹치진 않지만 그날 뭔가 있다
          when exists (select 1 from public.bookings o
                        where o.id <> b.id and o.status <> '취소' and o.wedding_date = b.wedding_date
                          and (o.assignee_id = s.id or o.sub_assignee_id = s.id))
            or exists (select 1 from public.staff_busy sb
                        where sb.staff_id = s.id and sb.the_date = b.wedding_date)
            then 'same'
        end as st,
        -- ① 왜 막혔나 — 겹치는 것만 (지금까지와 똑같다)
        (select string_agg(z.txt, ' / ' order by z.txt) from (
            select coalesce(public.fmt_ktime(o.wedding_time), '시간미정')
                   || coalesce(' ' || nullif(o.wedding_venue, ''), '') as txt
            from public.bookings o
            where o.id <> b.id and o.status <> '취소' and o.wedding_date = b.wedding_date
              and (o.assignee_id = s.id or o.sub_assignee_id = s.id)
              and private.too_close(o.wedding_time, b.wedding_time)
            union all
            select private.busy_label(sb, ' (작가 등록)')
            from public.staff_busy sb
            where sb.staff_id = s.id and sb.the_date = b.wedding_date
              and (sb.kind = 'personal'
                   or (sb.kind = 'busy' and (sb.all_day or private.too_close(sb.at_time, b.wedding_time))))
          ) z) as detail,
        -- ② 그날 뭐가 있나 — 겹치든 안 겹치든 전부, 이른 것부터
        (select string_agg(w.txt, ' / ' order by w.tm nulls last, w.txt) from (
            select coalesce(public.fmt_ktime(o.wedding_time), '시간미정')
                   || coalesce(' ' || nullif(o.wedding_venue, ''), '') as txt,
                   o.wedding_time as tm
            from public.bookings o
            where o.id <> b.id and o.status <> '취소' and o.wedding_date = b.wedding_date
              and (o.assignee_id = s.id or o.sub_assignee_id = s.id)
            union all
            select private.busy_label(sb, ' (작가 등록)'), sb.at_time
            from public.staff_busy sb
            where sb.staff_id = s.id and sb.the_date = b.wedding_date
          ) w) as sameday
      from public.staff s
      where s.active
    ) x
    where b.wedding_date between p_from and p_to and b.status <> '취소'
    group by b.id
  ) t;
  return res;
end$function$;
