-- 개인 일정을 여러 날에 걸쳐 넣을 수 있게. (대표 요청)
--   "휴가 8/25~8/28" 처럼 한 번에 넣고, 고칠 때도 지울 때도 한 번에.
--
-- 어떻게 담나
--   날짜마다 한 줄씩 넣는다. 그래야 겹침 판정·달력·날짜 조회가 지금 그대로 돌아간다.
--   (범위를 한 줄에 담으면 그 셋을 전부 뜯어고쳐야 하고, 조용히 어긋날 자리가 늘어난다)
--   대신 같은 묶음에 group_id 를 달아, 작가 화면에서는 한 덩어리로 다룬다.
--
-- 범위 안에 배정된 예식이 있으면 그 날만 건너뛰고 알려준다 — 통째로 실패시키지 않는다.

alter table public.staff_busy add column if not exists group_id uuid;
create index if not exists staff_busy_group_idx on public.staff_busy (group_id) where group_id is not null;

-- ── 여러 날 개인 일정 ─────────────────────────────────────────
create or replace function public.staff_busy_add_range(
  p_staff_id uuid, p_from date, p_to date,
  p_title text default null, p_note text default null,
  p_time text default null, p_place text default null, p_all_day boolean default true)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare d date; gid uuid := gen_random_uuid(); n int := 0; skipped jsonb := '[]'::jsonb;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and active) then raise exception 'staff not found'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception '날짜 범위가 올바르지 않습니다'; end if;
  if p_to - p_from > 60 then raise exception '한 번에 60일까지만 됩니다'; end if;

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
      values (p_staff_id, d, 'personal',
              case when coalesce(p_all_day, true) then null else p_time end,
              nullif(p_place, ''), nullif(p_note, ''), nullif(p_title, ''),
              coalesce(p_all_day, true), gid);
      n := n + 1;
    end if;
    d := d + 1;
  end loop;

  return jsonb_build_object('ok', n > 0, 'n', n, 'group', gid, 'skipped', skipped);
end$fn$;
revoke all on function public.staff_busy_add_range(uuid, date, date, text, text, text, text, boolean) from public;
grant execute on function public.staff_busy_add_range(uuid, date, date, text, text, text, text, boolean) to anon, authenticated;

-- ── 묶음 통째로 고치기 ────────────────────────────────────────
-- 내용만 바꾼다. 날짜 범위를 바꾸려면 지우고 다시 넣는 게 헷갈리지 않는다.
create or replace function public.staff_busy_upd_group(
  p_staff_id uuid, p_group uuid,
  p_title text default null, p_note text default null,
  p_time text default null, p_place text default null, p_all_day boolean default true)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare n int;
begin
  if p_group is null then raise exception '내 일정이 아닙니다'; end if;
  update public.staff_busy
     set title   = nullif(p_title, ''),
         note    = nullif(p_note, ''),
         place   = nullif(p_place, ''),
         at_time = case when coalesce(p_all_day, true) then null else p_time end,
         all_day = coalesce(p_all_day, true)
   where group_id = p_group and staff_id = p_staff_id;   -- 본인 것만
  get diagnostics n = row_count;
  if n = 0 then raise exception '내 일정이 아닙니다'; end if;
  return jsonb_build_object('ok', true, 'n', n);
end$fn$;
revoke all on function public.staff_busy_upd_group(uuid, uuid, text, text, text, text, boolean) from public;
grant execute on function public.staff_busy_upd_group(uuid, uuid, text, text, text, text, boolean) to anon, authenticated;

-- ── 묶음 통째로 지우기 ────────────────────────────────────────
create or replace function public.staff_busy_del_group(p_staff_id uuid, p_group uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare n int;
begin
  if p_group is null then raise exception '내 일정이 아닙니다'; end if;
  delete from public.staff_busy where group_id = p_group and staff_id = p_staff_id;   -- 본인 것만
  get diagnostics n = row_count;
  return jsonb_build_object('ok', n > 0, 'n', n);
end$fn$;
revoke all on function public.staff_busy_del_group(uuid, uuid) from public;
grant execute on function public.staff_busy_del_group(uuid, uuid) to anon, authenticated;

-- ── 작가 화면에 묶음 정보도 함께 ──────────────────────────────
-- 며칠짜리인지 알아야 "휴가 8/25~8/28" 이라고 보여줄 수 있다.
create or replace function public.staff_calendar(p_staff_id uuid, p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare st public.staff; res jsonb;
begin
  select * into st from public.staff where id = p_staff_id;
  if not found then return null; end if;
  if p_to < p_from or p_to > p_from + 400 then raise exception 'bad range'; end if;

  select jsonb_build_object(
    'staff_name', st.name,
    'from', p_from, 'to', p_to,
    'bookings', coalesce((select jsonb_agg(x order by x->>'wedding_date', x->>'wedding_time') from (
        select jsonb_build_object(
          'booking_id', b.id, 'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time,
          'wedding_venue', b.wedding_venue,
          'role', case when b.assignee_id = p_staff_id then '메인' else '서브' end,
          'bride_name', b.bride_name, 'groom_name', b.groom_name,
          'bride_phone', case when b.wedding_date <= current_date + 14 then b.bride_phone end,
          'groom_phone', case when b.wedding_date <= current_date + 14 then b.groom_phone end,
          'option_reception', b.option_reception, 'option_pyebaek', b.option_pyebaek,
          'option_part2', b.option_part2, 'photographer', b.photographer, 'rep_designation', b.rep_designation
        ) as x
        from public.bookings b
        where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
          and b.status <> '취소' and b.wedding_date between p_from and p_to) t), '[]'::jsonb),
    'busy', coalesce((select jsonb_agg(jsonb_build_object(
          'id', sb.id, 'the_date', sb.the_date, 'kind', sb.kind,
          'at_time', sb.at_time, 'place', sb.place, 'note', sb.note,
          'title', sb.title, 'all_day', sb.all_day, 'group_id', sb.group_id,
          -- 묶음이면 전체가 언제부터 언제까지인지 (달력 범위 밖까지 포함해서 센다)
          'g_from', g.g_from, 'g_to', g.g_to, 'g_n', g.g_n)
          order by sb.the_date, sb.all_day desc, sb.at_time)
        from public.staff_busy sb
        left join lateral (
          select min(o.the_date) g_from, max(o.the_date) g_to, count(*)::int g_n
          from public.staff_busy o
          where o.group_id = sb.group_id and o.staff_id = sb.staff_id
        ) g on sb.group_id is not null
        where sb.staff_id = p_staff_id and sb.the_date between p_from and p_to), '[]'::jsonb)
  ) into res;
  return res;
end$fn$;
revoke all on function public.staff_calendar(uuid, date, date) from public;
grant execute on function public.staff_calendar(uuid, date, date) to anon, authenticated;
