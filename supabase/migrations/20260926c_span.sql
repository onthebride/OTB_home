/* 쭉 이어지는 일정 — 27일 11시부터 28일 오후 5시까지
   (대표 2026-09-26 «이게 내가 27일 11시부터 28일 오후 5시까지로 설정했단말이지»)

   ── 무엇이 없었나
   「언제까지」 로 여러 날을 고르면 시각은 **날마다 반복**으로 들어갔다.
     27~28 · 11:00~19:00  →  27일 11~19시 · 28일 11~19시
   대표가 뜻하신 「27일 11시에 시작해서 28일 17시에 끝나는 하나의 일정」 은
   적을 방법이 아예 없었다. 칸 이름은 「언제까지」 인데 시각만 날마다 반복이라
   앞뒤가 안 맞았다. 대표가 메모에 손으로 「27일 11시부터 / 28일 17시까지」 라고
   적어두신 것이 그 증거다 — 시스템이 못 받으니 사람이 적어둔 것이다.

   ── 이렇게 넣는다 (p_span)
     첫날      = 시작 시각만 (11:00)
     가운데 날 = 종일
     마지막 날 = 종료 시각만 (17:00)
   세 줄 다 all_day 라 **그 날들은 통째로 막힌다.** 이어지는 일정이니 그게 맞다.
   ⚠ 「몇 시부터 몇 시까지」 는 화면에 보이라고 남겨두는 값이다 —
     막는 셈에는 안 들어간다(all_day 가 먼저 참이라 busy_clash 가 바로 true 다).
     실제로 우리 예식이 10:30~19:00 이라 두 셈의 결과가 같다.

   ── 구멍이 있으면 아예 안 넣는다
   가운데 날에 배정된 예식이 있으면 「이어진다」 가 거짓말이 된다.
   그럴 때는 건너뛰지 않고 통째로 거절하고 왜인지 말한다.

   ── 안 바뀌는 것
   · p_span 을 안 주면 **예전 그대로 날마다 반복**이다. RPC 를 부르던 자리가 안 깨진다
   · 지금 들어 있는 줄은 하나도 안 바뀐다 (span 은 기본 false)
   · 밤을 넘기는 규칙(20260926b)은 span 이 아닐 때만 돈다 — span 은 제 끝날을 안다 */

/* 이 줄이 「쭉 이어지는 묶음의 한 조각」 이라는 표.
   ⚠ 값을 꼴로 짐작하지 않는다(종일인데 시각이 있으면 span, 같은 식).
     조용히 틀릴 자리라 칸으로 못박는다 */
alter table public.staff_busy add column if not exists span boolean not null default false;

/* ⚠ 칸을 더하니 drop 을 같이 쓴다 (CLAUDE.md). 안 그러면 옛 판과 새 판이 같이 남아
   「어느 것인지 모르겠다」 로 터진다 — 2026-09-25 에 실제로 그랬다 */
drop function if exists public.staff_busy_add_range(uuid, date, date, text, text, text, text, boolean, text, text);


CREATE OR REPLACE FUNCTION private.busy_label(sb staff_busy, p_tail text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when sb.kind = 'personal' then '개인 일정' || p_tail
    when sb.kind = 'off' then '하루 불가'
    else (case
               /* 쭉 이어지는 일정의 한 조각 (대표 2026-09-26).
                  첫날은 시작만, 마지막 날은 끝만, 가운데 날은 종일이다.
                  ⚠ 한 줄만 보고도 읽히게 적는다 — 이 함수는 옆줄을 못 본다 */
               when coalesce(sb.span, false) then
                 case when nullif(sb.at_time, '') is not null
                        then public.fmt_ktime(sb.at_time) || '부터 이어짐'
                      when nullif(sb.end_time, '') is not null
                        then public.fmt_ktime(sb.end_time) || '까지 이어짐'
                      else '종일 이어짐' end
               when sb.all_day then '종일'
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

CREATE OR REPLACE FUNCTION public.staff_busy_add_range(p_staff_id uuid, p_from date, p_to date, p_title text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_time text DEFAULT NULL::text, p_place text DEFAULT NULL::text, p_all_day boolean DEFAULT true, p_kind text DEFAULT 'personal'::text, p_end text DEFAULT NULL::text, p_span boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare d date; last_d date; sp boolean; n int := 0; gid uuid := gen_random_uuid(); skipped jsonb := '[]'::jsonb; k text; e text;
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

  /* 쭉 이어지는 하나의 일정인가 (대표 2026-09-26
       «내가 27일 11시부터 28일 오후 5시까지로 설정했단말이지»).
     첫날은 시작만 · 가운데 날은 종일 · 마지막 날은 끝만 갖는다.
     ⚠ 안 주면 예전 그대로 「날마다 반복」 이다 — 부르던 자리가 안 깨진다 */
  sp := coalesce(p_span, false);
  if sp then
    if coalesce(p_all_day, true) or nullif(p_time, '') is null or e is null then
      raise exception '쭉 이어지는 일정은 시작·종료 시각을 둘 다 골라 주세요';
    end if;
    if p_to <= p_from then
      raise exception '쭉 이어지는 일정은 마지막 날을 시작한 날보다 뒤로 골라 주세요';
    end if;
    /* ⚠ 가운데가 비면 「이어진다」 가 거짓말이 된다. 건너뛰지 않고 통째로 거절한다 */
    if exists (select 1 from generate_series(p_from, p_to, interval '1 day') g
                where g::date < current_date - 1
                   or exists (select 1 from public.bookings b
                               where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
                                 and b.status <> '취소' and b.wedding_date = g::date)) then
      raise exception '그 사이에 배정된 예식이나 지난 날짜가 있어 이어서 넣을 수 없습니다';
    end if;
  end if;

  /* ⚠⚠ 밤을 넘기는 일정(끝이 시작보다 이른)이면 「언제까지」 는
       **마지막 새벽이 끝나는 날**이다. 마지막 밤은 그 하루 전에 시작한다.
       대표가 27일 밤 8시 ~ 28일 새벽 2시를 27~28 로 넣으셨더니
       27일 밤과 28일 밤, 두 밤이 들어갔다 (대표 «다음날 반복되서 등되면 안되는거지»).
         27 ~ 28 (밤 넘김) → 27일 밤 하나
         27 ~ 29 (밤 넘김) → 27일·28일 밤 둘 (29일 새벽에 끝난다)
         27 ~ 27 (밤 넘김) → 27일 밤 하나 — 하루만 고르신 것이니 빼지 않는다
       ⚠ 밤을 안 넘기면 예전 그대로다. e 는 busy_end_ok 를 거친 값이라
         종일이면 null 이 되어 이 갈래로 안 온다 */
  last_d := case when not sp and e is not null and nullif(p_time, '') is not null
                  and e::time < p_time::time and p_to > p_from
                 then p_to - 1 else p_to end;

  d := p_from;
  while d <= last_d loop
    if d < current_date - 1 then
      skipped := skipped || jsonb_build_object('d', d, 'why', '지난 날짜');
    elsif exists (select 1 from public.bookings b
                   where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
                     and b.status <> '취소' and b.wedding_date = d) then
      skipped := skipped || jsonb_build_object('d', d, 'why', '배정된 예식');
    else
      delete from public.staff_busy where staff_id = p_staff_id and the_date = d and kind = 'off';
      insert into public.staff_busy (staff_id, the_date, kind, at_time, end_time, place, note, title, all_day, group_id, span)
      values (p_staff_id, d, k,
              case when sp then (case when d = p_from then p_time end)
                   when coalesce(p_all_day, true) then null
                   else p_time end,
              case when sp then (case when d = p_to then e end) else e end,
              nullif(p_place, ''), nullif(p_note, ''), nullif(p_title, ''),
              sp or coalesce(p_all_day, true), gid, sp);
      n := n + 1;
    end if;
    d := d + 1;
  end loop;

  return jsonb_build_object('ok', n > 0, 'n', n, 'group', gid, 'skipped', skipped, 'kind', k);
end$function$
;

CREATE OR REPLACE FUNCTION public.staff_busy_upd_group(p_staff_id uuid, p_group uuid, p_title text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_time text DEFAULT NULL::text, p_place text DEFAULT NULL::text, p_all_day boolean DEFAULT true, p_end text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare n int; e text; sp boolean; d_from date; d_to date;
begin
  if p_group is null then raise exception '내 일정이 아닙니다'; end if;
  e := private.busy_end_ok(p_time, p_end, p_all_day);
  if e = '' then raise exception '끝나는 시각을 시작과 다르게 골라 주세요 (밤을 넘기면 다음날로 봅니다)'; end if;
  /* 쭉 이어지는 묶음이면 첫날·마지막 날만 시각을 갖는다 (대표 2026-09-26).
     ⚠ 예전처럼 날마다 같은 값을 밀어 넣으면 이어지던 모양이 통째로 망가진다 */
  select bool_or(coalesce(o.span, false)), min(o.the_date), max(o.the_date)
    into sp, d_from, d_to
    from public.staff_busy o where o.group_id = p_group and o.staff_id = p_staff_id;

  if coalesce(sp, false) then
    if nullif(p_time, '') is null or e is null then
      raise exception '쭉 이어지는 일정은 시작·종료 시각을 둘 다 골라 주세요';
    end if;
    update public.staff_busy
       set title    = nullif(p_title, ''),
           note     = nullif(p_note, ''),
           place    = nullif(p_place, ''),
           at_time  = case when the_date = d_from then p_time end,
           end_time = case when the_date = d_to then e end,
           all_day  = true
     where group_id = p_group and staff_id = p_staff_id;   -- 본인 것만
  else
  update public.staff_busy
     set title    = nullif(p_title, ''),
         note     = nullif(p_note, ''),
         place    = nullif(p_place, ''),
         at_time  = case when coalesce(p_all_day, true) then null else p_time end,
         end_time = e,
         all_day  = coalesce(p_all_day, true)
   where group_id = p_group and staff_id = p_staff_id;   -- 본인 것만
  end if;
  get diagnostics n = row_count;
  if n = 0 then raise exception '내 일정이 아닙니다'; end if;
  return jsonb_build_object('ok', true, 'n', n);
end$function$
;

CREATE OR REPLACE FUNCTION public.staff_calendar(p_staff_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  st public.staff; res jsonb; nd date;
  today date := (now() at time zone 'Asia/Seoul')::date;
  upto  date;   -- 어디까지 보여줄까 (아래 설명)
begin
  select * into st from public.staff where id = p_staff_id;
  if not found then return null; end if;
  if p_to < p_from or p_to > p_from + 400 then raise exception 'bad range'; end if;

  -- 가장 가까운 「날」
  select min(b.wedding_date) into nd from public.bookings b
   where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
     and b.status <> '취소'
     and b.wedding_date >= today;

  -- 예식은 «이틀 전부터» 보인다. 다만 이틀 안에 아무것도 없는 분도 있으니
  -- 가장 가까운 날 하나는 언제나 나오게 둔다 (그래서 greatest 다)
  upto := greatest(nd, today + 2);

  select jsonb_build_object(
    'staff_name', st.name,
    'staff_photo', st.photo_url,
    'from', p_from, 'to', p_to,
    -- 다음 촬영 — 첫째 날은 그대로, 그 뒤 이틀 안의 날은 more 에. 보고 있는 달과는 무관하다
    'next', case when nd is null then null else jsonb_build_object(
      'wedding_date', nd,
      'days', (nd - today),
      'items', private.shoot_items(p_staff_id, nd),
      -- 첫째 날 다음으로 오는 날들 (오늘+2 까지). 없으면 빈 목록
      'more', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'wedding_date', dd.wd,
                 'days', (dd.wd - today),
                 'items', private.shoot_items(p_staff_id, dd.wd)) order by dd.wd)
        from (select distinct b2.wedding_date as wd
              from public.bookings b2
              where (b2.assignee_id = p_staff_id or b2.sub_assignee_id = p_staff_id)
                and b2.status <> '취소'
                and b2.wedding_date > nd and b2.wedding_date <= upto) dd), '[]'::jsonb)) end,
    'bookings', coalesce((select jsonb_agg(x order by x->>'wedding_date', x->>'wedding_time') from (
        select jsonb_build_object(
          'booking_id', b.id, 'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time,
          'wedding_venue', b.wedding_venue,
          'role', case when b.assignee_id = p_staff_id then '메인' else '서브' end,
          'bride_name', b.bride_name, 'groom_name', b.groom_name,
          'bride_phone', case when b.wedding_date <= current_date + 14 then b.bride_phone end,
          'groom_phone', case when b.wedding_date <= current_date + 14 then b.groom_phone end,
          /* 신부님이 나를 지정하신 촬영인가 (대표 2026-09-19).
             ⚠ pick_pin 은 언제나 메인이다 — 서브로 들어가신 분께는 안 붙는다.
             ⚠ 받으실 돈은 서버가 셈해서 보낸다. 화면에서 다시 셈하면 수수료를
               다시 떼기로 하실 때 두 군데를 고쳐야 하고 한쪽이 남는다 */
          'pick_mine', (b.pick_pin is not null and b.pick_pin = p_staff_id),
          'pick_pay_won', case when b.pick_pin = p_staff_id
                               then private.pick_staff_pay(b.pick_fee_won) end,
          'option_reception', b.option_reception, 'option_pyebaek', b.option_pyebaek,
          'option_part2', b.option_part2, 'photographer', b.photographer, 'rep_designation', b.rep_designation,
          -- 신부가 촬영 설문을 냈는지. 냈으면 캘린더에서 바로 열 수 있게 한다
          'has_survey', exists(select 1 from public.surveys s where s.booking_id = b.id),
          'photo_usage_agree', coalesce(b.photo_usage_agree, false)
        ) || private.peer_of(b, p_staff_id) as x
        from public.bookings b
        where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
          and b.status <> '취소' and b.wedding_date between p_from and p_to) t), '[]'::jsonb),
    'busy', coalesce((select jsonb_agg(jsonb_build_object(
          'id', sb.id, 'the_date', sb.the_date, 'kind', sb.kind,
          'at_time', sb.at_time, 'end_time', sb.end_time, 'place', sb.place, 'note', sb.note,
          'title', sb.title, 'all_day', sb.all_day, 'group_id', sb.group_id, 'span', sb.span,
          -- 묶음이면 전체가 언제부터 언제까지인지 (달력 범위 밖까지 포함해서 센다)
          'g_from', g.g_from, 'g_to', g.g_to, 'g_n', g.g_n,
          -- 쭉 이어지는 묶음이면 첫날 시작·마지막날 종료 (화면이 한 줄로 그린다)
          'g_at', g.g_at, 'g_end', g.g_end)
          order by sb.the_date, sb.all_day desc, sb.at_time)
        from public.staff_busy sb
        left join lateral (
          select min(o.the_date) g_from, max(o.the_date) g_to, count(*)::int g_n,
                 (array_agg(o.at_time order by o.the_date) filter (where o.at_time is not null))[1] g_at,
                 (array_agg(o.end_time order by o.the_date desc) filter (where o.end_time is not null))[1] g_end
          from public.staff_busy o
          where o.group_id = sb.group_id and o.staff_id = sb.staff_id
        ) g on sb.group_id is not null
        where sb.staff_id = p_staff_id and sb.the_date between p_from and p_to), '[]'::jsonb)
  ) into res;
  return res;
end$function$
;
