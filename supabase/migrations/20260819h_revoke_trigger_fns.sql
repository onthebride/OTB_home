-- 트리거용 함수까지 anon 이 실행할 수 있게 열려 있었다. 트리거는 테이블에 달려서 도는 것이라
-- 밖에서 부를 일이 없다. 게다가 둘 다 security definer 라 열어둘 이유가 전혀 없다.
-- (지금 당장 뚫리는 건 아니다 — 트리거 함수는 직접 부르면 오류가 난다. 열어둘 까닭이 없어 닫는다)
revoke execute on function public.auto_assign_rep() from anon, authenticated, public;
revoke execute on function public.cancel_buddy_on_booking_cancel() from anon, authenticated, public;

-- booking_options_struct 는 예약ID만 있으면 옵션을 돌려준다. 손님 포털·설문이 쓰는 게 아니라
-- 관리자 쪽 계산용이라 anon 에게 열어둘 필요가 없다.
revoke execute on function public.booking_options_struct(uuid) from anon;
