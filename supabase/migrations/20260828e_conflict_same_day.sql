-- 「겹치진 않지만 그날 다른 일정이 있다」 를 따로 알려준다 (대표 요청 2026-08-28
-- «겹침까지는 아니어도 그날 1건 있음 살짝 넣어줘»)
--
-- 어쩌다 나왔나 — 대표가 10/10 에 이미 촬영이 있는데 다른 예식의 배정 목록에
-- 「배정 가능」 으로 떴다. 원인은 그 예식 시간이 00:00 으로 잘못 들어간 것이었지만,
-- 시간이 맞더라도 4시간을 넘기면 아무 표시가 없다는 점은 그대로다.
--
-- 그래서 상태를 하나 더 둔다.
--   off   그날을 아예 못 한다 (촬영불가·개인일정)      → 막는다
--   tight 4시간 안에 붙는다                          → 막는다
--   same  그날 다른 일정이 있지만 시간은 넉넉하다      → **막지 않는다.** 눈에만 띄게
-- ⚠ 「배정 가능」 에서 빼면 안 된다. 시간이 넉넉하면 진짜로 배정할 수 있는 자리다.
--
-- 몇 건인지도 함께 준다('n') — 화면에 「그날 2건」 처럼 적는다.
-- ⚠ detail(사유 글) 은 손대지 않았다. 겹치는 것만 담는다는 뜻이 그대로여야
--   'tight' 일 때 «무엇 때문에 걸렸는지» 가 흐려지지 않는다.

create or replace function public.admin_assign_conflicts(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad range'; end if;

  select coalesce(jsonb_object_agg(bid, staff), '{}'::jsonb) into res
  from (
    select b.id::text as bid,
           coalesce(jsonb_object_agg(x.sid, jsonb_build_object('s', x.st, 'd', x.detail, 'n', x.n))
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
          -- 여기부터가 새로 생긴 것 — 겹치진 않지만 그날 뭔가 있다
          when exists (select 1 from public.bookings o
                        where o.id <> b.id and o.status <> '취소' and o.wedding_date = b.wedding_date
                          and (o.assignee_id = s.id or o.sub_assignee_id = s.id))
            or exists (select 1 from public.staff_busy sb
                        where sb.staff_id = s.id and sb.the_date = b.wedding_date)
            then 'same'
        end as st,
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
