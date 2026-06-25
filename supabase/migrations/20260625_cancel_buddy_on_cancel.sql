-- 예약이 '취소'되면 연결된 짝꿍 이벤트도 자동 해제 (상대방 혜택까지 함께 해제).
-- 모든 취소 경로(취소 버튼=admin_update_booking, 수정폼 상태변경=admin_save_booking) 커버.
create or replace function public.cancel_buddy_on_booking_cancel()
returns trigger language plpgsql security definer set search_path=public, pg_temp as $$
begin
  if new.status = '취소' and (old.status is distinct from '취소') then
    update public.event_buddy set status = 'canceled'
      where status in ('waiting','matched','approved')
        and (requester_id = new.id or partner_id = new.id);
  end if;
  return new;
end$$;

drop trigger if exists trg_cancel_buddy on public.bookings;
create trigger trg_cancel_buddy
  after update of status on public.bookings
  for each row execute function public.cancel_buddy_on_booking_cancel();
