-- ============================================
-- 관리자 "할 일" 리마인더 (폰 푸시 + 대시보드 상단 배너)
--  ① 매주 월요일 → 작가 스케줄 체크
--  ② 예식 하루 전 → 설문 공유 (예식 있는 날마다 자동, 예약별 1건)
-- 매일 06:00 KST(=21:00 UTC) pg_cron 이 생성 + otb_push 발송.
-- 대시보드는 미확인(dismissed=false) 건을 상단 배너로 노출, '확인' 누르면 숨김.
-- ============================================
create table if not exists public.admin_reminders (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null,                       -- 'weekly_schedule' | 'survey_share'
  due_date     date not null,                       -- KST 기준 발생일
  booking_id   uuid references public.bookings(id) on delete cascade,
  title        text not null,
  body         text,
  url          text not null default '/admin',
  dismissed    boolean not null default false,
  dismissed_at timestamptz,
  created_at   timestamptz not null default now()
);
alter table public.admin_reminders enable row level security;  -- 직접접근 차단(관리자는 RPC 경유)

-- 중복 방지: 같은 종류+날짜+예약 조합은 1건만 (booking_id NULL 도 유일하게)
create unique index if not exists admin_reminders_uniq
  on public.admin_reminders (kind, due_date, coalesce(booking_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index if not exists admin_reminders_pending_idx on public.admin_reminders (dismissed, due_date desc);

-- ============================================
-- 리마인더 생성 (매일 cron). 새로 생긴 건에 대해서만 푸시(중복푸시 방지).
-- ============================================
create or replace function private.generate_admin_reminders()
returns int language plpgsql security definer set search_path=private, public, extensions, pg_temp as $$
declare
  today_kst date := (now() at time zone 'Asia/Seoul')::date;
  r record;
  wk_cnt int;
  n_new int := 0;
  n_survey int := 0;
  survey_names text := '';
  who text;
begin
  -- 오래된 미확인 알림 자동 정리(생성 7일 경과분): 배너가 무한정 쌓이지 않게
  update public.admin_reminders
     set dismissed = true, dismissed_at = now()
   where not dismissed and due_date < today_kst - 7;

  -- ① 매주 월요일: 작가 스케줄 체크 (dow 1 = 월요일)
  if extract(dow from today_kst) = 1 then
    select count(*) into wk_cnt from public.bookings
      where status <> '취소' and wedding_date >= today_kst and wedding_date <= today_kst + 7;
    insert into public.admin_reminders (kind, due_date, title, body, url)
    values ('weekly_schedule', today_kst, '작가 스케줄 체크',
            case when wk_cnt > 0 then '이번 주 예식 ' || wk_cnt || '건 — 작가 스케줄을 확인하세요.'
                 else '작가 스케줄을 확인하세요.' end,
            '/admin')
    on conflict do nothing;
    if found then
      n_new := n_new + 1;
      perform private.otb_push('🗓 작가 스케줄 체크',
        case when wk_cnt > 0 then '이번 주 예식 ' || wk_cnt || '건 — 작가 스케줄을 확인하세요.'
             else '작가 스케줄을 확인하세요.' end, '/admin');
    end if;
  end if;

  -- ② 예식 하루 전: 설문 공유 (예식 = 내일, KST) — 예약별 1건
  for r in
    select b.id, b.contractor_name, b.bride_name, b.wedding_venue, b.wedding_time
    from public.bookings b
    where b.status <> '취소' and b.wedding_date = today_kst + 1
    order by b.wedding_time nulls last
  loop
    who := coalesce(nullif(r.contractor_name,''), nullif(r.bride_name,''), '고객');
    insert into public.admin_reminders (kind, due_date, booking_id, title, body, url)
    values ('survey_share', today_kst, r.id, '설문 공유 (내일 예식)',
            who || coalesce(' · ' || nullif(r.wedding_venue,''), ''), '/admin')
    on conflict do nothing;
    if found then
      n_new := n_new + 1;
      n_survey := n_survey + 1;
      survey_names := survey_names || case when survey_names = '' then '' else ', ' end || who;
    end if;
  end loop;

  if n_survey > 0 then
    perform private.otb_push('📋 설문 공유 (내일 예식)',
      '내일 예식 ' || n_survey || '건 · ' || survey_names || ' — 설문을 공유하세요.', '/admin');
  end if;

  return n_new;
end$$;
revoke all on function private.generate_admin_reminders() from public, anon, authenticated;

-- 매일 06:00 KST(=21:00 UTC) cron 등록 (pg_cron 있을 때만)
do $cron_rem$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'otb-admin-reminders') then
      perform cron.unschedule('otb-admin-reminders');
    end if;
    perform cron.schedule('otb-admin-reminders', '0 21 * * *', 'select private.generate_admin_reminders();');
  else
    raise notice 'pg_cron 미설치 — 대시보드에서 활성화 후 재실행 필요';
  end if;
end$cron_rem$;

-- ============================================
-- 관리자 RPC: 목록 / 확인(개별) / 전체확인
-- ============================================
create or replace function public.admin_reminders_list()
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'due_date', due_date, 'booking_id', booking_id,
    'title', title, 'body', body, 'url', url
  ) order by due_date desc, kind, created_at), '[]'::jsonb)
  into res from public.admin_reminders where not dismissed;
  return res;
end$$;
revoke all on function public.admin_reminders_list() from public, anon;
grant execute on function public.admin_reminders_list() to authenticated;

create or replace function public.admin_reminder_dismiss(p_id uuid)
returns void language plpgsql security definer set search_path=public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.admin_reminders set dismissed = true, dismissed_at = now() where id = p_id;
end$$;
revoke all on function public.admin_reminder_dismiss(uuid) from public, anon;
grant execute on function public.admin_reminder_dismiss(uuid) to authenticated;

create or replace function public.admin_reminders_dismiss_all()
returns void language plpgsql security definer set search_path=public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.admin_reminders set dismissed = true, dismissed_at = now() where not dismissed;
end$$;
revoke all on function public.admin_reminders_dismiss_all() from public, anon;
grant execute on function public.admin_reminders_dismiss_all() to authenticated;
