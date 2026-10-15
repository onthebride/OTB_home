/* 관리자 홈 알림톡 칸 — 성공한 것은 안 띄우고 실패한 것만
   (대표 2026-10-15 «알림톡 발송 성공여부는 내부적으로 판단하고 실패 하는것만 알려줘»)

   무엇이 귀찮았나 — 6/20 에 이 칸을 「오늘 보낸 것 전부(성공·실패)」로 넓혔다 (0614489).
   그 뒤로 대표는 날마다 성공한 줄마다 「✓ 확인」 또는 「전체 확인」을 눌러 지우고 계셨다
   (10/15 낮에 보니 그날 나간 성공 줄이 벌써 다 「확인」 으로 지워져 있었다).
   성공은 시스템이 판단한다 — 솔라피 결과 4000 이면 completed 로 바뀐다(alimtalk_check_delivery).

   이제 뜨는 것:
   · failed  — 솔라피가 「전달 실패」라고 한 것 (코드 3101~3108 등)
   · gaveup  — 접수부터 안 된 것 (세 번 시도 실패 · 15분 무응답)
   · ⏳ 결과 모름 — sent·delivered 인 채로 **1시간 넘게** 결과가 안 온 것.
     평소엔 3분 안에 completed/failed 로 갈린다. 이걸 숨기면 성공도 실패도 아닌 채로
     아무도 모르게 된다 — 전에는 「오늘 것」 이라 그날은 보였다. 그 자리를 이것이 잇는다
   · 날짜와 상관없이, 「✓ 확인」 을 누를 때까지 (전과 같다)
   · 같은 예약·같은 알림톡이 그 뒤에 나갔으면(다시 보내기) 앞의 실패는 안 띄운다 (전과 같다)
     ⚠ 다만 뒤에 나간 것을 「확인」 으로 숨겼어도 앞의 실패를 되살리지 않는다.
       전에는 `and not o2.dismissed` 가 있어서, 성공 줄을 확인으로 지우면 묻혀 있던 옛 실패가
       다시 떠오를 수 있었다. 성공 줄을 안 띄우는 지금은 그 조건이 뜻이 없다

   폰 알림(otb_push)은 손대지 않았다 — 원래 실패 때만 간다(alimtalk_retry_due · alimtalk_check_delivery).
   dismissed 는 이 화면 표시에만 쓰인다 (admin_alimtalk_failures · admin_dismiss_alimtalk_fail 외엔 안 읽는다) */

CREATE OR REPLACE FUNCTION public.admin_alimtalk_log()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'booking_id', o.booking_id, 'template', o.template, 'name', b.contractor_name,
    'wedding_date', b.wedding_date, 'status', o.status, 'fail_code', o.fail_code, 'text', o.rendered_text,
    'sent_at', o.created_at) order by o.created_at desc), '[]'::jsonb)
  into res
  from private.alimtalk_outbox o
  join public.bookings b on b.id = o.booking_id
  where not o.dismissed
    and b.status <> '취소'
    and ( o.status in ('failed','gaveup')
          or (o.status in ('sent','delivered') and o.created_at < now() - interval '1 hour') )
    and not exists (
      select 1 from private.alimtalk_outbox o2
      where o2.booking_id = o.booking_id and o2.template = o.template
        and o2.status in ('delivered','completed') and o2.created_at > o.created_at);
  return res;
end$function$;

-- 「전체 확인」 — 칸에 떠 있는 것만 숨긴다 (위와 같은 조건)
CREATE OR REPLACE FUNCTION public.admin_dismiss_alimtalk_all()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update private.alimtalk_outbox o set dismissed = true
  from public.bookings b
  where b.id = o.booking_id and not o.dismissed and b.status <> '취소'
    and ( o.status in ('failed','gaveup')
          or (o.status in ('sent','delivered') and o.created_at < now() - interval '1 hour') );
end$function$;
