-- 대표에게도 배정 알림을 보낸다 (대표 2026-08-31)
--   «근데 내 스케줄 배정했는데 알림이 안가는거 같아»
--
-- 안 간 게 맞다. 내가 일부러 막아뒀다 —
--   «대표가 대표 자신에게 배정한 것은 폰을 안 울린다. 본인이 방금 한 일이다» (20260831c)
--
-- 20:04~20:24 에 네 건을 대표 본인에게 배정하셨고, 알림함에는 넷 다 남았지만
-- 폰은 울리지 않았다(pushed_at 을 만들 때 바로 찍어 크론이 건너뛰게 했다).
--
-- 생각이 짧았다. 대표도 작가로 나가시고, 배정한 것과 폰에서 확인하는 것은 다른 일이다.
-- 주간 톡도 «나한테도 톡 주고» 로 대표를 안 걸러낸다 — 같은 결로 맞춘다.
-- 한꺼번에 배정해도 3분 크론이 한 통으로 묶어주므로 시끄러울 일도 없다.
--
-- ⚠ 되돌리려면 아래 두 줄의 `case when rep then now() end` 를 되살리면 된다.

create or replace function private.assign_notify()
returns trigger language plpgsql security definer
set search_path to 'private', 'public', 'pg_temp' as $$
declare
  today date := (now() at time zone 'Asia/Seoul')::date;
  line text;
  -- 한 사람에게 두 번 알리지 않는다 (메인에서 서브로 옮겨도 «배정» 한 번)
  added uuid[] := '{}';
  gone  uuid[] := '{}';
  who uuid; nm text;
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
     ⚠ 2026-08-31 까지는 대표만 빼고 있었다. 대표 «내 스케줄 배정했는데 알림이 안가는거 같아»
       로 되돌렸다 — 대표도 작가로 나가시고, 배정하는 일과 폰에서 확인하는 일은 다르다.
       한꺼번에 배정해도 크론이 한 통으로 묶어주므로 시끄럽지 않다 */
  foreach who in array added loop
    select st.name into nm from public.staff st
      where st.id = who and coalesce(st.active, false);
    if nm is null then continue; end if;
    insert into public.staff_notice(staff_id, booking_id, kind, title, body, pushed_at)
    values (who, new.id, 'assign', '📌 새 예식이 배정되었습니다',
      line || E'\n' || (case when new.assignee_id = who then '메인작가' else '서브작가' end)
           || '로 배정되었습니다.', null);
  end loop;

  foreach who in array gone loop
    select st.name into nm from public.staff st
      where st.id = who and coalesce(st.active, false);
    if nm is null then continue; end if;
    insert into public.staff_notice(staff_id, booking_id, kind, title, body, pushed_at)
    values (who, new.id, 'unassign', '↩ 배정이 해제되었습니다',
      line || E'\n이 예식은 다른 작가님이 맡게 되었습니다.', null);
  end loop;

  return new;
end$$;
revoke all on function private.assign_notify() from public, anon, authenticated;
