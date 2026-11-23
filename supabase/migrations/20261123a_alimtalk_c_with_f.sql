-- 예식이 7일 안인 예약은 계약금 확인 톡(F)과 함께 잔금 안내(C)도 바로 나가게 (2026-11-23 대표 «일주일 안 예약은 확정 톡과 함께 바로 나가도록»)
--
-- 일주일 전 안내(C, 톡 이름 「예식전 최종 스케줄 확인」 — 담당 작가·스케줄·잔금 결제·예식 전 설문)는
-- private.alimtalk_send_scheduled 가 매일 10시에 «예식이 정확히 7일 뒤인 예약»에게만 보낸다.
-- 예식 일주일 안에 접수·확정된 예약은 그 날이 이미 지나서 이 톡이 한 번도 안 나갔다
-- (11/22 오후에 확정된 11/29 예식 — 그날 10시에는 예약이 아직 없었다).
--
-- 고침: 관리자가 계약금을 확인하고 F 를 보낼 때(public.admin_send_alimtalk 'F') 예식이 7일 안이면
--       C 도 이어서 보낸다. 사람이 보낸 F 에 붙이는 것이라 따로 시각을 정하지 않는다.
--
--   private.alimtalk_c_with_f(예약)  C 를 보내야 하면 보내고 bookings.alimtalk_sent 에 적은 뒤 true.
--                                    아니면 false. 보내다 실패해도 F 는 그대로 나간다(밖으로 안 터진다).
--
-- ⚠ 나가는 조건 (모두 맞아야 한다):
--     · 이번이 F 를 «처음» 보내는 것 (alimtalk_sent 에 F 가 아직 없음) — 실패 건 다시 보내기·F 다시 누르기에는 안 붙는다
--     · 취소 아님 · 계약금 입금됨 · 연락처 있음
--     · 예식이 한국 날짜로 1~7일 뒤 (오늘·지난 예식은 안 붙인다)
--     · C 를 아직 안 보냈음 (alimtalk_sent 에 C 없음) — 그래서 매일 10시 자동 발송과 겹쳐 두 번 나가지 않는다
--     · private.alimtalk_skip 에서 이 예약의 C 를 빼 두지 않았음
-- ⚠ 계약금 확인 때 예식이 7일보다 먼 예약은 그대로다 — 7일 전 10시에 자동으로 나간다 (바뀐 것 없음).
-- ⚠ public.admin_send_alimtalk 의 본문은 빼기 표(alimtalk_skip)를 직접 보지 않는다 — 시험 alimtalkskip 이
--   «관리자가 직접 누르는 발송은 막지 않는다» 를 몸통 글자로 못박아 둔다. 빼기 표는 이 새 함수 안에서만 본다.
-- ⚠ 응답에 c_sent(true/false)를 더했다. 옛 화면은 이 칸을 안 읽어 그대로 동작한다.

create or replace function private.alimtalk_c_with_f(p_booking_id uuid)
returns boolean language plpgsql security definer set search_path to 'private', 'public', 'extensions', 'pg_temp' as $$
declare b public.bookings; left_days int; vars jsonb;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found then return false; end if;
  if b.status = '취소' or not coalesce(b.deposit_paid, false) or b.contractor_phone is null then return false; end if;
  left_days := b.wedding_date - (now() at time zone 'Asia/Seoul')::date;
  if left_days is null or left_days < 1 or left_days > 7 then return false; end if;
  if (coalesce(b.alimtalk_sent, '{}'::jsonb) -> 'C') is not null then return false; end if;
  if exists (select 1 from private.alimtalk_skip k where k.booking_id = b.id and k.tpl = 'C') then return false; end if;

  vars := jsonb_build_object('#{고객명}', coalesce(b.contractor_name, ''), '#{예약ID}', b.id::text);
  begin
    perform private.alimtalk_dispatch(b.id, 'C', b.contractor_phone, vars);
    update public.bookings
       set alimtalk_sent = coalesce(alimtalk_sent, '{}'::jsonb) || jsonb_build_object('C', to_jsonb(now()))
     where id = b.id;
  exception when others then
    raise warning 'C 를 F 와 함께 보내지 못했다: %', sqlerrm;   -- 안쪽 일은 되돌려진다 (큐·outbox·표시 모두)
    return false;
  end;
  return true;
end$$;
revoke all on function private.alimtalk_c_with_f(uuid) from public, anon, authenticated;

-- 관리자 수동 발송 — F 를 처음 보내는 것이면 끝에 C 를 한 번 붙여 본다 (그 밖에는 운영 판 그대로)
create or replace function public.admin_send_alimtalk(p_booking_id uuid, p_template text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'extensions', 'pg_temp'
as $$
declare b public.bookings; vars jsonb; req bigint; f_first boolean; c_sent boolean := false;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select * into b from public.bookings where id = p_booking_id; if not found then raise exception 'booking not found'; end if;
  if b.contractor_phone is null then raise exception '연락처가 없습니다'; end if;
  if p_template not in ('A','B','C','D','E','F','G') then raise exception 'bad template'; end if;
  if p_template = 'E' and b.download_link is null then raise exception '다운로드 링크를 먼저 입력하세요'; end if;

  f_first := p_template = 'F' and (coalesce(b.alimtalk_sent,'{}'::jsonb) -> 'F') is null;
  vars := jsonb_build_object('#{고객명}', coalesce(b.contractor_name,''), '#{예약ID}', b.id::text);
  req := private.alimtalk_dispatch(p_booking_id, p_template, b.contractor_phone, vars);
  update public.bookings set alimtalk_sent = coalesce(alimtalk_sent,'{}'::jsonb) || jsonb_build_object(p_template, to_jsonb(now())) where id = p_booking_id;
  if f_first then c_sent := private.alimtalk_c_with_f(p_booking_id); end if;
  return jsonb_build_object('ok', true, 'req', req, 'c_sent', c_sent);
end$$;
