-- 예식 시간은 오전 9시 ~ 오후 8시(20:00 정각까지)만 (2026-10-31 대표 «시간등록을 아예 제한을 하자 오전 9시부터 저녁 8시까지로»)
--
-- 그날 2027-03-20 예식이 00:30(밤 12시 반)으로 들어와 있었다 — 12:30 을 잘못 넣은 것.
-- 작가 캘린더·겹침 확인이 이 시각으로 돌아 아무도 몰랐다.
--
-- 화면(손님 예약 · 관리자 수정)에서 먼저 막고, 여기서 한 번 더 막는다.
--   · 손님 폰에 예전 main.js 가 남아 있으면 범위 밖이 올 수 있다 — 그때 이 글이 화면에 뜬다
--   · 시각이 **바뀔 때만** 본다. 다른 칸만 고치는 저장은 그대로 지나간다
--   · 「HH:MM」 꼴이 아닌 글(빈칸 등)은 건드리지 않는다 — 막는 것은 시각뿐
-- ⚠ 분으로 바꿔 잰다 (private.min_of_day). time 으로 재면 24시를 넘어 돈다 (CLAUDE.md)

create or replace function private.tg_wedding_time_range()
returns trigger language plpgsql set search_path to 'private', 'public', 'pg_temp' as $$
declare t int;
begin
  if new.wedding_time is null or trim(new.wedding_time) !~ '^[0-9]{1,2}:[0-9]{2}' then return new; end if;
  if tg_op = 'UPDATE' and new.wedding_time is not distinct from old.wedding_time then return new; end if;
  t := private.min_of_day(trim(new.wedding_time));
  if t < 9 * 60 or t > 20 * 60 then
    raise exception '예식 시간은 오전 9시부터 오후 8시 사이만 넣을 수 있어요 (받은 값 %)', new.wedding_time
      using errcode = '23514';
  end if;
  return new;
end $$;

-- 이름 앞 글자 b — 같은 BEFORE 트리거끼리는 이름 순서로 돈다. a_fmt_phone 다음, trg_auto_rep 앞
drop trigger if exists b_wedding_time_range on public.bookings;
create trigger b_wedding_time_range before insert or update of wedding_time on public.bookings
  for each row execute function private.tg_wedding_time_range();
