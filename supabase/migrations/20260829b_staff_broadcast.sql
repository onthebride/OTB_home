-- 전체 작가 공지 — 대표가 한 번 쓰면 작가들 캘린더 「알림」 칸에 뜨고 폰도 울린다.
-- 대표 요청 2026-08-29 «전체 작가 공지 캘린더로 할 수 있게 해줘».
--   ① 어디서 — 관리자 화면 「작가」 메뉴
--   ② 누구에게 — «활성화되고, 스케줄이 하나라도 있거나 받는 중인 작가 전부»
--   ③ 폰 알림 — 보낸다
--   ④ 알림톡 — 안 한다 (대표 «알림톡 안하려고 하는것»)
--
-- ⚠ 「스케줄이 하나라도 있거나」는 **앞으로 잡힌 예식**으로 읽었다.
--   지난 예식만 있고 지금은 쉬는 분에게까지 공지가 갈 이유는 없다.
--   (오늘 예식은 포함한다 — 오늘 나가는 사람이야말로 봐야 한다)
--
-- ⚠ 캘린더에 남기는 것과 폰으로 보내는 것을 **같은 자리에서** 한다.
--   따로 만들면 한쪽만 나가는 날이 온다 (20260827h 의 교훈).
--
-- ⚠ kind 는 'notice' 다. 지금까지는 'change' | 'cancel' 뿐이었다 —
--   그 둘은 예약에 딸려 있어 booking_id 가 있지만 공지는 없다(null).

-- ===== 받을 사람 =====
-- 보내기 전에 관리자 화면이 먼저 이걸로 «누구에게 갑니다» 를 보여준다.
create or replace function public.admin_staff_notice_targets()
returns jsonb language plpgsql stable security definer
set search_path = public, private, pg_temp as $fn$
declare today date := (now() at time zone 'Asia/Seoul')::date; res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;

  select coalesce(jsonb_agg(t order by t.name), '[]'::jsonb) into res from (
    select st.id, st.name, st.accepting,
           (select count(*) from public.bookings b
            where b.status <> '취소' and b.wedding_date >= today
              and st.id in (b.assignee_id, b.sub_assignee_id)) as upcoming
    from public.staff st
    where coalesce(st.active, false)
      and (coalesce(st.accepting, false)
           or exists (select 1 from public.bookings b
                      where b.status <> '취소' and b.wedding_date >= today
                        and st.id in (b.assignee_id, b.sub_assignee_id)))
  ) t;
  return res;
end$fn$;
revoke all on function public.admin_staff_notice_targets() from public, anon;
grant execute on function public.admin_staff_notice_targets() to authenticated;

-- ===== 보내기 =====
create or replace function public.admin_staff_notice_send(p_title text, p_body text)
returns jsonb language plpgsql security definer
set search_path = public, private, pg_temp as $fn$
declare
  today date := (now() at time zone 'Asia/Seoul')::date;
  ttl text := btrim(coalesce(p_title, ''));
  bdy text := btrim(coalesce(p_body, ''));
  r record; n int := 0; names text := '';
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if ttl = '' then raise exception '제목을 적어주세요'; end if;
  if bdy = '' then raise exception '내용을 적어주세요'; end if;
  -- 폰 알림은 길면 잘린다. 여기서 막아 «보냈는데 반만 보이는» 일을 없앤다
  if length(ttl) > 60 then raise exception '제목은 60자까지입니다 (지금 %자)', length(ttl); end if;
  if length(bdy) > 1000 then raise exception '내용은 1000자까지입니다 (지금 %자)', length(bdy); end if;

  for r in
    select st.id, st.name
    from public.staff st
    where coalesce(st.active, false)
      and (coalesce(st.accepting, false)
           or exists (select 1 from public.bookings b
                      where b.status <> '취소' and b.wedding_date >= today
                        and st.id in (b.assignee_id, b.sub_assignee_id)))
    order by st.name
  loop
    -- ① 캘린더에 남긴다 — 폰 알림이 못 가도 이건 남는다
    insert into public.staff_notice(staff_id, booking_id, kind, title, body)
    values (r.id, null, 'notice', '📢 ' || ttl, bdy);

    -- ② 폰으로도 보낸다. 눌렀을 때 제 캘린더로 가야 하므로 작가ID를 실어준다
    perform private.otb_push('📢 ' || ttl, bdy, '/staff-calendar?s=' || r.id::text, r.id);

    n := n + 1;
    names := names || case when names = '' then '' else ', ' end || coalesce(r.name, '');
  end loop;

  return jsonb_build_object('ok', true, 'n', n, 'names', names);
end$fn$;
revoke all on function public.admin_staff_notice_send(text, text) from public, anon;
grant execute on function public.admin_staff_notice_send(text, text) to authenticated;
