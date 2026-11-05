/* 작가 캘린더 구독 — 일정에 신랑신부 이름을 싣는다 (대표 2026-11-02 «신랑신부 이름 넣어 / 다른작가도 일단 공개 하자»)
   대표가 아이폰에 넣어 써 보신 뒤 정하셨다. 연락처는 여전히 싣지 않는다 — 작가 캘린더에서 본다.
   staff_cal_feed 만 바꾼다. 나머지(열쇠·받아 간 기록)는 20261028a 그대로 */
create or replace function public.staff_cal_feed(p_token text, p_client text default 'other', p_ua text default null)
returns jsonb language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  sid uuid;
  today date := (now() at time zone 'Asia/Seoul')::date;
  cl text;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{32}$' then return null; end if;
  select f.staff_id into sid from private.staff_cal_feed f where f.token = p_token;
  if sid is null then return null; end if;

  cl := case when p_client in ('google', 'apple', 'naver') then p_client else 'other' end;
  insert into private.staff_cal_fetch as x (staff_id, client, last_ua) values (sid, cl, left(p_ua, 200))
  on conflict (staff_id, client) do update set last_at = now(), n = x.n + 1, last_ua = left(p_ua, 200);

  return jsonb_build_object('events', coalesce((
    select jsonb_agg(jsonb_build_object(
             /* 일정 번호 — 예약 번호를 그대로 쓰지 않는다. 예약 번호는 신부님 포털 열쇠다.
                구독한 일정은 구글·애플·네이버 서버에 남으므로 거기 열쇠가 남으면 안 된다.
                늘 같은 값이라야 시각이 바뀐 일정이 새 일정이 아니라 같은 일정으로 잡힌다 */
             'id', md5('otb-cal:' || b.id::text),
             'date', b.wedding_date,
             'time', b.wedding_time,
             'venue', b.wedding_venue,
             'role', case when b.assignee_id = sid then '메인' else '서브' end,
             'reception', coalesce(b.option_reception, false),
             'pyebaek', coalesce(b.option_pyebaek, false),
             'part2', coalesce(b.option_part2, false),
             'two', coalesce(b.photographer = '2인 촬영', false),
             'pick', coalesce(b.pick_pin = sid, false),
             'rep', coalesce(b.rep_designation, false),
             'peer_role', pr.peer->>'peer_role',
             'peer_name', pr.peer->>'peer_name',
             -- 신랑신부 이름 (대표 2026-11-02 «신랑신부 이름 넣어»). 연락처는 여전히 안 싣는다
             'groom', nullif(trim(b.groom_name), ''),
             'bride', nullif(trim(b.bride_name), ''))
           order by b.wedding_date, b.wedding_time)
    from public.bookings b
    cross join lateral (select private.peer_of(b, sid) as peer) pr
    where (b.assignee_id = sid or b.sub_assignee_id = sid)
      and b.status <> '취소'
      and b.wedding_date >= today - 60), '[]'::jsonb));
end$$;
revoke all on function public.staff_cal_feed(text, text, text) from public;
grant execute on function public.staff_cal_feed(text, text, text) to anon, authenticated;
