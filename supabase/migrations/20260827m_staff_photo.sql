-- 캘린더 머리말 개편 + 다음 촬영에 신랑·신부 (대표 요청 2026-08-27)
-- «로고는 왼쪽에 오른쪽에 김병훈 작가님 넣고 프로필 사진 하나 넣을 수 있게 되나?»
-- «다음 촬영 카드 뜨는거 신랑 신부 이름 연락처도 넣어줘»
--
-- ⚠ 사진은 **대표가 관리자에서 올린다.** 작가는 로그인이 없어서 저장소에 못 쓴다 —
--   작가에게 올리기를 열어주려면 anon 쓰기 길을 새로 내야 하는데, 그건 대가가 크다.
--   작가 얼굴은 나중에 「지정 촬영」 화면에도 쓸 것이라 대표가 고르는 편이 맞다.

alter table public.staff add column if not exists photo_url text;

-- 갤러리 버킷(공개)에 올린 주소만 받는다. 아무 주소나 받으면 남의 그림을 끼워 넣을 수 있다
alter table public.staff drop constraint if exists staff_photo_url_ok;
alter table public.staff add constraint staff_photo_url_ok
  check (photo_url is null or photo_url ~ '^https://[a-z0-9.-]+/storage/v1/object/public/gallery/');

create or replace function public.staff_calendar(p_staff_id uuid, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path=public, pg_temp as $$
declare st public.staff; res jsonb;
begin
  select * into st from public.staff where id = p_staff_id;
  if not found then return null; end if;
  if p_to < p_from or p_to > p_from + 400 then raise exception 'bad range'; end if;

  select jsonb_build_object(
    'staff_name', st.name,
    'staff_photo', st.photo_url,
    'from', p_from, 'to', p_to,
    -- 다음 촬영 (보고 있는 달과 무관하게 오늘 이후 첫 예식)
    'next', (select jsonb_build_object(
          'booking_id', b.id, 'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time,
          'wedding_venue', b.wedding_venue,
          'role', case when b.assignee_id = p_staff_id then '메인' else '서브' end,
          'bride_name', b.bride_name, 'groom_name', b.groom_name,
          -- ⚠ 연락처는 예식 2주 전부터만. 날짜 칸과 같은 규칙이라야 한다
          'bride_phone', case when b.wedding_date <= current_date + 14 then b.bride_phone end,
          'groom_phone', case when b.wedding_date <= current_date + 14 then b.groom_phone end,
          'days', (b.wedding_date - (now() at time zone 'Asia/Seoul')::date))
        from public.bookings b
        where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
          and b.status <> '취소'
          and b.wedding_date >= (now() at time zone 'Asia/Seoul')::date
        order by b.wedding_date, b.wedding_time
        limit 1),
    'bookings', coalesce((select jsonb_agg(x order by x->>'wedding_date', x->>'wedding_time') from (
        select jsonb_build_object(
          'booking_id', b.id, 'wedding_date', b.wedding_date, 'wedding_time', b.wedding_time,
          'wedding_venue', b.wedding_venue,
          'role', case when b.assignee_id = p_staff_id then '메인' else '서브' end,
          'bride_name', b.bride_name, 'groom_name', b.groom_name,
          'bride_phone', case when b.wedding_date <= current_date + 14 then b.bride_phone end,
          'groom_phone', case when b.wedding_date <= current_date + 14 then b.groom_phone end,
          'option_reception', b.option_reception, 'option_pyebaek', b.option_pyebaek,
          'option_part2', b.option_part2, 'photographer', b.photographer, 'rep_designation', b.rep_designation,
          -- 신부가 촬영 설문을 냈는지. 냈으면 캘린더에서 바로 열 수 있게 한다
          'has_survey', exists(select 1 from public.surveys s where s.booking_id = b.id)
        ) as x
        from public.bookings b
        where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
          and b.status <> '취소' and b.wedding_date between p_from and p_to) t), '[]'::jsonb),
    'busy', coalesce((select jsonb_agg(jsonb_build_object(
          'id', sb.id, 'the_date', sb.the_date, 'kind', sb.kind,
          'at_time', sb.at_time, 'place', sb.place, 'note', sb.note,
          'title', sb.title, 'all_day', sb.all_day, 'group_id', sb.group_id,
          -- 묶음이면 전체가 언제부터 언제까지인지 (달력 범위 밖까지 포함해서 센다)
          'g_from', g.g_from, 'g_to', g.g_to, 'g_n', g.g_n)
          order by sb.the_date, sb.all_day desc, sb.at_time)
        from public.staff_busy sb
        left join lateral (
          select min(o.the_date) g_from, max(o.the_date) g_to, count(*)::int g_n
          from public.staff_busy o
          where o.group_id = sb.group_id and o.staff_id = sb.staff_id
        ) g on sb.group_id is not null
        where sb.staff_id = p_staff_id and sb.the_date between p_from and p_to), '[]'::jsonb)
  ) into res;
  return res;
end$$;

-- 관리자: 작가 사진 넣고 빼기 (대표만)
drop function if exists public.admin_staff_photo(uuid, text);
create or replace function public.admin_staff_photo(p_staff_id uuid, p_url text)
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.staff set photo_url = nullif(trim(coalesce(p_url, '')), '') where id = p_staff_id;
  if not found then raise exception 'staff not found'; end if;
  return jsonb_build_object('ok', true,
    'photo_url', (select photo_url from public.staff where id = p_staff_id));
end$$;
revoke all on function public.admin_staff_photo(uuid, text) from public, anon;
grant execute on function public.admin_staff_photo(uuid, text) to authenticated;
