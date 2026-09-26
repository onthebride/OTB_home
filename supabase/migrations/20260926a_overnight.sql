/* 밤을 넘기는 일정 — 밤 10시 ~ 다음날 새벽 2시
   (대표 2026-09-26 «당일 밤 10시부터 다음날 새벽2시까지 스케줄이면 시간범위로 등록이 어렵네»)

   ── 무엇이 막혀 있었나
   busy_end_ok 가 「끝이 시작보다 늦어야 한다」 로 잘라내고 있었다.
   22:00 → 02:00 은 숫자로만 보면 거꾸로라 아예 저장이 안 됐다.
   이제 **끝이 시작보다 이르면 다음날로 본다.** 같은 시각만 막는다(뜻이 없다).

   ── 같이 고치는 것 ⚠⚠ 어제 올린 판에 진짜 구멍이 있었다
   시각 셈을 postgres 의 time 으로 했는데, time 은 24시를 넘으면 **한 바퀴 돈다.**
     '23:00'::time + interval '2 hours'  →  01:00   (다음날이 아니라 그냥 새벽 1시)
   그래서 저녁 촬영 20:00~23:00 을 적어두면
     막히는 구간 = (20:00-2h, 23:00+2h) = (18:00, 01:00) → **어떤 시각도 해당 없음**
   즉 **저녁 촬영을 적어두면 아무것도 안 막혔다.** 우리 예식은 19:00 까지 있다.
   아직 끝 시각을 적어둔 줄이 0건이라 실제 피해는 없었지만, 대표 말씀대로
   밤 일정을 넣기 시작하면 바로 터질 자리였다.
   → 시·분을 **자정부터의 분(minute)** 으로 바꿔 센다. 한 바퀴 도는 일이 없다.

   ── 이제 이렇게 된다 (버퍼는 그대로, 끝을 알면 앞뒤 2시간)
     22:00 ~ 02:00 (다음날)  → 그날 20:00 부터 자정까지 막힘
     20:00 ~ 23:00           → 18:00~24:00 막힘   (전에는 아무것도 안 막혔다)
     13:00 ~ 14:00           → 12:00~15:00 막힘   (그대로)
     13:00 ~ 끝 없음         → 10:00~16:00 막힘   (그대로)

   ── 여기까지만 한다 (솔직하게 적어둔다)
   밤을 넘긴 **다음날 새벽 꼬리**는 그 다음날 예식을 막지 않는다.
   staff_busy 는 하루에 한 줄로 달려 있고, 배정을 보는 자리들이 전부
   「그 예식 날짜와 같은 날」 로 이어 보고 있기 때문이다.
   우리 예식은 10:30~19:00 이라, 새벽 2시에 끝나는 일정이 다음날 예식과
   부딪히는 일은 없다. 다만 **다음날 아침 8시 반 넘어까지 가는 밤샘**을 적으시면
   그 다음날은 안 막힌다 — 그때는 이틀로 나눠 적으셔야 한다.
   (전부 막으려면 배정을 보는 자리 여덟 군데의 날짜 이음새를 다 고쳐야 해서,
    대표께 먼저 말씀드리고 따로 한다) */

/* 자정부터 몇 분인가. time 처럼 한 바퀴 돌지 않는다 — 넘기면 넘긴 대로 센다 */
create or replace function private.min_of_day(t text)
returns int language sql immutable as $fn$
  select split_part(t, ':', 1)::int * 60 + split_part(t, ':', 2)::int;
$fn$;

/* 끝 시각을 받아도 되나. 「빈 칸」(null) 과 「잘못됐다」('') 를 가려 돌려준다.
   ⚠ 이제 끝이 시작보다 **이르면 다음날**이다. 막는 것은 같은 시각뿐 */
create or replace function private.busy_end_ok(p_time text, p_end text, p_all_day boolean)
returns text language sql immutable as $fn$
  select case
    when coalesce(p_all_day, false) then null
    when nullif(p_end, '') is null then null
    when nullif(p_time, '') is null then ''
    when p_end !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then ''
    when p_end::time = p_time::time then ''        -- 같은 시각은 뜻이 없다
    else p_end
  end;
$fn$;

/* 「다른 촬영」이 우리 예식과 겹치나.
   ⚠ 겹침을 재는 자리는 **여기 하나뿐**이다. 숫자도 여기 칸에만 적는다 */
create or replace function private.busy_clash(
  sb public.staff_busy, p_wed text,
  p_hours int default 4,        -- 끝을 모를 때: 시작에서 앞뒤로 (예전 그대로)
  p_span_hours int default 2)   -- 끝을 알 때: 앞뒤로 오가고 준비하는 시간만
returns boolean language sql immutable
set search_path to 'private', 'public', 'pg_temp'
as $fn$
  select case
    when coalesce(sb.all_day, false) then true                       -- 종일은 그날 통째로
    when coalesce(sb.at_time, '') = '' or coalesce(p_wed, '') = '' then false
    when coalesce(sb.end_time, '') = ''                              -- 끝을 모르면 예전 그대로
      then private.too_close(sb.at_time, p_wed, p_hours)
    else (select v.w > v.s - v.buf and v.w < v.e + v.buf from (
            select private.min_of_day(sb.at_time) as s,
                   -- 끝이 시작보다 이르면 밤을 넘긴 것이다 (하루를 더해 편다)
                   private.min_of_day(sb.end_time)
                     + case when private.min_of_day(sb.end_time)
                               < private.min_of_day(sb.at_time) then 1440 else 0 end as e,
                   private.min_of_day(p_wed) as w,
                   p_span_hours * 60 as buf) v)
  end;
$fn$;


CREATE OR REPLACE FUNCTION public.staff_busy_add(p_staff_id uuid, p_date date, p_kind text, p_time text DEFAULT NULL::text, p_place text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_title text DEFAULT NULL::text, p_all_day boolean DEFAULT false, p_end text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
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
  if e = '' then raise exception '끝나는 시각을 시작과 다르게 골라 주세요 (밤을 넘기면 다음날로 봅니다)'; end if;

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
end$function$
;

CREATE OR REPLACE FUNCTION public.staff_busy_add_range(p_staff_id uuid, p_from date, p_to date, p_title text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_time text DEFAULT NULL::text, p_place text DEFAULT NULL::text, p_all_day boolean DEFAULT true, p_kind text DEFAULT 'personal'::text, p_end text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
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
  if e = '' then raise exception '끝나는 시각을 시작과 다르게 골라 주세요 (밤을 넘기면 다음날로 봅니다)'; end if;

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
end$function$
;

CREATE OR REPLACE FUNCTION public.staff_busy_upd(p_staff_id uuid, p_id bigint, p_time text DEFAULT NULL::text, p_place text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_title text DEFAULT NULL::text, p_all_day boolean DEFAULT false, p_end text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
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
  if e = '' then raise exception '끝나는 시각을 시작과 다르게 골라 주세요 (밤을 넘기면 다음날로 봅니다)'; end if;

  update public.staff_busy
     set at_time  = case when coalesce(p_all_day, false) then null else p_time end,
         end_time = e,
         place    = nullif(p_place, ''),
         note     = nullif(p_note, ''),
         title    = nullif(p_title, ''),
         all_day  = coalesce(p_all_day, false)
   where id = p_id and staff_id = p_staff_id;
  return jsonb_build_object('ok', true, 'id', p_id);
end$function$
;

CREATE OR REPLACE FUNCTION public.staff_busy_upd_group(p_staff_id uuid, p_group uuid, p_title text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_time text DEFAULT NULL::text, p_place text DEFAULT NULL::text, p_all_day boolean DEFAULT true, p_end text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare n int; e text;
begin
  if p_group is null then raise exception '내 일정이 아닙니다'; end if;
  e := private.busy_end_ok(p_time, p_end, p_all_day);
  if e = '' then raise exception '끝나는 시각을 시작과 다르게 골라 주세요 (밤을 넘기면 다음날로 봅니다)'; end if;
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
end$function$
;

CREATE OR REPLACE FUNCTION private.busy_label(sb staff_busy, p_tail text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when sb.kind = 'personal' then '개인 일정' || p_tail
    when sb.kind = 'off' then '하루 불가'
    else (case when sb.all_day then '종일'
               else coalesce(public.fmt_ktime(sb.at_time), '시간미정')
                    || case when coalesce(sb.end_time, '') <> ''
                            then '~'
                                 || case when coalesce(sb.at_time, '') <> ''
                                          and sb.end_time::time < sb.at_time::time
                                         then '다음날 ' else '' end
                                 || coalesce(public.fmt_ktime(sb.end_time), '') else '' end
          end)
         || coalesce(' ' || nullif(sb.place, ''), '') || ' 다른 촬영' || p_tail
  end;
$function$
;
