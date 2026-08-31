-- 배정되면 작가에게 알린다 (대표 2026-08-31)
--
--   «작가에게 스케줄이 새로 배정되면 그 작가 스케줄에 등록되고 알림으로 내용 표시되게 해줘
--     지금은 배정하고 모아서 복사해서 카톡으로 붙였는데
--     캘린더로 그 내용을 확인할 수 있게 통합하고 싶어»
--
-- 지금까지 배정은 예약 줄에 작가만 바뀌고 끝이었다. 작가 알림함에도 안 남고 폰에도 안 갔다.
-- 그래서 대표가 손으로 카톡에 붙여 넣고 계셨다.
--
-- ⚠ **배정 칸에 건다.** 배정 감사 기록(trg_assignment_audit_upd)이 붙어 있는 바로 그 자리다.
--   그래야 어느 길로 배정하든 다 잡힌다 — 월별 일정에서 한꺼번에, 예약 상세에서 하나,
--   되돌리기, 내가 SQL 로 고칠 때까지.
--   `update of assignee_id, sub_assignee_id` 라 다른 칸을 고칠 때는 안 깨어난다.
--
-- ⚠ 스무 건을 한꺼번에 배정하면 폰이 스무 번 울리면 안 된다.
--   **알림함에는 건별로 남기고, 폰은 3분 뒤 크론이 모아서 한 통** 보낸다.
--   건별로 남기는 것은 작가가 「어느 예식이 왔는지」를 하나씩 봐야 하기 때문이고,
--   폰을 모으는 것은 스무 번 울리면 아무도 안 보기 때문이다.
--
-- ⚠ 지난 예식은 안 알린다 (예식이 지나고 배정을 정리하는 일이 있다).
-- ⚠ 취소된 예식도 안 알린다.
-- ⚠ 대표가 대표 자신에게 배정한 것은 폰을 안 울린다 — 본인이 방금 한 일이다.
--   («나한테도 톡 주고» 는 월요일 주간 톡 이야기였다. 이건 즉시 알림이라 다르다)

/* 아직 폰으로 안 보낸 알림을 표시해 둔다. 크론이 이것만 모아서 보낸다.
   ⚠ 기본값을 now() 로 둔다 — 「이미 보냈다」가 기본이다.
     예식 변경·취소·공지·자동멈춤은 **제 자리에서 그때 바로** 폰을 울린다. 그것들까지
     크론이 다시 보내면 같은 알림이 두 번 간다. 모아서 보낼 것만 null 로 넣는다
     (private.assign_notify 가 그렇게 넣는다). */
alter table public.staff_notice add column if not exists pushed_at timestamptz default now();
create index if not exists staff_notice_topush
  on public.staff_notice (staff_id, created_at) where pushed_at is null;

/* ===== 배정이 바뀌면 알림함에 남긴다 ===== */
create or replace function private.assign_notify()
returns trigger language plpgsql security definer
set search_path to 'private', 'public', 'pg_temp' as $$
declare
  today date := (now() at time zone 'Asia/Seoul')::date;
  line text;
  -- 한 사람에게 두 번 알리지 않는다 (메인에서 서브로 옮겨도 «배정» 한 번)
  added uuid[] := '{}';
  gone  uuid[] := '{}';
  who uuid; nm text; rep boolean;
begin
  -- 지난 예식·취소된 예식은 알릴 것이 없다
  if new.wedding_date is null or new.wedding_date < today then return new; end if;
  if new.status = '취소' then return new; end if;

  if tg_op = 'INSERT' then
    added := array_remove(array[new.assignee_id, new.sub_assignee_id], null);
  else
    if new.assignee_id is distinct from old.assignee_id then
      if new.assignee_id is not null then added := added || new.assignee_id; end if;
      if old.assignee_id is not null then gone := gone || old.assignee_id; end if;
    end if;
    if new.sub_assignee_id is distinct from old.sub_assignee_id then
      if new.sub_assignee_id is not null then added := added || new.sub_assignee_id; end if;
      if old.sub_assignee_id is not null then gone := gone || old.sub_assignee_id; end if;
    end if;
  end if;

  -- 메인↔서브로 자리만 바뀐 사람은 «빠짐» 이 아니다
  gone := array(select x from unnest(gone) x where not (x = any(added)));
  added := array(select distinct x from unnest(added) x);

  if array_length(added, 1) is null and array_length(gone, 1) is null then return new; end if;
  line := private.wedding_line(new);

  /* pushed_at 을 null 로 넣으면 3분 뒤 크론이 모아서 폰으로 보낸다.
     ⚠ 대표는 예외다 — 배정을 방금 본인이 한 것이라 폰이 울릴 까닭이 없다.
       («나한테도 톡 주고» 는 월요일 주간 톡 이야기였다. 이건 즉시 알림이라 다르다)
       알림함에는 그대로 남긴다. 대표도 작가로 나가시니 「내 예식」 목록은 같아야 한다 */
  foreach who in array added loop
    select st.name, coalesce(st.is_rep, false) into nm, rep
      from public.staff st where st.id = who and coalesce(st.active, false);
    if nm is null then continue; end if;
    insert into public.staff_notice(staff_id, booking_id, kind, title, body, pushed_at)
    values (who, new.id, 'assign', '📌 새 예식이 배정되었습니다',
      line || E'\n' || (case when new.assignee_id = who then '메인작가' else '서브작가' end)
           || '로 배정되었습니다.',
      case when rep then now() end);
  end loop;

  foreach who in array gone loop
    select st.name, coalesce(st.is_rep, false) into nm, rep
      from public.staff st where st.id = who and coalesce(st.active, false);
    if nm is null then continue; end if;
    insert into public.staff_notice(staff_id, booking_id, kind, title, body, pushed_at)
    values (who, new.id, 'unassign', '↩ 배정이 해제되었습니다',
      line || E'\n이 예식은 다른 작가님이 맡게 되었습니다.',
      case when rep then now() end);
  end loop;

  return new;
end$$;
revoke all on function private.assign_notify() from public, anon, authenticated;

drop trigger if exists trg_assign_notify_ins on public.bookings;
drop trigger if exists trg_assign_notify_upd on public.bookings;
create trigger trg_assign_notify_ins after insert on public.bookings
  for each row execute function private.assign_notify();
create trigger trg_assign_notify_upd after update of assignee_id, sub_assignee_id on public.bookings
  for each row execute function private.assign_notify();

/* ===== 폰은 모아서 한 통 =====
   3분마다 돈다. 아직 안 보낸 알림을 작가별로 묶어 한 통씩 보낸다.
   ⚠ 한 건이면 그 내용을 그대로, 여럿이면 «3건» 으로 줄여 말한다 —
     폰 알림에 예식 셋을 다 적으면 잘려서 아무것도 안 보인다 */
create or replace function private.notice_push_flush()
returns jsonb language plpgsql security definer
set search_path to 'private', 'public', 'extensions', 'pg_temp' as $$
declare r record; n int := 0; ttl text; msg text;
begin
  for r in
    select n.staff_id, count(*)::int cnt, min(n.title) one_title, min(n.body) one_body,
           array_agg(n.id) ids
      from public.staff_notice n
      join public.staff st on st.id = n.staff_id and coalesce(st.active, false)
     where n.pushed_at is null
       -- 갓 만들어진 것은 한 번 쉰다. 한꺼번에 배정하는 중일 수 있다
       and n.created_at <= now() - interval '90 seconds'
     group by n.staff_id
  loop
    if r.cnt = 1 then
      ttl := r.one_title; msg := r.one_body;
    else
      ttl := '📌 확인하실 것이 ' || r.cnt || '건 있습니다';
      msg := '캘린더 「확인」 칸에서 보실 수 있어요.';
    end if;
    perform private.otb_push(ttl, msg, '/staff-calendar?s=' || r.staff_id::text, r.staff_id);
    update public.staff_notice set pushed_at = now() where id = any(r.ids);
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'sent', n);
end$$;
revoke all on function private.notice_push_flush() from public, anon, authenticated;

/* 지금까지 쌓인 것은 보내지 않는다 — 옛 알림이 한꺼번에 울리면 놀라신다 */
update public.staff_notice set pushed_at = now() where pushed_at is null;

do $do$
declare jid bigint;
begin
  select jobid into jid from cron.job where command like '%notice_push_flush%';
  if jid is null then
    perform cron.schedule('otb-notice-push', '*/3 * * * *', 'select private.notice_push_flush();');
    raise notice '배정 알림 묶어 보내기를 새로 걸었다 (3분마다)';
  else
    perform cron.alter_job(jid, schedule => '*/3 * * * *');
    raise notice '배정 알림 묶어 보내기(jobid %) 시각을 맞췄다', jid;
  end if;
end$do$;
