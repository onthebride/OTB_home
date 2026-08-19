-- 날짜 조회 — "그날 배정 가능한 작가가 있나? 문의 온 예약을 받을 수 있나?"
-- 가능 여부 판단은 admin_staff_availability 하나만 쓴다(4시간 규칙이 두 군데로 갈라지면 안 된다).
-- 여기서는 거기에 촬영 후 설문 평점과 최근 배정 건수를 붙여 추천 순서를 만든다.
--   정렬: 가능한 사람 먼저 → 평점 높은 순(평가 없으면 뒤) → 최근 배정 적은 순 → 이름
-- 평점은 아직 응답이 몇 건 안 된다. 그래서 응답 수(fb_n)를 같이 내려보내 화면에서 밝힌다.
create or replace function public.admin_day_check(p_date date, p_time text default null)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare av jsonb; res jsonb; t text := nullif(btrim(coalesce(p_time, '')), '');
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_date is null then raise exception '날짜를 선택해 주세요'; end if;
  if t is not null and t !~ '^[0-2][0-9]:[0-5][0-9]$' then
    raise exception '시간을 HH:MM 형식으로 입력해 주세요';
  end if;

  av := public.admin_staff_availability(p_date, t);

  with a as (
    select * from jsonb_to_recordset(av) as x(id uuid, name text, status text, detail text)
  ), fb as (
    select staff_id, count(*)::int as n, round(avg(overall)::numeric, 2) as avg
    from public.feedback group by staff_id
  ), ld as (      -- 앞뒤 90일 배정 건수 — 평점이 같거나 없을 때 고르게 나누기 위한 참고
    select s.id, count(b.*)::int as n
    from public.staff s
    left join public.bookings b
      on (b.assignee_id = s.id or b.sub_assignee_id = s.id)
     and b.status <> '취소'
     and b.wedding_date between p_date - 90 and p_date + 90
    group by s.id
  ), t2 as (
    select a.id, a.name, a.status, a.detail,
           fb.avg as fb_avg, coalesce(fb.n, 0) as fb_n, coalesce(ld.n, 0) as load_n
    from a left join fb on fb.staff_id = a.id left join ld on ld.id = a.id
  )
  select jsonb_build_object(
    'the_date', p_date,
    'at_time', t,
    'ok_n', (select count(*) from t2 where status = 'ok'),
    'total_n', (select count(*) from t2),
    'fb_total', (select count(*) from public.feedback),
    'weddings', coalesce((select jsonb_agg(w order by w.wedding_time nulls last) from (
        select b.id, b.contractor_name, b.wedding_time, b.wedding_venue,
               ms.name as main_name, ss.name as sub_name
        from public.bookings b
        left join public.staff ms on ms.id = b.assignee_id
        left join public.staff ss on ss.id = b.sub_assignee_id
        where b.wedding_date = p_date and b.status <> '취소'
      ) w), '[]'::jsonb),
    'staff', coalesce((select jsonb_agg(to_jsonb(x) order by
        (x.status <> 'ok'), x.fb_avg desc nulls last, x.load_n, x.name) from t2 x), '[]'::jsonb)
  ) into res;
  return res;
end$fn$;
revoke all on function public.admin_day_check(date, text) from public, anon;
grant execute on function public.admin_day_check(date, text) to authenticated;
