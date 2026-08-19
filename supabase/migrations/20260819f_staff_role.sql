-- 작가에 메인/서브 구분을 넣는다.
-- 지금까지는 이름에 "(서브)" 를 붙인 게 전부여서, 날짜 조회 추천이
-- '최근 배정 적은 순'으로 서브 전용 작가를 메인 후보 위로 올리는 문제가 있었다.
--
-- 하나만 고르는 방식(메인 아니면 서브)은 맞지 않는다. 양재훈 작가는 메인 38건·서브 1건으로
-- 둘 다 하기 때문. 그래서 '메인 가능' / '서브 가능' 두 칸으로 둔다.
--
-- 초기값(대표 확인):
--   이름에 (서브) 가 붙은 작가 → 서브만
--   양재훈                     → 둘 다
--   나머지                     → 메인만
-- 새로 등록하는 작가는 둘 다 켜진 상태로 시작한다(빠뜨려서 못 고르는 일이 없게).
do $mig$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'staff' and column_name = 'can_main') then
    return;
  end if;

  alter table public.staff
    add column can_main boolean not null default true,
    add column can_sub  boolean not null default true;

  update public.staff set can_main = false, can_sub = true  where position('(서브)' in coalesce(name, '')) > 0;
  update public.staff set can_main = true,  can_sub = false
   where position('(서브)' in coalesce(name, '')) = 0
     and coalesce(name, '') <> '양재훈';
  update public.staff set can_main = true,  can_sub = true   where coalesce(name, '') = '양재훈';
end
$mig$;

-- 작가 저장 — 메인/서브 칸 추가. null 로 오면 그 칸은 건드리지 않는다.
drop function if exists public.admin_staff_update(uuid, text, text, boolean, boolean, text);
create or replace function public.admin_staff_update(
  p_id uuid, p_name text, p_phone text, p_active boolean, p_rep boolean,
  p_color text default null, p_can_main boolean default null, p_can_sub boolean default null)
returns public.staff language plpgsql security definer set search_path = public, pg_temp
as $$ declare r public.staff; begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if coalesce(p_rep, false) then
    update public.staff set is_rep = false where id <> p_id;  -- 대표는 1명만
  end if;
  update public.staff set
       name     = nullif(p_name, ''),
       phone    = nullif(p_phone, ''),
       active   = coalesce(p_active, true),
       is_rep   = coalesce(p_rep, false),
       -- p_color: null=변경안함 / ''=자동(색 해제) / '#RRGGBB'=지정
       color    = case when p_color is null then color else nullif(p_color, '') end,
       can_main = coalesce(p_can_main, can_main),
       can_sub  = coalesce(p_can_sub,  can_sub)
   where id = p_id returning * into r;
  return r;
end; $$;
revoke all on function public.admin_staff_update(uuid, text, text, boolean, boolean, text, boolean, boolean) from public, anon;
grant execute on function public.admin_staff_update(uuid, text, text, boolean, boolean, text, boolean, boolean) to authenticated;

-- 날짜 조회 — 메인 기준으로 추천한다. 서브 전용 작가는 뒤로 빼고 따로 센다.
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
    select a.id, a.name, a.status, a.detail, st.can_main, st.can_sub,
           fb.avg as fb_avg, coalesce(fb.n, 0) as fb_n, coalesce(ld.n, 0) as load_n
    from a
    join public.staff st on st.id = a.id
    left join fb on fb.staff_id = a.id
    left join ld on ld.id = a.id
  )
  select jsonb_build_object(
    'the_date', p_date,
    'at_time', t,
    'ok_n',     (select count(*) from t2 where status = 'ok' and can_main),
    'ok_sub_n', (select count(*) from t2 where status = 'ok' and can_sub),
    'total_n',  (select count(*) from t2 where can_main),
    'fb_total', (select count(*) from public.feedback),
    'weddings', coalesce((select jsonb_agg(w order by w.wedding_time nulls last) from (
        select b.id, b.contractor_name, b.wedding_time, b.wedding_venue,
               ms.name as main_name, ss.name as sub_name
        from public.bookings b
        left join public.staff ms on ms.id = b.assignee_id
        left join public.staff ss on ss.id = b.sub_assignee_id
        where b.wedding_date = p_date and b.status <> '취소'
      ) w), '[]'::jsonb),
    -- 메인 가능한 작가가 먼저, 그 안에서 가능 → 평점 → 최근 배정 적은 순
    'staff', coalesce((select jsonb_agg(to_jsonb(x) order by
        (not x.can_main), (x.status <> 'ok'), x.fb_avg desc nulls last, x.load_n, x.name) from t2 x), '[]'::jsonb)
  ) into res;
  return res;
end$fn$;
revoke all on function public.admin_day_check(date, text) from public, anon;
grant execute on function public.admin_day_check(date, text) to authenticated;
