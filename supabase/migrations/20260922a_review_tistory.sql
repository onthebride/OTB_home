/* 후기 링크 갈래에 티스토리·브런치를 더한다 (2026-09-22)

   신부님 한 분이 tistory.com 에 후기를 올려주셨는데 갈래가 없어 「기타」로 빠졌다.
   티스토리는 블로그다 — 네이버 블로그와 같은 칸에 넣는다. 브런치도 미리 넣어둔다.

   ⚠ 내 코드가 바뀌어서 시험이 빨개진 게 아니라 **새 자료가 들어와서**다.
     「링크 있는 줄에 기타가 없다」를 보던 시험이 제 일을 했다.
   ⚠ 앞으로도 처음 보는 데에 올려주시면 또 걸린다. 그때마다 갈래를 하나 더하면 된다.

   이 파일은 살아 있는 정의를 읽어와 한 군데만 갈아 끼운 것이다 (_tistory_patch.mjs). */
CREATE OR REPLACE FUNCTION public.admin_event_reviews()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
        -- 티스토리·브런치도 블로그다 (2026-09-22 에 티스토리 후기가 들어와 「기타」로 빠졌다)
        when er.link ~* 'blog[.]naver|tistory|brunch[.]co[.]kr' then '블로그'
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
end$function$
;
