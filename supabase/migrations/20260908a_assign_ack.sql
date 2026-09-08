-- 배정한 것을 작가가 확인했는지, 예약을 볼 때 바로 보이게 (대표 2026-09-08
--   «이게 내가 작가들 스케줄 줬는데 작가들이 확인을 햇는지 물어보기전에 알 수가 없네»
--   «그냥 앞으로 배정하는거 작가들이 확인 누르면 내가 알 수 있게해줘»)
--
-- 지금까지는 홈의 「작가 미확인」에 **안 누른 것만** 떴다. 누른 것은 목록에서 사라질 뿐,
-- 「이 예식은 확인됐다」를 어디서도 볼 수 없었다. 없어진 것을 보고 짐작하는 셈이었다.
--
-- ⚠ 대표가 «앞으로 배정하는거» 라고 하셨다. 8/31 이전 배정분 92건은 알림이 나간 적이
--   없어 확인할 기회 자체가 없었다 — 그건 그대로 둔다(대표가 안 하기로 하셨다).
--   그래서 **알림이 나간 것만** 상태를 낸다. 안 나간 것은 아무 표시도 안 한다 —
--   「확인 안 함」으로 적으면 작가가 안 한 것처럼 보인다. 물어본 적이 없는 것이다.
--
-- ⚠ 예약 줄에 칸을 더하지 않는다. admin_list_bookings 가 SETOF bookings 라
--   칸을 늘리면 그 줄을 쓰는 다른 곳들(admin_mark_pay 의 to_jsonb 등)이 같이 흔들린다.
--   따로 뽑아 화면에서 붙인다.

create or replace function public.admin_assign_ack()
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'private', 'pg_temp' as $$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;

  select coalesce(jsonb_object_agg(t.bid, t.v), '{}'::jsonb) into res
  from (
    select b.id::text as bid,
           jsonb_strip_nulls(jsonb_build_object(
             'main_sent', (m.id is not null),
             'main_ok',   (m.read_at is not null),
             -- 언제 눌렀는지. 「어제 눌렀네」 가 보이면 물어볼 일이 없다
             'main_at',   to_char(m.read_at at time zone 'Asia/Seoul', 'MM/DD HH24:MI'),
             'sub_sent',  (s.id is not null),
             'sub_ok',    (s.read_at is not null),
             'sub_at',    to_char(s.read_at at time zone 'Asia/Seoul', 'MM/DD HH24:MI'))) as v
      from public.bookings b
      -- 그 사람에게 간 **마지막** 배정 알림. 배정을 바꾸면 새로 가므로 마지막 것이 지금 것이다
      left join lateral (
        select n.id, n.read_at from public.staff_notice n
         where n.booking_id = b.id and n.staff_id = b.assignee_id and n.kind = 'assign'
         order by n.created_at desc limit 1) m on b.assignee_id is not null
      left join lateral (
        select n.id, n.read_at from public.staff_notice n
         where n.booking_id = b.id and n.staff_id = b.sub_assignee_id and n.kind = 'assign'
         order by n.created_at desc limit 1) s on b.sub_assignee_id is not null
     -- 알림이 나간 것만. 안 나간 것은 「확인 안 함」이 아니라 「물어본 적 없음」이다
     where m.id is not null or s.id is not null
  ) t;

  return res;
end$$;
revoke all on function public.admin_assign_ack() from public, anon;
grant execute on function public.admin_assign_ack() to authenticated;
