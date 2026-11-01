-- 손님 자동 알림톡을 예약 하나만 빼기 (2026-10-31 대표 «내일 ○○○신부는 후기작성 알림톡 안나가게 해줘»)
--
-- 예식 다음날 10시 「촬영 후 설문」(G) 은 private.alimtalk_send_scheduled 이 확정 예약 모두에게 보낸다.
-- 한 분만 빼는 길이 없었다.
--
-- ⚠ 뺀 것을 bookings.alimtalk_sent 에 적지 않는다. 그 칸의 G 는 관리자 「설문 안 보낸 예식」이
--   «보냈다» 로 읽는 자리다. 안 보낸 것은 안 보낸 것으로 둔다 (20260829a_send_hold.sql 과 같은 까닭).
--   bookings 를 건드리지 않으니 trg_booking_change_notify 도 안 돈다.
-- ⚠ 어느 예약을 뺐는지(예약 번호)는 이 파일에 적지 않는다. 예약 번호가 곧 손님 예약 페이지 주소다 —
--   저장소가 공개라 운영 DB 에만 넣는다.
-- ⚠ 관리자가 직접 누르는 발송(public.admin_send_alimtalk)은 막지 않는다. 그건 대표가 고른 것이다.

create table if not exists private.alimtalk_skip (
  booking_id uuid not null,
  tpl        text not null,                -- 'B' 한달전 · 'C' 잔금 · 'D' 전날 · 'G' 촬영 후 설문
  why        text,
  at         timestamptz not null default now(),
  primary key (booking_id, tpl)
);
comment on table private.alimtalk_skip is
  '손님 자동 알림톡에서 이 예약의 이 템플릿만 뺀다. 대표가 말씀하신 것만 넣는다 (2026-10-31)';
revoke all on table private.alimtalk_skip from public, anon, authenticated;

create or replace function private.alimtalk_send_scheduled()
returns int language plpgsql security definer set search_path=private, public, extensions, pg_temp as $$
declare r record; n int := 0; vars jsonb; req bigint;
begin
  for r in
    select b.id, b.contractor_name, b.contractor_phone, x.tpl
    from public.bookings b
    cross join (values ('B', (current_date + 30)), ('C', (current_date + 7)), ('D', (current_date + 1)),
                       ('G', (current_date - 1))) as x(tpl, dday)   -- G: 예식 다음날 촬영 설문
    where b.status <> '취소' and coalesce(b.deposit_paid,false)
      and b.wedding_date = x.dday
      and b.contractor_phone is not null
      and (coalesce(b.alimtalk_sent,'{}'::jsonb) -> x.tpl) is null
      and not exists (select 1 from private.alimtalk_skip k where k.booking_id = b.id and k.tpl = x.tpl)
  loop
    vars := jsonb_build_object('#{고객명}', coalesce(r.contractor_name,''), '#{예약ID}', r.id::text);
    req := private.alimtalk_dispatch(r.id, r.tpl, r.contractor_phone, vars);
    update public.bookings set alimtalk_sent = coalesce(alimtalk_sent,'{}'::jsonb) || jsonb_build_object(r.tpl, to_jsonb(now())) where id = r.id;
    n := n + 1;
  end loop;
  return n;
end$$;
revoke all on function private.alimtalk_send_scheduled() from public, anon, authenticated;
