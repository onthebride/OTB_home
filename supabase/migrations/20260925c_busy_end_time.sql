/* 다른 촬영에 「시작~종료 시간」 (대표 2026-09-25 «시작시간 종료시간도 넣는게 좋겠는데?»)

   지금까지는 시작 시간 하나만 받았다. 그래서 겹치는지 볼 때
   **시작에서 앞뒤 4시간**이라는 한 가지 잣대밖에 못 썼다.
   오후 1시에 시작해 6시에 끝나는 촬영이든 2시에 끝나는 촬영이든 똑같이 봤다.

   끝나는 시각을 알면 제대로 잰다 — 예식이 [시작−4시간, 종료+4시간] 안에 들면 겹침.
   ⚠⚠ 종료가 시작과 같으면 **지금 규칙과 똑같아진다** (|w−s| < 4h).
     그래서 끝 시각이 없는 옛 자료는 **하나도 안 바뀐다.** 이것이 이 판의 안전장치다.

   ⚠ 끝 시각은 안 적으셔도 된다. 없으면 예전 그대로 본다.
   ⚠ 자정을 넘기는 촬영은 못 담는다 (시각만 담고 날짜를 안 담는다).
     종료가 시작보다 이르면 안 받는다 — 조용히 엉뚱하게 재지 않는다.
   ⚠⚠ 아래 네 함수는 **살아 있는 정의를 그대로 옮기고 끝 시각만 더한 것**이다.
     특히 staff_busy_add 의 'off' 갈래는 ('off','busy') 만 지우고 **개인 일정은 남긴다** —
     작가님이 적어둔 메모라 지우면 안 된다. 그 줄을 바꾸지 말 것. */

alter table public.staff_busy add column if not exists end_time text;

/* ── 겹치는지 한 자리에서 판단한다 ──
   ⚠ 전에는 부르는 자리마다 `sb.all_day or too_close(sb.at_time, w)` 를 적어 두었다.
     자리가 둘이면 한쪽만 고쳐진다 — 하나로 모은다 */
create or replace function private.busy_clash(sb public.staff_busy, p_wed text, p_hours int default 4)
returns boolean language sql immutable
set search_path to 'private', 'public', 'pg_temp'
as $fn$
  select case
    when coalesce(sb.all_day, false) then true                       -- 종일은 그날 통째로
    when sb.at_time is null or sb.at_time = '' or p_wed is null or p_wed = '' then false
    when sb.end_time is null or sb.end_time = ''                     -- 끝을 모르면 예전 그대로
      then private.too_close(sb.at_time, p_wed, p_hours)
    else p_wed::time > (sb.at_time::time - make_interval(hours => p_hours))
     and p_wed::time < (sb.end_time::time + make_interval(hours => p_hours))
  end;
$fn$;

/* ── 화면에 적는 글 — 끝 시각이 있으면 「오후 1:00~오후 6:00」 ──
   ⚠ 개인 일정은 여전히 「개인 일정」뿐이다. 제목·메모·시간을 안 낸다 */
create or replace function private.busy_label(sb public.staff_busy, p_tail text)
returns text language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select case
    when sb.kind = 'personal' then '개인 일정' || p_tail
    when sb.kind = 'off' then '하루 불가'
    else (case when sb.all_day then '종일'
               else coalesce(public.fmt_ktime(sb.at_time), '시간미정')
                    || case when coalesce(sb.end_time, '') <> ''
                            then '~' || coalesce(public.fmt_ktime(sb.end_time), '') else '' end
          end)
         || coalesce(' ' || nullif(sb.place, ''), '') || ' 다른 촬영' || p_tail
  end;
$fn$;

/* 끝 시각을 다듬는다. 종일이거나 안 적으셨으면 없는 것으로 둔다.
   ⚠ 시작보다 이르면 null 이 아니라 **빈 글자**를 돌려준다 — 부르는 쪽이 그걸 보고 막는다 */
create or replace function private.busy_end_ok(p_time text, p_end text, p_all_day boolean)
returns text language sql immutable
as $fn$
  select case
    when coalesce(p_all_day, false) then null
    when nullif(p_end, '') is null then null
    when nullif(p_time, '') is null then ''
    when p_end !~ '^[0-2][0-9]:[0-5][0-9]$' then ''
    when p_end::time <= p_time::time then ''
    else p_end
  end;
$fn$;

-- ── 하루짜리 넣기 ────────────────────────────────────────────
drop function if exists public.staff_busy_add(uuid, date, text, text, text, text, text, boolean);
create or replace function public.staff_busy_add(
  p_staff_id uuid, p_date date, p_kind text,
  p_time text default null, p_place text default null, p_note text default null,
  p_title text default null, p_all_day boolean default false,
  p_end text default null)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $fn$
declare newid bigint; e text;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and active) then raise exception 'staff not found'; end if;
  if p_kind not in ('off', 'busy', 'personal') then raise exception 'bad kind'; end if;
  if p_date < current_date - 1 then raise exception '지난 날짜는 등록할 수 없습니다'; end if;
  -- 다른 촬영은 시간을 알아야 겹치는지 볼 수 있다. 개인일정은 어차피 그날을 막으니 시간이 없어도 된다.
  if p_kind = 'busy' and not coalesce(p_all_day, false)
     and (p_time is null or p_time !~ '^[0-2][0-9]:[0-5][0-9]$') then
    raise exception '시간을 HH:MM 형식으로 입력해 주세요';
  end if;
  e := private.busy_end_ok(p_time, p_end, p_all_day);
  if e = '' then raise exception '끝나는 시각은 시작보다 늦어야 해요'; end if;

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
    -- ⚠⚠ 개인일정은 남긴다 — 작가가 적어둔 자기 메모라 지워버리면 안 된다.
    delete from public.staff_busy
     where staff_id = p_staff_id and the_date = p_date and kind in ('off', 'busy');
    insert into public.staff_busy (staff_id, the_date, kind, note, all_day)
    values (p_staff_id, p_date, 'off', nullif(p_note,''), true)
    returning id into newid;
  else
    delete from public.staff_busy where staff_id = p_staff_id and the_date = p_date and kind = 'off';
    insert into public.staff_busy (staff_id, the_date, kind, at_time, end_time, place, note, title, all_day)
    values (p_staff_id, p_date, p_kind,
            case when coalesce(p_all_day, false) then null else p_time end,
            e, nullif(p_place,''), nullif(p_note,''), nullif(p_title,''),
            coalesce(p_all_day, false))
    returning id into newid;
  end if;
  return jsonb_build_object('ok', true, 'id', newid);
end$fn$;

-- ── 여러 날 넣기 ─────────────────────────────────────────────
drop function if exists public.staff_busy_add_range(uuid, date, date, text, text, text, text, boolean, text);
create or replace function public.staff_busy_add_range(
  p_staff_id uuid, p_from date, p_to date,
  p_title text default null, p_note text default null,
  p_time text default null, p_place text default null,
  p_all_day boolean default true,
  p_kind text default 'personal',
  p_end text default null)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $fn$
declare d date; n int := 0; gid uuid := gen_random_uuid(); skipped jsonb := '[]'::jsonb; k text; e text;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and active) then raise exception 'staff not found'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception '날짜 범위가 올바르지 않습니다'; end if;
  if p_to - p_from > 60 then raise exception '한 번에 60일까지만 됩니다'; end if;

  k := case when p_kind = 'busy' then 'busy' else 'personal' end;
  if k = 'busy' and not coalesce(p_all_day, true) and nullif(p_time, '') is null then
    raise exception '다른 촬영은 시간을 알려주셔야 해요 (하루 종일이면 종일로 해주세요)';
  end if;
  e := private.busy_end_ok(p_time, p_end, p_all_day);
  if e = '' then raise exception '끝나는 시각은 시작보다 늦어야 해요'; end if;

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
      insert into public.staff_busy (staff_id, the_date, kind, at_time, end_time, place, note, title, all_day, group_id)
      values (p_staff_id, d, k,
              case when coalesce(p_all_day, true) then null else p_time end,
              e, nullif(p_place, ''), nullif(p_note, ''), nullif(p_title, ''),
              coalesce(p_all_day, true), gid);
      n := n + 1;
    end if;
    d := d + 1;
  end loop;

  return jsonb_build_object('ok', n > 0, 'n', n, 'group', gid, 'skipped', skipped, 'kind', k);
end$fn$;

-- ── 고치기 ───────────────────────────────────────────────────
drop function if exists public.staff_busy_upd(uuid, bigint, text, text, text, text, boolean);
create or replace function public.staff_busy_upd(
  p_staff_id uuid, p_id bigint,
  p_time text default null, p_place text default null, p_note text default null,
  p_title text default null, p_all_day boolean default false,
  p_end text default null)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $fn$
declare row public.staff_busy; e text;
begin
  select * into row from public.staff_busy where id = p_id and staff_id = p_staff_id;   -- 본인 것만
  if not found then raise exception '내 일정이 아닙니다'; end if;
  if row.kind = 'off' then raise exception '촬영불가는 수정할 수 없습니다. 해제 후 다시 등록해 주세요'; end if;
  if row.kind = 'busy' and not coalesce(p_all_day, false)
     and (p_time is null or p_time !~ '^[0-2][0-9]:[0-5][0-9]$') then
    raise exception '시간을 HH:MM 형식으로 입력해 주세요';
  end if;
  e := private.busy_end_ok(p_time, p_end, p_all_day);
  if e = '' then raise exception '끝나는 시각은 시작보다 늦어야 해요'; end if;

  update public.staff_busy
     set at_time  = case when coalesce(p_all_day, false) then null else p_time end,
         end_time = e,
         place    = nullif(p_place, ''),
         note     = nullif(p_note, ''),
         title    = nullif(p_title, ''),
         all_day  = coalesce(p_all_day, false)
   where id = p_id and staff_id = p_staff_id;
  return jsonb_build_object('ok', true, 'id', p_id);
end$fn$;

drop function if exists public.staff_busy_upd_group(uuid, uuid, text, text, text, text, boolean);
create or replace function public.staff_busy_upd_group(
  p_staff_id uuid, p_group uuid,
  p_title text default null, p_note text default null,
  p_time text default null, p_place text default null,
  p_all_day boolean default true,
  p_end text default null)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $fn$
declare n int; e text;
begin
  if p_group is null then raise exception '내 일정이 아닙니다'; end if;
  e := private.busy_end_ok(p_time, p_end, p_all_day);
  if e = '' then raise exception '끝나는 시각은 시작보다 늦어야 해요'; end if;
  update public.staff_busy
     set title    = nullif(p_title, ''),
         note     = nullif(p_note, ''),
         place    = nullif(p_place, ''),
         at_time  = case when coalesce(p_all_day, true) then null else p_time end,
         end_time = e,
         all_day  = coalesce(p_all_day, true)
   where group_id = p_group and staff_id = p_staff_id;   -- 본인 것만
  get diagnostics n = row_count;
  if n = 0 then raise exception '내 일정이 아닙니다'; end if;
  return jsonb_build_object('ok', true, 'n', n);
end$fn$;

grant execute on function public.staff_busy_add(uuid, date, text, text, text, text, text, boolean, text) to anon, authenticated;
grant execute on function public.staff_busy_add_range(uuid, date, date, text, text, text, text, boolean, text, text) to anon, authenticated;
grant execute on function public.staff_busy_upd(uuid, bigint, text, text, text, text, boolean, text) to anon, authenticated;
grant execute on function public.staff_busy_upd_group(uuid, uuid, text, text, text, text, boolean, text) to anon, authenticated;
