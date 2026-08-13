-- 20260813_deposit_paid_at.sql
-- 계약금 입금확인 시각(deposit_paid_at) 기록.
-- 목적: 입금확인을 누르면 상태가 신규→확정으로 바뀌며 예약탭 '신규' 목록에서 즉시 사라지는데,
--       입금 후 3일(72시간) 동안은 '신규' 목록에 계속 보이도록 하기 위한 기준 시각.
-- Supabase 대시보드 → SQL Editor 에 붙여넣고 실행하면 됩니다.

alter table public.bookings add column if not exists deposit_paid_at timestamptz;

-- 입금확인 토글: 입금 켜면 시각 기록(이미 있으면 유지), 해제하면 지움
create or replace function public.admin_set_deposit(p_id uuid, p_paid boolean)
returns public.bookings language plpgsql security definer set search_path=public, pg_temp
as $$ declare r public.bookings; begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.bookings
     set deposit_paid = coalesce(p_paid,false),
         -- 미입금→입금 전환 순간만 기록(기존 입금건을 다시 저장해도 시각이 밀리지 않게)
         deposit_paid_at = case when coalesce(p_paid,false) and not deposit_paid then now()
                                when coalesce(p_paid,false) then deposit_paid_at else null end,
         status = case
           when coalesce(p_paid,false) and status = '신규' then '확정'
           when not coalesce(p_paid,false) and status = '확정' then '신규'
           else status end
   where id=p_id returning * into r;
  return r;
end; $$;

-- 예약 수정 모달의 '계약금 입금 완료' 체크로 저장하는 경로도 동일하게 시각 기록
create or replace function public.admin_save_booking(p_id uuid, payload jsonb)
returns public.bookings language plpgsql security definer set search_path = public, pg_temp
as $$
declare r public.bookings;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  update public.bookings set
    status            = coalesce(payload->>'status', status),
    admin_note        = payload->>'admin_note',
    contractor_name   = nullif(payload->>'contractor_name',''),
    contractor_phone  = nullif(payload->>'contractor_phone',''),
    contractor_email  = nullif(payload->>'contractor_email',''),
    wedding_date      = nullif(payload->>'wedding_date','')::date,
    wedding_time      = nullif(payload->>'wedding_time',''),
    wedding_venue     = nullif(payload->>'wedding_venue',''),
    groom_name        = nullif(payload->>'groom_name',''),
    groom_phone       = nullif(payload->>'groom_phone',''),
    bride_name        = nullif(payload->>'bride_name',''),
    bride_phone       = nullif(payload->>'bride_phone',''),
    package           = case when payload ? 'package' then nullif(payload->>'package','')
                             else (case when coalesce((payload->>'basic')::boolean, true) then '베이직(데이터형)' else null end) end,
    travel_fee        = coalesce((payload->>'travel_fee')::boolean, false),
    option_album      = coalesce((payload->>'option_album')::boolean, false),
    option_reception  = coalesce((payload->>'option_reception')::boolean, false),
    option_pyebaek    = coalesce((payload->>'option_pyebaek')::boolean, false),
    option_part2      = coalesce((payload->>'option_part2')::boolean, false),
    photographer      = coalesce(nullif(payload->>'photographer',''), '기본'),
    rep_designation   = coalesce((payload->>'rep_designation')::boolean, false),
    photo_usage_agree = coalesce((payload->>'photo_usage_agree')::boolean, false),
    agree_available   = coalesce((payload->>'agree_available')::boolean, false),
    agree_terms       = coalesce((payload->>'agree_terms')::boolean, false),
    total_price       = nullif(payload->>'total_price','')::int,
    deposit_paid      = coalesce((payload->>'deposit_paid')::boolean, deposit_paid),
    -- 계약금 입금확인 시각: 미입금→입금 순간만 기록, 해제하면 지움(예약탭 '신규' 3일 유예용)
    deposit_paid_at   = case when coalesce((payload->>'deposit_paid')::boolean, deposit_paid) and not deposit_paid then now()
                             when coalesce((payload->>'deposit_paid')::boolean, deposit_paid) then deposit_paid_at
                             else null end,
    balance_paid      = coalesce((payload->>'balance_paid')::boolean, balance_paid),
    custom_options    = case when payload ? 'custom_options' then coalesce(payload->'custom_options','[]'::jsonb) else custom_options end,
    line_items        = case when payload ? 'line_items' then (case when jsonb_array_length(coalesce(payload->'line_items','[]'::jsonb)) > 0 then payload->'line_items' else null end) else line_items end,
    assignee_id       = case when payload ? 'assignee_id' then nullif(payload->>'assignee_id','')::uuid else assignee_id end,
    sub_assignee_id   = case when payload ? 'sub_assignee_id' then nullif(payload->>'sub_assignee_id','')::uuid else sub_assignee_id end
  where id = p_id
  returning * into r;
  return r;
end;
$$;
revoke all on function public.admin_save_booking(uuid, jsonb) from public, anon;
grant execute on function public.admin_save_booking(uuid, jsonb) to authenticated;
