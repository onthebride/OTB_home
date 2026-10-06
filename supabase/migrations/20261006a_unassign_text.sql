/* 배정 해제 알림 글 — 「다른 작가님이 맡게 되었습니다」 → 「스케줄이 취소되었습니다」
   (대표 2026-10-06 «이거 다른 작가님이 맡게되었다는 말 말고 스케줄 취소되었다고 해주고»)

   빠진 작가님께는 그날 촬영이 없어진 것이 전부다. 누가 대신 가는지는 그분 일이 아니고,
   아직 아무도 안 정해졌는데 「다른 작가님이 맡게 되었다」 고 하면 틀린 말이 된다
   (2026-09-16 에 「작가 알림 구멍 셋」 의 ③ 으로 적어 둔 것이다).

   ⚠ 바뀌는 것은 그 글 한 줄뿐이다 — 누구에게 언제 가는지(90초 쉬고 3분마다 묶어 폰으로)는 그대로.
   ⚠ 살아 있는 정의를 pg_get_functiondef 로 받아 그 한 줄만 바꿨다 (.backups/tests/pgrun/_unassign_text_patch.mjs).
   ⚠ 이미 나가서 아직 안 읽은 해제 알림도 같은 말로 고친다 — 화면에 옛말이 남아 있으면 「안 고쳐졌다」 로 보인다.
     읽은 것(지난 소식)은 그대로 둔다 */

CREATE OR REPLACE FUNCTION private.assign_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'private', 'public', 'pg_temp'
AS $function$
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
      line || E'\n스케줄이 취소되었습니다.', null);
  end loop;

  return new;
end$function$;

-- 아직 안 읽은 해제 알림의 글도 같은 말로 (읽은 것은 그대로)
update public.staff_notice
   set body = replace(body, E'\n이 예식은 다른 작가님이 맡게 되었습니다.', E'\n스케줄이 취소되었습니다.')
 where kind = 'unassign' and read_at is null
   and body like '%다른 작가님이 맡게 되었습니다.%';
