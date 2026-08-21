-- 날짜만 넣고 조회하면 '가능' 이라고 잘못 말하던 것을 고친다. (대표 지적)
--
-- 무슨 일이 있었나
--   김병훈 작가가 8/27 에 오전 11시·오후 3시 다른 촬영을 등록해 뒀는데,
--   날짜만 넣고 조회하니 「가능」 으로 나왔다. 아래 줄에는 그 두 건이 그대로 적혀 있는데도.
--
-- 왜
--   겹치는지 보는 private.too_close 는 '시간을 모르면 판단하지 않는다'(false) 로 되어 있다.
--   조회할 때 시간을 안 넣으면 비교 대상이 없으니 전부 통과해 버렸다.
--
-- 어떻게
--   시간을 안 넣었으면 '몇 시에 겹치는지' 는 알 수 없지만 '그날 일정이 있다' 는 안다.
--   그러면 '가능' 이라고 하면 안 된다. 걸리는 것으로 본다.
--   시간을 넣으면 지금처럼 4시간 규칙으로 정확히 본다.

create or replace function public.admin_staff_availability(p_date date, p_time text default null)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
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
                       and (t is null or sb.all_day or private.too_close(sb.at_time, t))) then 'tight'
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
end$fn$;
revoke all on function public.admin_staff_availability(date, text) from public, anon;
grant execute on function public.admin_staff_availability(date, text) to authenticated;
