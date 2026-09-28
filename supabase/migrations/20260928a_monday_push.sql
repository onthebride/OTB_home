/* 월요일 체크에도 폰 알림 (대표 2026-09-28 «지금 월요일 체크는 핸드폰 알림 안나가?» → «작가 캘린더»)

   ── 그동안 어땠나
   private.staff_check_send_weekly() 는 알림톡(S)만 보냈다. otb_push 를 안 불렀다.
   2026-09-28 10:00 에 넷(김병훈·양재훈·최선종·황성용)에게 알림톡이 나갔고 폰 알림은 0 이었다.
   작가님 입장에서는 **예식 하루 전 알림은 폰에 뜨는데 주간 체크 요청만 카톡으로만** 왔다.

   ── 무엇을 더하나
   알림톡을 보낸 바로 뒤에 폰 알림도 하나 울린다. 누르면 작가 캘린더로 간다.

   ⚠⚠ staff_notice(알림함) 줄은 **일부러 안 만든다.**
     「확인」 칸의 월요일 체크는 예식마다 세 가지를 체크하고 「확인 완료」 를 누르는 것이다
     (staff_todo 의 check 갈래). 거기에 「확인했어요」 만 누르면 되는 알림함 줄을 하나 더
     만들면 누를 것이 둘이 되고, 엉뚱한 쪽을 눌러 체크가 안 된 채로 넘어간다.
     이 알림은 **종을 울리는 것뿐**이다. 할 일은 확인 칸에 그대로 있다.

   ⚠ staff_notice.pushed_at 은 default now() 다 — 줄을 넣어도 notice_push_flush 가
     집어가지 않는다. 그래서 알림은 언제나 만든 쪽에서 직접 보낸다. 여기서도 그렇게 한다.

   ⚠ p_dry 일 때는 안 보낸다. 알림톡과 같은 자리에 둔다.

   ── 안 바뀌는 것
   알림톡은 그대로 나간다. 누가 받는지, 한 주에 한 번인지도 그대로다.
   폰 알림 기기를 등록 안 하신 분(김주영 작가)은 예전처럼 알림톡만 받으신다. */


CREATE OR REPLACE FUNCTION private.staff_check_send_weekly(p_dry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'private', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  d0 date := date_trunc('week', (now() at time zone 'Asia/Seoul')::date)::date;  -- 이번 주 월요일
  r record; n int := 0; vars jsonb; out_rows jsonb := '[]'::jsonb; n_mark int := 0; m int;
begin
  if not p_dry and exists (select 1 from private.send_hold h where h.kind = 'S' and h.on_date = d0) then
    return jsonb_build_object('ok', true, 'held', true, 'week_of', d0, 'n', 0);
  end if;

  for r in
    -- 메인·서브 가릴 것 없이 «이번 주에 나갈 사람» 이면 받는다.
    -- 한 작가가 이번 주에 세 건이어도 한 통만 간다 (버튼을 누르면 다 보인다)
    select st.id, st.name, st.phone, count(*) as n_wed, min(b.wedding_date) as first_wed
    from public.bookings b
    join public.staff st on st.id in (b.assignee_id, b.sub_assignee_id)
    where b.status <> '취소'
      and b.wedding_date >= d0 and b.wedding_date < d0 + 7
      and coalesce(st.active, false)
      and coalesce(st.phone, '') <> ''
      -- 대표를 걸러내지 않는 것은 일부러다 (대표 요청 2026-08-25 «나한테도 톡 주고»).
      -- 본인도 찍으러 나가니 이번 주 일정을 같은 방식으로 받는 게 맞다
      --
      -- 이번 주에 이미 보냈으면 다시 안 보낸다 (크론이 두 번 돌아도 안전하게)
      and not exists (
        select 1 from private.alimtalk_outbox o
        where o.template = 'S' and o.phone = st.phone
          and o.created_at >= (d0::timestamp at time zone 'Asia/Seoul'))
    group by st.id, st.name, st.phone
    order by st.name
  loop
    out_rows := out_rows || jsonb_build_object(
      'staff', r.name, 'phone', right(r.phone, 4), 'weddings', r.n_wed, 'first', r.first_wed);
    if not p_dry then
      vars := jsonb_build_object('#{작가명}', coalesce(r.name, ''), '#{작가ID}', r.id::text);
      perform private.alimtalk_dispatch(null, 'S', r.phone, vars);
      /* 폰 알림도 같이 (대표 2026-09-28 «지금 월요일 체크는 핸드폰 알림 안나가?» → «작가 캘린더»).
         ⚠⚠ 알림함 줄은 안 만든다 — 확인 칸의 「확인 완료」 는 예식마다 세 가지를 체크하는 것이라
           (staff_todo 의 check 갈래) 「확인했어요」 하나짜리 줄을 더하면 누를 것이 둘이 된다.
           이건 종을 울리는 것뿐이고, 할 일은 확인 칸에 그대로 있다.
         ⚠ 기기를 등록 안 하신 분께는 그냥 안 간다. 알림톡은 그대로 받으신다 */
      perform private.otb_push(
        '📅 이번 주 촬영 ' || r.n_wed || '건',
        to_char(r.first_wed, 'MM월 DD일') || '부터 · 캘린더 「확인」 칸에서 확인 부탁드려요',
        '/staff-calendar?s=' || r.id::text, r.id);
      -- ★ 여기가 이번에 더한 것 — 그 주 예식들에 «체크 요청이 나갔다» 를 남긴다.
      --   이게 없으면 admin_unconfirmed() 가 이 건들을 아예 안 문다
      select private.mark_weekly_sent(r.id, d0, now()) into m;
      n_mark := n_mark + m;
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'dry', p_dry, 'held', false, 'week_of', d0,
    'n', n, 'marked', n_mark, 'rows', out_rows);
end$function$
;
