-- 공지 받을 사람을 바꾼다 (대표 2026-08-29
-- «공지는 활성작가 모두에게 가는걸로 하자 / 대신 스케줄 안받는걸 체크한 사람은 안나가는걸로»)
--
-- 어제 정한 것: 활성 + (받는 중 **이거나** 앞으로 예식이 있음)
-- 오늘 정한 것: 활성 + 받는 중                     ← 예식 조건을 뺀다
--
-- 즉 「스케줄 안 받기」를 켠 분은 앞으로 예식이 잡혀 있어도 공지를 안 받는다.
-- 쉬겠다고 하신 분께 회사 공지를 보내지 않는다는 뜻이다.
-- (⚠ 예식이 바뀌거나 취소되는 알림은 이것과 별개다 — 그건 배정된 사람에게 그대로 간다)

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
    where coalesce(st.active, false) and coalesce(st.accepting, false)
  ) t;
  return res;
end$fn$;
revoke all on function public.admin_staff_notice_targets() from public, anon;
grant execute on function public.admin_staff_notice_targets() to authenticated;

create or replace function public.admin_staff_notice_send(p_title text, p_body text)
returns jsonb language plpgsql security definer
set search_path = public, private, pg_temp as $fn$
declare
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
    where coalesce(st.active, false) and coalesce(st.accepting, false)
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
