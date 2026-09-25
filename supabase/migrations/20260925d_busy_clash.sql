/* 겹침을 볼 때 **끝 시각까지** 본다 (대표 2026-09-25 «시작시간 종료시간도 넣는게 좋겠는데?»)

   `sb.all_day or too_close(sb.at_time, w)` 를 `private.busy_clash(sb, w)` 하나로 바꾼다.
   ⚠⚠ 끝 시각이 없는 옛 자료는 **하나도 안 바뀐다** — busy_clash 가 그때는 too_close 로 떨어진다.
   ⚠ 자리가 둘이다. 한쪽만 고치면 한 화면만 달라진다 — 둘 다 고친다.
   ⚠ 이 파일은 살아 있는 정의를 읽어와 갈아 끼운 것이다 (_busyclash_patch.mjs). */
CREATE OR REPLACE FUNCTION public.admin_assign_conflicts(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
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
                          and (private.busy_clash(sb, b.wedding_time)))
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
                   or (sb.kind = 'busy' and (private.busy_clash(sb, b.wedding_time))))
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
end$function$
;

CREATE OR REPLACE FUNCTION public.admin_staff_availability(p_date date, p_time text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare res jsonb; t text := nullif(btrim(coalesce(p_time, '')), '');
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(t2 order by (t2.status <> 'ok'), t2.name), '[]'::jsonb) into res from (
    select s.id, s.name,
      case
        -- 촬영불가·개인일정은 시간과 무관하게 그날을 막는다
        when exists(select 1 from public.staff_busy sb
                     where sb.staff_id = s.id and sb.the_date = p_date
                       and sb.kind in ('off', 'personal')) then 'off'
        -- 다른 촬영: 시간을 알면 4시간 규칙, 모르면 '그날 뭔가 있다' 로 본다
        when exists(select 1 from public.staff_busy sb
                     where sb.staff_id = s.id and sb.the_date = p_date and sb.kind = 'busy'
                       and (t is null or private.busy_clash(sb, t))) then 'tight'
        -- 우리 예식도 마찬가지
        when exists(select 1 from public.bookings b
                     where (b.assignee_id = s.id or b.sub_assignee_id = s.id)
                       and b.status <> '취소' and b.wedding_date = p_date
                       and (t is null or private.too_close(b.wedding_time, t))) then 'tight'
        else 'ok' end as status,
      coalesce((select string_agg(x, ' / ' order by x) from (
          select coalesce(public.fmt_ktime(b.wedding_time), '시간미정') || ' ' || coalesce(b.wedding_venue,'') as x
          from public.bookings b
          where (b.assignee_id = s.id or b.sub_assignee_id = s.id)
            and b.status <> '취소' and b.wedding_date = p_date
          union all
          select private.busy_label(sb, ' (본인 등록)')
          from public.staff_busy sb where sb.staff_id = s.id and sb.the_date = p_date) u), '') as detail
    from public.staff s where s.active
  ) t2;
  return res;
end$function$
;
