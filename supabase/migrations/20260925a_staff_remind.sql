/* 작가 캘린더 「미리 알림」 (대표 2026-09-25)

   «작가들이 스케줄받으면 캘린더 알림이 가잖아? … 그거랑은 완전 별개로
     캘린더 자체가 핸드폰에 보내는 팝업 알림 / 우리가 작가들이 우리 캘린더를 썼으면 했잖아
     그 기능 추가 관점에서 / 본인 스케줄이나 개인 일정이 있으면 사전에 알림을 좀 받고 싶은거지
     3일전 하루 전 당일 오전 6시 이렇게 / 설정 알림에 알림받을 시간을 추가해서»

   지금은 **대표가 배정하실 때 한 번**만 폰 알림이 간다. 그 한 번이 끝이라
   작가님들은 우리 캘린더를 「배정 받는 곳」으로만 쓰신다.
   다가오는 일정을 미리 알려주면 그때부터 「내 캘린더」가 된다 — 그게 이 판의 목적이다.

   ⚠ 우리 예식과 **개인 일정 둘 다** 알린다. 개인 일정이 빠지면 내 캘린더가 안 된다.
   ⚠ 같은 알림을 두 번 보내지 않는다. 크론은 한 시간에 한 번 돌고 두 번 돌 수도 있다 —
     보낸 것을 표에 적어 두고 거른다 (staff_notice 에는 unique 가 없다).
   ⚠ 시각은 **시 단위**만 고르게 한다. 크론이 정시에 도니 분 단위를 받으면 못 지킨다.
     못 지킬 약속을 화면에 두지 않는다.
   ⚠ 처음에는 **아무에게도 안 간다**(remind_ahead 가 빈 배열). 대표가 «내 캘린더에 먼저»
     하셔서 대표만 켜 둔다. */

-- ── ① 설정 칸 ────────────────────────────────────────────────
-- remind_ahead : 며칠 전에 받을지. {3,1,0} = 3일 전·하루 전·당일. 비어 있으면 안 받는다
-- remind_at    : 받을 시각 (한국시간). 시 단위만 쓴다
alter table public.staff add column if not exists remind_ahead int[] not null default '{}'::int[];
alter table public.staff add column if not exists remind_at time not null default '07:00';

do $$ begin
  alter table public.staff add constraint staff_remind_ahead_ok
    check (remind_ahead <@ array[0,1,2,3,7]);
exception when duplicate_object then null; end $$;

-- ── ② 보낸 기록 ──────────────────────────────────────────────
/* ⚠ 이것이 「두 번 안 보내기」의 전부다. staff_notice 에는 unique 가 없어
   거기에 기대면 크론이 두 번 돌 때 두 통이 간다 */
create table if not exists private.staff_remind_log (
  staff_id uuid not null references public.staff(id) on delete cascade,
  the_date date not null,          -- 일정이 있는 날
  ref      text not null,          -- 'b:<예약id>' 또는 'p:<개인일정id>'
  ahead    int  not null,          -- 며칠 전에 보낸 것인가
  sent_at  timestamptz not null default now(),
  primary key (staff_id, the_date, ref, ahead)
);
create index if not exists staff_remind_log_sent on private.staff_remind_log (sent_at);

-- ── ③ 설정 읽기·쓰기에 칸을 더한다 ───────────────────────────
create or replace function public.staff_settings(p_staff_id uuid)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $fn$
declare st public.staff; r jsonb := private.pick_rules(); e jsonb;
begin
  select * into st from public.staff where id = p_staff_id and coalesce(active,false);
  if not found then raise exception 'staff not found'; end if;

  e := private.pick_eligible(p_staff_id);

  return jsonb_build_object(
    'name', st.name,
    'is_rep', coalesce(st.is_rep, false),
    'accepting', coalesce(st.accepting, true),
    'pick_fee', st.pick_fee,
    -- 지금까지 화면이 쓰던 이름 둘. 그대로 둔다
    'reviews', e->'reviews',
    'need', (r->>'reviews')::int,
    'can_fee', (e->>'ok')::boolean,
    'elig', e,
    'base', (r->>'base')::int,
    'tax_bp', (r->>'tax_bp')::int,
    -- 2026-09-16 에 더한 값 규칙. 화면이 여기서 받아 적는다 — 두 곳에 숫자를 두지 않는다
    'fee_min',     (r->>'fee_min')::int,
    'pin_default', (r->>'pin_default')::int,
    'cut_pct',     (r->>'cut_pct')::int,
    'cut_max',     (r->>'cut_max')::int,
    -- 2026-09-25 미리 알림
    'remind_ahead', to_jsonb(coalesce(st.remind_ahead, '{}'::int[])),
    'remind_at',    to_char(st.remind_at, 'HH24:MI'));
end$fn$;

create or replace function public.staff_settings_set(p_staff_id uuid, p_patch jsonb)
returns jsonb language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $fn$
declare e jsonb; r jsonb; fee int; cap int; fmin int; ah int[]; hh int;
begin
  if not exists (select 1 from public.staff where id = p_staff_id and coalesce(active,false)) then
    raise exception 'staff not found';
  end if;
  if jsonb_typeof(p_patch) <> 'object' then raise exception 'bad patch'; end if;

  if p_patch ? 'accepting' then
    if jsonb_typeof(p_patch->'accepting') <> 'boolean' then raise exception 'bad accepting'; end if;
    update public.staff set accepting = (p_patch->>'accepting')::boolean where id = p_staff_id;
  end if;

  if p_patch ? 'pick_fee' then
    e := private.pick_eligible(p_staff_id);
    r := private.pick_rules();
    if not (e->>'ok')::boolean then
      raise exception 'not eligible: shots %/% reviews %/% gallery %/% accepting % can_main %',
        e->>'shots', e->>'need_shots', e->>'reviews', e->>'need_reviews',
        e->>'gallery', e->>'need_gallery', e->>'accepting', e->>'can_main';
    end if;
    fee := nullif(p_patch->>'pick_fee','')::int;
    if fee is not null and fee < 0 then raise exception 'bad fee'; end if;
    fmin := (r->>'fee_min')::int;
    if fee is not null and fee > 0 and fee < fmin then
      raise exception '지정 촬영비는 %원부터 정하실 수 있어요 (안 받으시려면 0)',
        to_char(fmin, 'FM999,999,999');
    end if;
    -- ⚠ 만원 단위. 예약 총액이 만원 단위 정수라 그 아래는 담을 곳이 없다
    if fee is not null and fee % 10000 <> 0 then
      raise exception '만원 단위로 정해주세요 (예: 50,000 · 60,000 · 100,000)';
    end if;
    cap := (e->>'fee_cap')::int;
    if fee is not null and fee > cap then
      raise exception '지금 한도는 %원입니다 (촬영 %회·후기 %개·사진 %장). 더 쌓이면 한도가 올라갑니다',
        to_char(cap, 'FM999,999,999'), e->>'shots', e->>'reviews', e->>'gallery';
    end if;
    update public.staff set pick_fee = fee, pick_fee_at = now() where id = p_staff_id;
  end if;

  /* 미리 알림 (2026-09-25).
     ⚠ 아무거나 받지 않는다 — 화면에 없는 값이 들어오면 그대로 굳어 영영 못 고치신다 */
  if p_patch ? 'remind_ahead' then
    if jsonb_typeof(p_patch->'remind_ahead') <> 'array' then raise exception 'bad remind_ahead'; end if;
    select coalesce(array_agg(distinct v order by v desc), '{}'::int[]) into ah
      from jsonb_array_elements_text(p_patch->'remind_ahead') x(v0)
      cross join lateral (select (x.v0)::int v) z
     where (x.v0) ~ '^[0-9]+$' and (x.v0)::int = any (array[0,1,2,3,7]);
    update public.staff set remind_ahead = ah where id = p_staff_id;
  end if;

  if p_patch ? 'remind_at' then
    /* ⚠ **시 단위만** 받는다. 크론이 정시에 도는데 분을 받으면 그 약속을 못 지킨다.
       화면에도 시만 고르게 해뒀다 — 여기서도 막아 둔다 */
    hh := nullif(regexp_replace(coalesce(p_patch->>'remind_at',''), '[^0-9].*$', ''), '')::int;
    if hh is null or hh < 0 or hh > 23 then raise exception '알림 시각은 0~23시로 정해주세요'; end if;
    update public.staff set remind_at = make_time(hh, 0, 0) where id = p_staff_id;
  end if;

  return public.staff_settings(p_staff_id);
end$fn$;

grant execute on function public.staff_settings(uuid) to anon, authenticated;
grant execute on function public.staff_settings_set(uuid, jsonb) to anon, authenticated;

-- ── ④ 보내는 사람 ────────────────────────────────────────────
/* 한 시간에 한 번 돈다. 지금이 그 작가님이 고른 시각인 사람만 골라,
   그분의 「며칠 전」마다 그 날짜의 일정을 찾아 알린다.
   ⚠ 이미 보낸 것은 staff_remind_log 로 거른다.
   ⚠ 개인 일정의 제목·메모는 **안 싣는다**. 폰 잠금화면에 뜨는 글이다 —
     「개인 일정」이라고만 적는다 (private.busy_label 과 같은 결). */
create or replace function private.staff_remind_send(p_dry boolean default false)
returns jsonb language plpgsql security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $fn$
declare
  now_kst timestamp := (now() at time zone 'Asia/Seoul');
  today   date := now_kst::date;
  hh      int  := extract(hour from now_kst)::int;
  r record; it record; n int := 0; rows_ jsonb := '[]'::jsonb;
  ttl text; msg text; whenw text; lines text[]; refs text[];
begin
  for r in
    select st.id as staff_id, st.name, a.ahead, (today + a.ahead) as d
      from public.staff st
      cross join lateral unnest(st.remind_ahead) as a(ahead)
     where coalesce(st.active, false)
       and extract(hour from st.remind_at)::int = hh
  loop
    whenw := case r.ahead when 0 then '오늘' when 1 then '내일' when 2 then '모레'
                          else r.ahead || '일 뒤' end;

    lines := '{}'; refs := '{}';
      for it in
        -- ① 우리 예식
        select 'b:' || b.id::text as ref,
               coalesce(public.fmt_ktime(b.wedding_time), '시간 미정')
               || coalesce(' · ' || nullif(b.wedding_venue, ''), '')
               || case when b.assignee_id = r.staff_id then '' else ' (서브)' end as line
          from public.bookings b
         where b.status <> '취소' and b.wedding_date = r.d
           and r.staff_id in (b.assignee_id, b.sub_assignee_id)
        union all
        -- ② 작가님이 적어두신 일정. 제목·메모는 안 싣는다
        select 'p:' || sb.id::text,
               private.busy_label(sb, '')
          from public.staff_busy sb
         where sb.staff_id = r.staff_id and sb.the_date = r.d
        order by 2
      loop
        if exists (select 1 from private.staff_remind_log g
                    where g.staff_id = r.staff_id and g.the_date = r.d
                      and g.ref = it.ref and g.ahead = r.ahead) then
          continue;
        end if;
        lines := lines || it.line;
        refs  := refs  || it.ref;
      end loop;

      if array_length(lines, 1) is null then continue; end if;

      ttl := '📅 ' || whenw || ' 일정이 있어요';
      msg := to_char(r.d, 'MM월 DD일') || '(' ||
             (array['일','월','화','수','목','금','토'])[extract(dow from r.d)::int + 1] || ')'
             || E'\n' || array_to_string(lines, E'\n');

      rows_ := rows_ || jsonb_build_object('staff', r.name, 'ahead', r.ahead,
                                           'date', r.d, 'n', array_length(lines, 1));
      n := n + 1;
      if not p_dry then
        insert into public.staff_notice(staff_id, booking_id, kind, title, body)
        values (r.staff_id, null, 'remind', ttl, msg);
        perform private.otb_push(ttl, msg, '/staff-calendar?s=' || r.staff_id::text, r.staff_id);
        insert into private.staff_remind_log(staff_id, the_date, ref, ahead)
        select r.staff_id, r.d, x, r.ahead from unnest(refs) x
        on conflict do nothing;
      end if;
  end loop;

  return jsonb_build_object('ok', true, 'dry', p_dry, 'hour', hh, 'sent', n, 'rows', rows_);
end$fn$;

-- ── ⑤ 한 시간에 한 번 ────────────────────────────────────────
select cron.unschedule('otb-staff-remind') where exists (
  select 1 from cron.job where jobname = 'otb-staff-remind');
select cron.schedule('otb-staff-remind', '0 * * * *', $$select private.staff_remind_send();$$);
