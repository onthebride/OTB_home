-- 이벤트 후기(신부가 블로그·카페에 올린 글)를 관리자 «통계» 에서 볼 수 있게 한다.
-- 대표 요청 2026-08-27 «우리 신부들이 이벤트 참여한 후기는 어디 모아지는데가 있어?» → «관리자 통계에 넣어줘»
--
-- 지금까지는 모이기만 하고 볼 데가 없었다. 홈의 [이벤트] 카드는 «승인 대기» 만 그리고,
-- 대기가 0건이면 카드째 접힌다. 승인하는 순간 화면에서 사라져 36건이 통째로 안 보이고 있었다.
--
-- ⚠ 표를 두 갈래로 나눠 센다. 섞으면 «후기 36건» 이 부풀려 보인다:
--   · link 가 있는 것            = 신부가 실제로 글을 올리고 링크를 낸 것
--   · link = '(관리자 처리)'     = 대표가 예약 상세에서 체크만 한 것 (글이 어디 있는지 모른다)

drop function if exists public.admin_event_reviews();

create or replace function public.admin_event_reviews()
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
declare rows_ jsonb; months jsonb; tot int; joined int;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;

  select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb) into rows_
  from (
    select jsonb_build_object(
      'id', er.id,
      'booking_id', er.booking_id,
      'name', bk.contractor_name,
      'wedding_date', to_char(bk.wedding_date, 'YYYY-MM-DD'),
      'created_at', to_char(er.created_at at time zone 'Asia/Seoul', 'YYYY-MM-DD'),
      'link', er.link,
      'reward', er.reward,
      'status', er.status,
      -- 링크가 없는 것(체크만 한 것)은 화면에서 따로 표시해야 한다
      'has_link', er.link is not null and er.link <> '(관리자 처리)',
      'where', case
        when er.link ~* 'blog[.]naver'            then '블로그'
        when er.link ~* 'cafe[.]naver'            then '카페'
        when er.link ~* 'instagram'               then '인스타'
        when er.link ~* 'place[.]naver|naver[.]me' then '플레이스'
        when er.link = '(관리자 처리)'            then '직접확인'
        else '기타' end
    ) as x
    from public.event_review er
    left join public.bookings bk on bk.id = er.booking_id
  ) t;

  -- 언제 몇 건씩 들어왔나 (등록한 달 기준, 한국시간)
  select coalesce(jsonb_agg(jsonb_build_object('m', m, 'n', n, 'linked', linked) order by m), '[]'::jsonb)
    into months
  from (
    select to_char(er.created_at at time zone 'Asia/Seoul', 'YYYY-MM') as m,
           count(*)::int as n,
           count(*) filter (where er.link <> '(관리자 처리)')::int as linked
    from public.event_review er group by 1
  ) g;

  -- 참여율의 분모는 «취소가 아닌 예약» 전부. 예식 전이라도 계약후기를 쓸 수 있으므로
  -- 지난 예식으로 좁히지 않는다
  select count(*)::int into tot from public.bookings where status is distinct from '취소';
  select count(*)::int into joined from public.event_review er
    join public.bookings bk on bk.id = er.booking_id
   where bk.status is distinct from '취소';

  return jsonb_build_object(
    'rows', rows_,
    'months', months,
    'n', jsonb_array_length(rows_),
    'linked', (select count(*)::int from public.event_review where link <> '(관리자 처리)'),
    'checked', (select count(*)::int from public.event_review where link = '(관리자 처리)'),
    'pending', (select count(*)::int from public.event_review where status = 'pending'),
    'album', (select count(*)::int from public.event_review where reward = '앨범'),
    'discount', (select count(*)::int from public.event_review where reward = '할인'),
    'bookings', tot,
    'joined', joined
  );
end$$;
revoke all on function public.admin_event_reviews() from public, anon;
grant execute on function public.admin_event_reviews() to authenticated;
