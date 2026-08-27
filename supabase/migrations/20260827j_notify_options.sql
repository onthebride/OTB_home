-- 옵션이 바뀔 때도 알리고, 작가 폰 등록은 하나만 남긴다 (대표 요청 2026-08-27)
-- «연회장이나 폐백 2부등 촬영시간이 늘어나느거면 알림이 가야할거 같아»
-- «폰등록은 항상 하나로 갱신되게 해줘»

/* ===== ① 작가 폰 등록은 하나만 =====
   대표 폰에 4개가 쌓여 시험 알림이 네 번 왔다. 홈 화면에 다시 추가할 때마다
   브라우저가 **새 endpoint** 를 주기 때문이다 — 옛것은 살아 있어 계속 받는다.
   그래서 켤 때 **그 작가의 다른 등록을 지운다.** 마지막에 켠 기기 하나만 남는다.
   ⚠ 관리자(staff_id is null)는 건드리지 않는다 — 대표는 PC 와 폰에서 같이 본다. */
create or replace function public.save_push_subscription(
  p_endpoint text, p_p256dh text, p_auth text, p_staff_id uuid default null)
returns void language plpgsql security definer set search_path=public, pg_temp as $$
begin
  if p_endpoint is null or p_p256dh is null or p_auth is null then raise exception 'bad subscription'; end if;
  if p_staff_id is null then
    if auth.uid() is null then raise exception 'unauthorized'; end if;
  else
    if not exists (select 1 from public.staff where id = p_staff_id and coalesce(active, false)) then
      raise exception 'staff not found';
    end if;
    -- 작가는 한 기기만. 다른 데서 켜면 이전 것은 꺼진다
    delete from public.push_subscriptions
     where staff_id = p_staff_id and endpoint <> p_endpoint;
  end if;
  insert into public.push_subscriptions (endpoint, p256dh, auth, staff_id)
    values (p_endpoint, p_p256dh, p_auth, p_staff_id)
  on conflict (endpoint, staff_id) do update
    set p256dh = excluded.p256dh, auth = excluded.auth;
end$$;
revoke all on function public.save_push_subscription(text, text, text, uuid) from public;
grant execute on function public.save_push_subscription(text, text, text, uuid) to anon, authenticated;

-- 이미 쌓인 것 정리 — 작가마다 마지막에 켠 것 하나만 남긴다
delete from public.push_subscriptions p
where p.staff_id is not null
  and p.ctid <> (select q.ctid from public.push_subscriptions q
                 where q.staff_id = p.staff_id
                 order by coalesce(q.last_ok_at, q.created_at) desc, q.created_at desc
                 limit 1);

/* ===== ② 촬영이 길어지는 옵션이 바뀌면 알린다 =====
   대표 «연회장이나 폐백 2부등 촬영시간이 늘어나느거면 알림이 가야할거 같아».
   작가는 그날 몇 시간을 잡아둘지가 달라진다 — 날짜·시간·장소만큼 중요하다.
   ⚠ 앨범(option_album)은 뺀다. 작가가 할 일이 아니다 — 알려봐야 성가시기만 하다. */
create or replace function private.booking_change_notify()
returns trigger language plpgsql security definer
set search_path to 'private', 'public', 'pg_temp'
as $$
declare
  changed text[] := '{}';
  msg text; who uuid; nm text; ttl text;
  targets uuid[];
  -- 옵션 칸 이름 → 손님·작가가 부르는 이름
  opt_names text[] := array['연회장 인사촬영', '폐백촬영', '2부 촬영'];
  olds boolean[]; news boolean[]; i int;
begin
  -- 지난 예식은 알릴 것이 없다
  if coalesce(new.wedding_date, old.wedding_date) < (now() at time zone 'Asia/Seoul')::date then
    return new;
  end if;

  if new.status = '취소' and old.status is distinct from '취소' then
    changed := changed || '취소되었습니다'::text;
  else
    if new.wedding_date is distinct from old.wedding_date then
      changed := changed || ('날짜 ' || to_char(old.wedding_date, 'MM/DD') || ' → '
                             || to_char(new.wedding_date, 'MM/DD'))::text;
    end if;
    if new.wedding_time is distinct from old.wedding_time then
      changed := changed || ('시간 ' || coalesce(public.fmt_ktime(old.wedding_time), '-') || ' → '
                             || coalesce(public.fmt_ktime(new.wedding_time), '-'))::text;
    end if;
    if coalesce(nullif(trim(new.wedding_venue), ''), '') is distinct from coalesce(nullif(trim(old.wedding_venue), ''), '') then
      changed := changed || ('장소 ' || coalesce(old.wedding_venue, '-') || ' → '
                             || coalesce(new.wedding_venue, '-'))::text;
    end if;

    -- 촬영이 길어지는 옵션. 붙었는지 떨어졌는지를 그대로 적는다
    olds := array[coalesce(old.option_reception,false), coalesce(old.option_pyebaek,false), coalesce(old.option_part2,false)];
    news := array[coalesce(new.option_reception,false), coalesce(new.option_pyebaek,false), coalesce(new.option_part2,false)];
    for i in 1..3 loop
      if olds[i] is distinct from news[i] then
        changed := changed || (opt_names[i] || (case when news[i] then ' 추가' else ' 빠짐' end))::text;
      end if;
    end loop;

    -- 1인 ↔ 2인 촬영도 그날 판이 달라진다
    if coalesce(new.photographer,'') is distinct from coalesce(old.photographer,'') then
      changed := changed || ('촬영 ' || coalesce(nullif(old.photographer,''), '-') || ' → '
                             || coalesce(nullif(new.photographer,''), '-'))::text;
    end if;
  end if;

  if array_length(changed, 1) is null then return new; end if;

  -- 바뀌기 전·후에 걸쳐 있는 작가 모두에게 (배정이 함께 바뀌었을 수도 있다)
  targets := array(select distinct x from unnest(array[
    old.assignee_id, old.sub_assignee_id, new.assignee_id, new.sub_assignee_id]) x
    where x is not null);

  ttl := case when new.status = '취소' then '❌ 예식이 취소되었습니다'
              else '📅 예식 내용이 바뀌었습니다' end;

  foreach who in array targets loop
    select name into nm from public.staff where id = who and coalesce(active, false);
    if nm is null then continue; end if;
    msg := private.wedding_line(case when new.status = '취소' then old else new end)
           || E'\n' || array_to_string(changed, E'\n');

    -- ① 캘린더에 남긴다 — 폰 알림이 못 가도 이건 남는다
    insert into public.staff_notice(staff_id, booking_id, kind, title, body)
    values (who, new.id, case when new.status = '취소' then 'cancel' else 'change' end, ttl, msg);

    -- ② 폰으로도 보낸다
    perform private.otb_push(ttl, msg, '/staff-calendar?s=' || who::text, who);
  end loop;

  return new;
end$$;
