-- 예약·배정을 날마다 통째로 떠 두고, 설명 안 되는 차이가 있으면 알린다.
-- 대표 지시 2026-08-29
--   «스케줄 절대 지워지면 안됨 / 배정된거 내가 수정하는게아니면 절대 없어지면 안됨
--     매일 12시에 예약 이랑 배정 데이터 백업해놓고 원인없는 차이점이 있으면 보고해»
--
-- ===== 무엇을 «원인» 으로 보는가 =====
-- public.assignment_audit 에 배정이 바뀔 때마다 한 줄씩 남는다. 트리거로 걸려 있어
-- **누가 어떻게 바꾸든** 남는다 — 관리자 화면이든, 내가 SQL 로 만지든.
-- 그러니 「어제 있던 배정이 오늘 없는데 그 사이 감사 기록이 없다」면 설명이 안 되는 일이다.
-- 그때만 알린다. 대표가 관리자에서 손수 바꾼 것은 기록이 남으므로 조용하다.
--
-- ⚠ 예식일·상태가 바뀐 것은 «적어만 두고 알리지 않는다». 그건 날마다 있는 일이고
--   감사 기록이 따로 없어서, 알리기 시작하면 매일 울려 진짜 경보를 묻어버린다.
--
-- ===== 되살리는 법 (사고가 났을 때) =====
--   -- 8월 30일에 뜬 것으로 배정만 되돌린다
--   update public.bookings b set assignee_id = k.assignee_id, sub_assignee_id = k.sub_assignee_id
--   from private.booking_backup k
--   where k.taken_on = date '2026-08-30' and k.booking_id = b.id;
--   -- 사라진 예약이 무엇이었는지 본다
--   select * from private.booking_backup k where k.taken_on = date '2026-08-30'
--    and not exists (select 1 from public.bookings b where b.id = k.booking_id);

create table if not exists private.booking_backup (
  taken_on        date not null,
  booking_id      uuid not null,
  contractor_name text,
  bride_name      text,
  groom_name      text,
  wedding_date    date,
  wedding_time    text,
  wedding_venue   text,
  status          text,
  photographer    text,
  assignee_id     uuid,
  sub_assignee_id uuid,
  created_at      timestamptz,
  primary key (taken_on, booking_id)
);
comment on table private.booking_backup is
  '예약·배정을 날마다 통째로 떠 둔 것. 낮 12시 크론이 넣는다 (대표 2026-08-29)';
revoke all on table private.booking_backup from public, anon, authenticated;

-- 무엇이 달라졌는지 적어 두는 곳. 알린 것도 안 알린 것도 다 남긴다
create table if not exists private.backup_diff (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  taken_on    date not null,          -- 오늘 뜬 것
  prev_on     date not null,          -- 견준 어제 것
  booking_id  uuid,
  what        text not null,          -- 'gone' | 'assignee' | 'sub' | 'wedding_date' | 'status'
  was         text,
  now_        text,
  explained   boolean not null,       -- 감사 기록으로 설명이 되나
  note        text
);
create index if not exists backup_diff_at on private.backup_diff (at desc);
revoke all on table private.backup_diff from public, anon, authenticated;

create or replace function private.booking_backup_run(p_dry boolean default false)
returns jsonb language plpgsql security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $$
declare
  today date := (now() at time zone 'Asia/Seoul')::date;
  prev  date;
  since timestamptz;
  r record;
  n_rows int := 0; n_diff int := 0; n_bad int := 0;
  msgs text[] := '{}';
begin
  select max(k.taken_on) into prev from private.booking_backup k where k.taken_on < today;

  -- 오늘 것을 다시 뜬다 (두 번 돌아도 탈 없게)
  if not p_dry then
    delete from private.booking_backup k where k.taken_on = today;
    insert into private.booking_backup (taken_on, booking_id, contractor_name, bride_name, groom_name,
      wedding_date, wedding_time, wedding_venue, status, photographer,
      assignee_id, sub_assignee_id, created_at)
    select today, b.id, b.contractor_name, b.bride_name, b.groom_name,
      b.wedding_date, b.wedding_time, b.wedding_venue, b.status, b.photographer,
      b.assignee_id, b.sub_assignee_id, b.created_at
    from public.bookings b;
    get diagnostics n_rows = row_count;
  else
    select count(*) into n_rows from public.bookings;
  end if;

  if prev is null then
    return jsonb_build_object('ok', true, 'first', true, 'taken_on', today, 'rows', n_rows);
  end if;

  -- 어제 뜬 시각 이후의 감사 기록만 «설명» 으로 인정한다
  since := (prev::timestamp at time zone 'Asia/Seoul');

  for r in
    with p as (select * from private.booking_backup k where k.taken_on = prev)
    -- ① 예약이 통째로 사라졌다
    select p.booking_id, 'gone' as what,
           coalesce(p.contractor_name, '') || ' · ' || coalesce(p.wedding_date::text, '') as was,
           null::text as now_,
           exists (select 1 from public.assignment_audit a
                   where a.booking_id = p.booking_id and a.action = 'booking_deleted'
                     and a.at >= since) as explained
    from p where not exists (select 1 from public.bookings b where b.id = p.booking_id)
    union all
    -- ② 메인 배정이 달라졌다
    select p.booking_id, 'assignee',
           (select st.name from public.staff st where st.id = p.assignee_id),
           (select st.name from public.staff st where st.id = b.assignee_id),
           exists (select 1 from public.assignment_audit a
                   where a.booking_id = p.booking_id and a.field = 'assignee_id' and a.at >= since)
    from p join public.bookings b on b.id = p.booking_id
    where b.assignee_id is distinct from p.assignee_id
    union all
    -- ③ 서브 배정이 달라졌다
    select p.booking_id, 'sub',
           (select st.name from public.staff st where st.id = p.sub_assignee_id),
           (select st.name from public.staff st where st.id = b.sub_assignee_id),
           exists (select 1 from public.assignment_audit a
                   where a.booking_id = p.booking_id and a.field = 'sub_assignee_id' and a.at >= since)
    from p join public.bookings b on b.id = p.booking_id
    where b.sub_assignee_id is distinct from p.sub_assignee_id
    union all
    -- ④ 예식일이 바뀌었다 — 적어만 둔다 (감사 기록이 없는 갈래라 늘 «설명 안 됨» 이 된다)
    select p.booking_id, 'wedding_date', p.wedding_date::text, b.wedding_date::text, true
    from p join public.bookings b on b.id = p.booking_id
    where b.wedding_date is distinct from p.wedding_date
    union all
    -- ⑤ 상태가 바뀌었다 — 마찬가지로 적어만 둔다
    select p.booking_id, 'status', p.status, b.status, true
    from p join public.bookings b on b.id = p.booking_id
    where b.status is distinct from p.status
  loop
    n_diff := n_diff + 1;
    if not r.explained then n_bad := n_bad + 1; end if;
    if not p_dry then
      insert into private.backup_diff (taken_on, prev_on, booking_id, what, was, now_, explained, note)
      values (today, prev, r.booking_id, r.what, r.was, r.now_, r.explained,
              case when r.what in ('wedding_date', 'status') then '적어만 둠 (알리지 않는다)' end);
    end if;
  end loop;

  if n_bad > 0 then
    msgs := msgs || (n_bad || '건이 설명되지 않습니다');
    if not p_dry then
      perform private.otb_push('🚨 예약·배정이 까닭 없이 달라졌습니다',
        prev::text || ' 것과 견주어 ' || n_bad || '건 — 관리자에서 확인하세요. (백업은 남아 있습니다)',
        '/admin');
    end if;
  end if;

  -- 400일 넘은 것은 지운다. 하루 250줄 안팎이라 넉넉하다
  if not p_dry then
    delete from private.booking_backup k where k.taken_on < today - 400;
    delete from private.backup_diff d where d.at < now() - interval '400 days';
  end if;

  return jsonb_build_object('ok', n_bad = 0, 'dry', p_dry, 'taken_on', today, 'prev_on', prev,
    'rows', n_rows, 'diffs', n_diff, 'unexplained', n_bad, 'warnings', to_jsonb(msgs));
end$$;
revoke all on function private.booking_backup_run(boolean) from public, anon, authenticated;

-- 낮 12시 한국 (cron.timezone 이 GMT 라 3시로 적는다)
do $$
declare jid bigint;
begin
  select jobid into jid from cron.job where command like '%booking_backup_run%';
  if jid is null then
    perform cron.schedule('otb-booking-backup', '0 3 * * *', 'select private.booking_backup_run();');
    raise notice '예약 백업을 새로 걸었다 (한국 낮 12시)';
  else
    perform cron.alter_job(jid, schedule => '0 3 * * *');
    raise notice '예약 백업(jobid %) 시각을 맞췄다', jid;
  end if;
end $$;

-- 첫 백업을 지금 떠 둔다. 안 그러면 내일 낮까지 견줄 것이 없다
select private.booking_backup_run();
