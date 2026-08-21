-- 작가 일정을 세 가지로 나눈다. (대표 요청)
--
--   촬영불가      그날 촬영 못 함.               대표: '하루 불가'
--   다른촬영등록  타사 촬영.                     대표: 시간·장소만 (겹치는지 판단해야 하니까)
--   개인일정등록  병원·가족 일 같은 것.          대표: 아무것도 안 보임 + 그날은 촬영불가로 처리
--
-- 어제 넣은 '나만 보기' 체크는 없앤다. 종류가 곧 공개 범위라 체크가 필요 없어졌다.
-- (대표가 '기본으로 켜져 있게' 를 원했는데, 개인일정은 처음부터 안 보이는 게 기본이 됐다)
--
-- 왜 개인일정을 촬영불가로 같이 처리하나
--   대표 판단 — 다른 일정이 있으면 보통 촬영은 어렵다. 그래서 시간을 따지지 않고 그날을 막는다.
--   덕분에 대표는 시간조차 알 필요가 없어져서, 개인일정은 통째로 가릴 수 있다.
--
-- 다른촬영등록에서 메모는 대표에게 안 보인다.
--   그래야 작가가 타사 촬영 메모까지 여기 적는다 — 다른 업체 일도 우리 스케줄러로 관리하게.

alter table public.staff_busy drop constraint if exists staff_busy_kind_check;
alter table public.staff_busy add constraint staff_busy_kind_check
  check (kind in ('off', 'busy', 'personal'));

-- '나만 보기' 는 종류로 대체됐다
alter table public.staff_busy drop column if exists is_private;

-- ── 등록 ──────────────────────────────────────────────────────
create or replace function public.staff_busy_add(
  p_staff_id uuid, p_date date, p_kind text,
  p_time text default null, p_place text default null, p_note text default null,
  p_title text default null, p_all_day boolean default false)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare newid bigint;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and active) then raise exception 'staff not found'; end if;
  if p_kind not in ('off', 'busy', 'personal') then raise exception 'bad kind'; end if;
  if p_date < current_date - 1 then raise exception '지난 날짜는 등록할 수 없습니다'; end if;
  -- 다른 촬영은 시간을 알아야 겹치는지 볼 수 있다. 개인일정은 어차피 그날을 막으니 시간이 없어도 된다.
  if p_kind = 'busy' and not coalesce(p_all_day, false)
     and (p_time is null or p_time !~ '^[0-2][0-9]:[0-5][0-9]$') then
    raise exception '시간을 HH:MM 형식으로 입력해 주세요';
  end if;

  -- 그날을 막는 종류(촬영불가·개인일정)는 이미 배정된 예식이 있으면 안 된다
  if p_kind in ('off', 'personal')
     and exists (select 1 from public.bookings b
                  where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
                    and b.status <> '취소' and b.wedding_date = p_date) then
    raise exception '배정된 예식이 있는 날입니다. 대표에게 연락해 주세요';
  end if;

  if p_kind = 'off' then
    -- 하루 전체 불가면 그날 '다른 촬영' 기록은 의미가 없으니 정리한다.
    -- 이미 찍혀 있는 '촬영불가' 도 지운다 — 안 그러면 두 번 누를 때 하루 하나 규칙에 걸린다.
    -- 개인일정은 남긴다 — 작가가 적어둔 자기 메모라 지워버리면 안 된다.
    delete from public.staff_busy
     where staff_id = p_staff_id and the_date = p_date and kind in ('off', 'busy');
    insert into public.staff_busy (staff_id, the_date, kind, note, all_day)
    values (p_staff_id, p_date, 'off', nullif(p_note,''), true)
    returning id into newid;
  else
    delete from public.staff_busy where staff_id = p_staff_id and the_date = p_date and kind = 'off';
    insert into public.staff_busy (staff_id, the_date, kind, at_time, place, note, title, all_day)
    values (p_staff_id, p_date, p_kind,
            case when coalesce(p_all_day, false) then null else p_time end,
            nullif(p_place,''), nullif(p_note,''), nullif(p_title,''),
            coalesce(p_all_day, false))
    returning id into newid;
  end if;
  return jsonb_build_object('ok', true, 'id', newid);
end$fn$;
revoke all on function public.staff_busy_add(uuid, date, text, text, text, text, text, boolean) from public;
grant execute on function public.staff_busy_add(uuid, date, text, text, text, text, text, boolean) to anon, authenticated;

-- ── 수정 ──────────────────────────────────────────────────────
create or replace function public.staff_busy_upd(
  p_staff_id uuid, p_id bigint,
  p_time text default null, p_place text default null, p_note text default null,
  p_title text default null, p_all_day boolean default false)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare row public.staff_busy;
begin
  select * into row from public.staff_busy where id = p_id and staff_id = p_staff_id;   -- 본인 것만
  if not found then raise exception '내 일정이 아닙니다'; end if;
  if row.kind = 'off' then raise exception '촬영불가는 수정할 수 없습니다. 해제 후 다시 등록해 주세요'; end if;
  if row.kind = 'busy' and not coalesce(p_all_day, false)
     and (p_time is null or p_time !~ '^[0-2][0-9]:[0-5][0-9]$') then
    raise exception '시간을 HH:MM 형식으로 입력해 주세요';
  end if;
  update public.staff_busy
     set at_time = case when coalesce(p_all_day, false) then null else p_time end,
         place   = nullif(p_place, ''),
         note    = nullif(p_note, ''),
         title   = nullif(p_title, ''),
         all_day = coalesce(p_all_day, false)
   where id = p_id and staff_id = p_staff_id;
  return jsonb_build_object('ok', true, 'id', p_id);
end$fn$;
revoke all on function public.staff_busy_upd(uuid, bigint, text, text, text, text, boolean) from public;
grant execute on function public.staff_busy_upd(uuid, bigint, text, text, text, text, boolean) to anon, authenticated;

-- ── 작가 화면: 자기 것은 전부 보인다 ──────────────────────────
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
          'title', sb.title, 'all_day', sb.all_day)
          order by sb.the_date, sb.all_day desc, sb.at_time)
        from public.staff_busy sb
        where sb.staff_id = p_staff_id and sb.the_date between p_from and p_to), '[]'::jsonb)
  ) into res;
  return res;
end$fn$;
revoke all on function public.staff_calendar(uuid, date, date) from public;
grant execute on function public.staff_calendar(uuid, date, date) to anon, authenticated;

-- ── 관리자에게 보일 한 줄 ─────────────────────────────────────
-- 다른 촬영은 시간·장소까지. 개인일정은 그날 못 한다는 것만.
create or replace function private.busy_label(sb public.staff_busy, p_tail text)
returns text language sql immutable set search_path = public, pg_temp as $fn$
  select case
    when sb.kind = 'personal' then '개인 일정' || p_tail
    when sb.kind = 'off' then '하루 불가'
    else (case when sb.all_day then '종일' else coalesce(public.fmt_ktime(sb.at_time), '시간미정') end)
         || coalesce(' ' || nullif(sb.place, ''), '') || ' 다른 촬영' || p_tail
  end;
$fn$;

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

create or replace function public.admin_staff_availability(p_date date, p_time text default null)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(t order by (t.status <> 'ok'), t.name), '[]'::jsonb) into res from (
    select s.id, s.name,
      case when exists(select 1 from public.staff_busy sb
                        where sb.staff_id = s.id and sb.the_date = p_date
                          and sb.kind in ('off', 'personal')) then 'off'
           when exists(select 1 from public.staff_busy sb
                        where sb.staff_id = s.id and sb.the_date = p_date and sb.kind = 'busy'
                          and (sb.all_day or private.too_close(sb.at_time, p_time))) then 'tight'
           when exists(select 1 from public.bookings b
                        where (b.assignee_id = s.id or b.sub_assignee_id = s.id)
                          and b.status <> '취소' and b.wedding_date = p_date
                          and private.too_close(b.wedding_time, p_time)) then 'tight'
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
  ) t;
  return res;
end$fn$;
revoke all on function public.admin_staff_availability(date, text) from public, anon;
grant execute on function public.admin_staff_availability(date, text) to authenticated;
