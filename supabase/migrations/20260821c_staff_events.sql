-- 작가 캘린더를 '스케줄러' 로. (대표 요청)
--
-- 왜
--   작가들은 대개 캘린더 앱을 따로 안 쓴다. 그래서 '우리 일정을 작가 캘린더로 내보내기' 는
--   첫 관문(구독 등록)에서 막힌다. 반대로 간다 — 우리 것을 쓸 만하게 만든다.
--   작가가 여기 자기 일정까지 적으면 딴 데 적을 이유가 없어진다.
--   지금까지 작가가 직접 넣은 건 8건뿐이었다. 반면 우리가 물어봐 받은 확인은 56건.
--
-- 넣는 것
--   · title    제목을 자유롭게 (지금은 장소만 적을 수 있었다)
--   · all_day  종일 일정 (휴가·여행처럼 시간이 없는 것)
--   · is_private  나만 보기 — 이게 핵심이다
--
-- 나만 보기가 왜 핵심인가
--   작가가 개인 일정을 적으면 대표가 그걸 다 보게 된다. 병원·가족 일까지.
--   그러면 작가는 안 적는다. 결국 지금과 똑같아진다.
--   그래서 제목·장소·메모는 작가 화면에서만 보이고, 관리자 화면에는 '일정 있음' 으로만 나간다.
--   대표에게 필요한 건 '그 시간에 되냐' 뿐이라 판단에 필요한 정보는 그대로 남는다.

alter table public.staff_busy
  add column if not exists title      text,
  add column if not exists all_day    boolean not null default false,
  add column if not exists is_private boolean not null default false;

-- ── 등록 ──────────────────────────────────────────────────────
create or replace function public.staff_busy_add(
  p_staff_id uuid, p_date date, p_kind text,
  p_time text default null, p_place text default null, p_note text default null,
  p_title text default null, p_all_day boolean default false, p_private boolean default false)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare newid bigint;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and active) then raise exception 'staff not found'; end if;
  if p_kind not in ('off', 'busy') then raise exception 'bad kind'; end if;
  if p_date < current_date - 1 then raise exception '지난 날짜는 등록할 수 없습니다'; end if;
  -- 종일이 아니면 시간이 있어야 한다
  if p_kind = 'busy' and not coalesce(p_all_day, false)
     and (p_time is null or p_time !~ '^[0-2][0-9]:[0-5][0-9]$') then
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
    insert into public.staff_busy (staff_id, the_date, kind, note, all_day)
    values (p_staff_id, p_date, 'off', nullif(p_note,''), true)
    returning id into newid;
  else
    delete from public.staff_busy where staff_id = p_staff_id and the_date = p_date and kind = 'off';
    insert into public.staff_busy (staff_id, the_date, kind, at_time, place, note, title, all_day, is_private)
    values (p_staff_id, p_date, 'busy',
            case when coalesce(p_all_day, false) then null else p_time end,
            nullif(p_place,''), nullif(p_note,''), nullif(p_title,''),
            coalesce(p_all_day, false), coalesce(p_private, false))
    returning id into newid;
  end if;
  return jsonb_build_object('ok', true, 'id', newid);
end$fn$;
revoke all on function public.staff_busy_add(uuid, date, text, text, text, text, text, boolean, boolean) from public;
grant execute on function public.staff_busy_add(uuid, date, text, text, text, text, text, boolean, boolean) to anon, authenticated;

-- ── 고치기 ────────────────────────────────────────────────────
-- 지금까지는 지우고 다시 넣어야 했다. 캘린더로 쓰려면 이게 있어야 한다.
create or replace function public.staff_busy_upd(
  p_staff_id uuid, p_id bigint,
  p_time text default null, p_place text default null, p_note text default null,
  p_title text default null, p_all_day boolean default false, p_private boolean default false)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare row public.staff_busy;
begin
  select * into row from public.staff_busy where id = p_id and staff_id = p_staff_id;   -- 본인 것만
  if not found then raise exception '내 일정이 아닙니다'; end if;
  if row.kind <> 'busy' then raise exception '촬영불가는 고칠 수 없습니다. 해제 후 다시 등록해 주세요'; end if;
  if not coalesce(p_all_day, false) and (p_time is null or p_time !~ '^[0-2][0-9]:[0-5][0-9]$') then
    raise exception '시간을 HH:MM 형식으로 입력해 주세요';
  end if;
  update public.staff_busy
     set at_time    = case when coalesce(p_all_day, false) then null else p_time end,
         place      = nullif(p_place, ''),
         note       = nullif(p_note, ''),
         title      = nullif(p_title, ''),
         all_day    = coalesce(p_all_day, false),
         is_private = coalesce(p_private, false)
   where id = p_id and staff_id = p_staff_id;
  return jsonb_build_object('ok', true, 'id', p_id);
end$fn$;
revoke all on function public.staff_busy_upd(uuid, bigint, text, text, text, text, boolean, boolean) from public;
grant execute on function public.staff_busy_upd(uuid, bigint, text, text, text, text, boolean, boolean) to anon, authenticated;

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
    -- 우리 예식 배정 (연락처는 예식 2주 전부터만 — 그 전엔 필요 없음)
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
    -- 작가가 직접 등록한 것 (본인 화면이라 나만 보기도 그대로)
    'busy', coalesce((select jsonb_agg(jsonb_build_object(
          'id', sb.id, 'the_date', sb.the_date, 'kind', sb.kind,
          'at_time', sb.at_time, 'place', sb.place, 'note', sb.note,
          'title', sb.title, 'all_day', sb.all_day, 'is_private', sb.is_private)
          order by sb.the_date, sb.all_day desc, sb.at_time)
        from public.staff_busy sb
        where sb.staff_id = p_staff_id and sb.the_date between p_from and p_to), '[]'::jsonb)
  ) into res;
  return res;
end$fn$;
revoke all on function public.staff_calendar(uuid, date, date) from public;
grant execute on function public.staff_calendar(uuid, date, date) to anon, authenticated;

-- ── 관리자 화면에 보일 한 줄 ──────────────────────────────────
-- 나만 보기면 제목·장소를 가린다. 시간은 남긴다 — 대표는 그걸로 판단한다.
create or replace function private.busy_label(sb public.staff_busy, p_tail text)
returns text language sql immutable set search_path = public, pg_temp as $fn$
  select case when sb.all_day then '종일' else coalesce(public.fmt_ktime(sb.at_time), '시간미정') end
      || case when sb.is_private then ' 일정 있음'
              else coalesce(' ' || nullif(sb.title, ''), '')
                || coalesce(' ' || nullif(sb.place, ''), '') end
      || p_tail;
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
                          -- 종일 일정은 시간을 따질 수 없으니 그날은 걸린 것으로 본다
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
            where sb.staff_id = s.id and sb.the_date = b.wedding_date and sb.kind = 'busy'
              and (sb.all_day or private.too_close(sb.at_time, b.wedding_time))
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
                        where sb.staff_id = s.id and sb.the_date = p_date and sb.kind = 'off') then 'off'
           when exists(select 1 from public.staff_busy sb
                        where sb.staff_id = s.id and sb.the_date = p_date and sb.kind = 'busy'
                          and (sb.all_day or private.too_close(sb.at_time, p_time))) then 'tight'
           when exists(select 1 from public.bookings b
                        where (b.assignee_id = s.id or b.sub_assignee_id = s.id)
                          and b.status <> '취소' and b.wedding_date = p_date
                          and private.too_close(b.wedding_time, p_time)) then 'tight'
           else 'ok' end as status,
      -- 그날 이미 있는 일정(우리 예식 + 본인 등록) 요약
      coalesce((select string_agg(x, ' / ' order by x) from (
          select coalesce(public.fmt_ktime(b.wedding_time), '시간미정') || ' ' || coalesce(b.wedding_venue,'') as x
          from public.bookings b
          where (b.assignee_id = s.id or b.sub_assignee_id = s.id)
            and b.status <> '취소' and b.wedding_date = p_date
          union all
          select case when sb.kind = 'off' then '하루 불가'
                      else private.busy_label(sb, '') end || ' (본인 등록)'
          from public.staff_busy sb where sb.staff_id = s.id and sb.the_date = p_date) u), '') as detail
    from public.staff s where s.active
  ) t;
  return res;
end$fn$;
revoke all on function public.admin_staff_availability(date, text) from public, anon;
grant execute on function public.admin_staff_availability(date, text) to authenticated;
