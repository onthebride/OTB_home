/* 끝 시각을 적으면 버퍼를 2시간으로 (대표 2026-09-25 «응 종료하면 버퍼를 2시간정도로 가자»)

   ⚠⚠ 내가 틀렸던 것을 바로잡는 판이다.
     끝 시각을 받아놓고 앞뒤 버퍼를 4시간씩 그대로 뒀더니, 적을수록 **더 넓게** 막혔다.
       시작 13:00, 끝 없음  → 10~16시 막힘
       시작 13:00, 끝 14:00 → 10~17시   ← 적었더니 더 막힌다
     작가님 입장에서는 적을수록 손해라 아무도 안 적으신다. 그러면 칸을 만든 뜻이 없다.

   왜 갈라야 하나 — 옛 4시간은 「촬영 한 건」을 통째로 싸잡은 값이다.
     몇 시에 끝나는지 모르니 넉넉히 잡아둔 것이다.
     끝 시각을 아는 순간 그 뭉텅이가 필요 없어진다. 남는 것은 **오가고 준비하는 시간**뿐이다.
     우리 예식은 1시간 30분 전 도착이 규칙이니 2시간이면 그 위에 이동이 얹힌다.

   이제 이렇게 된다
     시작 13:00, 끝 없음  → 10~16시 (예전 그대로)
     시작 13:00, 끝 14:00 → 12~15시 (짧게 끝나면 더 받으실 수 있다)
     시작 13:00, 끝 18:00 → 12~19시 (길면 그만큼 막힌다)

   ⚠ 두 숫자는 **여기 한 곳에만** 적는다. 화면은 이 판단을 안 따라 한다. */

/* ⚠ 칸을 더할 때는 drop function 을 같이 쓴다 (CLAUDE.md).
   안 그러면 옛 판(칸 셋)과 새 판(칸 넷)이 같이 남아 `busy_clash(sb, 시각)` 이
   「어느 것인지 모르겠다」로 터진다 — 2026-09-25 에 실제로 그랬다 */
drop function if exists private.busy_clash(public.staff_busy, text, int);

create or replace function private.busy_clash(
  sb public.staff_busy, p_wed text,
  p_hours int default 4,        -- 끝을 모를 때: 시작에서 앞뒤로 (예전 그대로)
  p_span_hours int default 2)   -- 끝을 알 때: 앞뒤로 오가고 준비하는 시간만
returns boolean language sql immutable
set search_path to 'private', 'public', 'pg_temp'
as $fn$
  select case
    when coalesce(sb.all_day, false) then true                       -- 종일은 그날 통째로
    when sb.at_time is null or sb.at_time = '' or p_wed is null or p_wed = '' then false
    when sb.end_time is null or sb.end_time = ''                     -- 끝을 모르면 예전 그대로
      then private.too_close(sb.at_time, p_wed, p_hours)
    else p_wed::time > (sb.at_time::time - make_interval(hours => p_span_hours))
     and p_wed::time < (sb.end_time::time + make_interval(hours => p_span_hours))
  end;
$fn$;
