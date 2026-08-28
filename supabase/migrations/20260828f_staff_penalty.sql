-- 작가 평가에 「감점」 을 더한다 (대표 요청 2026-08-28)
--
-- 지금까지 작가 점수는 **신부님 설문의 평균** 하나뿐이었다. 우리가 매기는 것이 없었다.
-- 대표가 둘을 더하기로 했다.
--
--   ① 예식 앞두고 스케줄 취소   1개월 전 -3 · 2주 전 -5 · 1주 전 -8   → 1개월 지나면 소멸
--   ② 지각                      조금 -2 · 많이 -5                     → 1년간 무지각이면 통째로 리셋
--
-- ⚠ 왜 지각을 설문 점수에서 빼내는가 (대표 «그 도착 점수를 좀 절대치로»)
--   전에는 도착이 설문 100점 안의 20점이었다. 그래서 **설문을 많이 받을수록 지각이 묻혔다** —
--   같은 「많이 늦음」 한 번이 응답 6건인 작가에겐 -1.3점, 1건인 작가에겐 -8점이었다.
--   이제 도착은 점수에서 빼고 감점으로 옮긴다. 응답 수와 무관하게 한 번은 한 번이다.
--
-- ⚠ 감점 점수는 **그때 값을 박아 둔다**(points 칸). 나중에 설정을 바꿔도 지난 일은 안 흔들린다.
-- ⚠ 면제(waived)는 지우지 않는다 — 무슨 일이 있었는지는 남고, 점수만 빼 준다.

/* ── 설정 — 대표가 화면에서 바꿀 수 있어야 한다 (지각 사례가 아직 0건이라 겪어보고 고칠 값들) ── */
create table if not exists private.penalty_conf (
  key text primary key,
  val numeric not null,
  memo text
);
insert into private.penalty_conf (key, val, memo) values
  ('cancel_1m',        3,  '예식 1개월 전 취소'),
  ('cancel_2w',        5,  '예식 2주 전 취소'),
  ('cancel_1w',        8,  '예식 1주 전 취소'),
  ('cancel_valid_days', 30, '취소 감점이 살아 있는 날 수'),
  ('late_small',       2,  '조금 늦음'),
  ('late_big',         5,  '많이 늦음'),
  ('late_reset_days',  365, '이 날 수만큼 지각이 없으면 지각 감점을 통째로 리셋'),
  ('late_cap',         0,  '지각 감점 상한 (0 이면 상한 없음)')
on conflict (key) do nothing;

create or replace function private.pconf(p_key text, p_default numeric default 0)
returns numeric language sql stable as $$
  select coalesce((select val from private.penalty_conf where key = p_key), p_default);
$$;

/* ── 감점 기록 ── */
create table if not exists public.staff_penalty (
  id          bigserial primary key,
  staff_id    uuid not null references public.staff(id) on delete cascade,
  kind        text not null check (kind in ('cancel', 'late')),
  grade       text not null,                    -- cancel: m1|w2|w1   late: small|big
  points      numeric not null check (points >= 0),   -- 그때의 감점 (설정이 바뀌어도 안 흔들린다)
  at          date not null,                    -- 언제 있었던 일인가
  booking_id  uuid references public.bookings(id) on delete set null,
  note        text,
  waived      boolean not null default false,   -- 대표가 봐준 것 (기록은 남는다)
  waived_at   timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists staff_penalty_staff_idx on public.staff_penalty (staff_id, at desc);
alter table public.staff_penalty enable row level security;
-- 표를 직접 만질 일은 없다. 아래 함수로만 오간다
revoke all on table public.staff_penalty from anon, authenticated;
revoke all on sequence public.staff_penalty_id_seq from anon, authenticated;

/* ── 지금 유효한 감점이 얼마인가 ──
   취소 : 최근 cancel_valid_days 안의 것만
   지각 : 마지막 지각으로부터 late_reset_days 가 지났으면 **통째로 0**.
          아니면 (면제 뺀) 전부를 더한다. 상한이 켜져 있으면 거기서 멈춘다.
   ⚠ 「하나씩 만료」 가 아니다. 대표 지시는 «1년동안 지각없으면 리셋» —
     11개월마다 늦는 사람은 지워지지 않는다는 뜻이다. */
create or replace function private.penalty_of(p_staff_id uuid)
returns jsonb language plpgsql stable as $$
declare
  today date := (now() at time zone 'Asia/Seoul')::date;
  c_days int := private.pconf('cancel_valid_days', 30)::int;
  r_days int := private.pconf('late_reset_days', 365)::int;
  cap numeric := private.pconf('late_cap', 0);
  cancel_p numeric := 0; late_p numeric := 0; late_raw numeric := 0;
  last_late date; late_n int := 0; cancel_n int := 0;
begin
  select coalesce(sum(points), 0), count(*)
    into cancel_p, cancel_n
    from public.staff_penalty
   where staff_id = p_staff_id and kind = 'cancel' and not waived
     and at > today - c_days;

  select max(at), coalesce(sum(points), 0), count(*)
    into last_late, late_raw, late_n
    from public.staff_penalty
   where staff_id = p_staff_id and kind = 'late' and not waived;

  if last_late is null or (today - last_late) >= r_days then
    late_p := 0;                                  -- 리셋
  else
    late_p := late_raw;
    if cap > 0 then late_p := least(late_p, cap); end if;
  end if;

  return jsonb_build_object(
    'cancel', cancel_p, 'cancel_n', cancel_n,
    'late', late_p, 'late_n', late_n, 'late_raw', late_raw,
    'late_last', last_late,
    -- 리셋까지 며칠 남았나 (지각이 있고 아직 안 지워졌을 때만)
    'late_reset_in', case when last_late is null or (today - last_late) >= r_days then null
                          else r_days - (today - last_late) end,
    'total', cancel_p + late_p);
end$$;

/* ── 설문 점수에서 도착을 뺀다 ──
   남은 다섯으로 다시 100점을 만든다 (분모 tot 가 알아서 맞춘다).
   ⚠ 신부님 답(arrival)은 그대로 저장된다 — 점수 계산에서만 빠진다. */
create or replace function private.fb_score(f public.feedback)
returns numeric language sql immutable as $$
  select case when tot = 0 then null else round(got / tot * 100, 1) end
  from (
    select
      coalesce(f.kindness,  0) / 10.0 * 20
        + coalesce(f.requests,  0) / 10.0 * 10
        + coalesce(f.flow,      0) / 10.0 * 15
        + coalesce(f.family,    0) / 10.0 * 15
        + coalesce(f.recommend, 0) / 10.0 * 20                       as got,
      ((case when f.kindness  is null then 0 else 20 end)
        + (case when f.requests  is null then 0 else 10 end)
        + (case when f.flow      is null then 0 else 15 end)
        + (case when f.family    is null then 0 else 15 end)
        + (case when f.recommend is null then 0 else 20 end))::numeric as tot
  ) w;
$$;

/* ── 대표용 ── */
create or replace function public.admin_penalty_conf()
returns jsonb language plpgsql stable security definer set search_path=public, private, pg_temp as $$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_object_agg(key, jsonb_build_object('val', val, 'memo', memo)), '{}'::jsonb)
    into res from private.penalty_conf;
  return res;
end$$;
revoke all on function public.admin_penalty_conf() from public, anon;
grant execute on function public.admin_penalty_conf() to authenticated;

create or replace function public.admin_penalty_conf_set(p_patch jsonb)
returns jsonb language plpgsql security definer set search_path=public, private, pg_temp as $$
declare k text; v numeric;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  for k, v in select key, (value #>> '{}')::numeric from jsonb_each(p_patch) loop
    -- 없는 열쇠는 만들지 않는다 — 오타로 설정이 늘어나면 아무도 모른다
    if not exists (select 1 from private.penalty_conf where key = k) then
      raise exception 'unknown key %', k;
    end if;
    if v < 0 then raise exception 'negative %', k; end if;
    update private.penalty_conf set val = v where key = k;
  end loop;
  return public.admin_penalty_conf();
end$$;
revoke all on function public.admin_penalty_conf_set(jsonb) from public, anon;
grant execute on function public.admin_penalty_conf_set(jsonb) to authenticated;

-- 감점 하나 넣기. 점수는 설정에서 가져와 **그때 값으로 박아 둔다**
create or replace function public.admin_penalty_add(p_patch jsonb)
returns jsonb language plpgsql security definer set search_path=public, private, pg_temp as $$
declare sid uuid; k text; g text; d date; pts numeric; nid bigint;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  sid := nullif(p_patch->>'staff_id','')::uuid;
  k   := nullif(p_patch->>'kind','');
  g   := nullif(p_patch->>'grade','');
  d   := coalesce(nullif(p_patch->>'at','')::date, (now() at time zone 'Asia/Seoul')::date);
  if sid is null or not exists (select 1 from public.staff where id = sid) then
    raise exception 'staff not found';
  end if;
  pts := case
    when k = 'cancel' and g = 'm1' then private.pconf('cancel_1m', 3)
    when k = 'cancel' and g = 'w2' then private.pconf('cancel_2w', 5)
    when k = 'cancel' and g = 'w1' then private.pconf('cancel_1w', 8)
    when k = 'late'   and g = 'small' then private.pconf('late_small', 2)
    when k = 'late'   and g = 'big'   then private.pconf('late_big', 5)
    else null end;
  if pts is null then raise exception 'bad kind/grade % %', k, g; end if;

  insert into public.staff_penalty (staff_id, kind, grade, points, at, booking_id, note)
  values (sid, k, g, pts, d, nullif(p_patch->>'booking_id','')::uuid, nullif(p_patch->>'note',''))
  returning id into nid;
  return jsonb_build_object('ok', true, 'id', nid, 'points', pts);
end$$;
revoke all on function public.admin_penalty_add(jsonb) from public, anon;
grant execute on function public.admin_penalty_add(jsonb) to authenticated;

-- 면제 켜고 끄기 (지우지 않는다)
create or replace function public.admin_penalty_waive(p_id bigint, p_on boolean default true)
returns jsonb language plpgsql security definer set search_path=public, private, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.staff_penalty
     set waived = coalesce(p_on, true),
         waived_at = case when coalesce(p_on, true) then now() else null end
   where id = p_id;
  if not found then raise exception 'not found'; end if;
  return jsonb_build_object('ok', true);
end$$;
revoke all on function public.admin_penalty_waive(bigint, boolean) from public, anon;
grant execute on function public.admin_penalty_waive(bigint, boolean) to authenticated;

-- 잘못 넣었을 때만 지운다 (면제와 다르다 — 면제는 남기고, 이건 없던 일로)
create or replace function public.admin_penalty_del(p_id bigint)
returns jsonb language plpgsql security definer set search_path=public, private, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  delete from public.staff_penalty where id = p_id;
  if not found then raise exception 'not found'; end if;
  return jsonb_build_object('ok', true);
end$$;
revoke all on function public.admin_penalty_del(bigint) from public, anon;
grant execute on function public.admin_penalty_del(bigint) to authenticated;

-- 작가별 감점 요약 + 내역
create or replace function public.admin_penalties(p_staff_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public, private, pg_temp as $$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select jsonb_build_object(
    'sum', coalesce((select jsonb_object_agg(s.id::text, private.penalty_of(s.id))
                     from public.staff s where s.active), '{}'::jsonb),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'staff_id', p.staff_id, 'staff', st.name,
        'kind', p.kind, 'grade', p.grade, 'points', p.points, 'at', p.at,
        'waived', p.waived, 'note', p.note,
        'booking', case when b.id is null then null else jsonb_build_object(
          'id', b.id, 'name', b.contractor_name, 'date', b.wedding_date) end)
        order by p.at desc, p.id desc)
      from public.staff_penalty p
      join public.staff st on st.id = p.staff_id
      left join public.bookings b on b.id = p.booking_id
      where p_staff_id is null or p.staff_id = p_staff_id), '[]'::jsonb)
  ) into res;
  return res;
end$$;
revoke all on function public.admin_penalties(uuid) from public, anon;
grant execute on function public.admin_penalties(uuid) to authenticated;
