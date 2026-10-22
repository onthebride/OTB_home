-- 알림톡이 손님에게 두 번 가던 것 (2026-10-22 점검에서 찾음 → 대표 «응 수정»)
--
-- 무엇이. 아침 10시(01:00 UTC) 예약 발송 때 솔라피 답이 5초(pg_net 기본)를 넘기면
--   net._http_response 에 timed_out = true 가 남는다. alimtalk_retry_due 는 이것을
--   「응답 왔는데 2xx 아님 = 확실한 실패」 로 보고 3분 뒤 **다시 보냈다.**
--   그런데 시간 초과는 「솔라피가 받았는지 모른다」 는 뜻이다. 실제로는 이미 나가 있었다.
--   솔라피 list?to= 로 재 보니 다시 보낸 8줄 중 100일 안의 7줄이 **전부 두 통 전달**
--   (한달전 4 · 최종안내 2 · 잔금안내 1, 전부 10시 묶음. 10/22 아침에도 한달전 둘).
--   도구: .backups/tests/pgrun/_atk_dupcheck.mjs
--
-- 고친 것
--   ① 시간 초과는 「모름」 이다. 바로 다시 보내지 않고, 솔라피에 그 번호로 나간 것을 묻는다
--      (GET /messages/v4/list?to=…&startDate=보낸 때-1분). 답을 다음 차례(3분 뒤)에 본다.
--        · 같은 템플릿이 그 뒤로 나가 있다 → 나간 것이다. delivered + message_id
--          (그 다음은 alimtalk_check_delivery 가 전달 여부를 본다 — 지금과 같다)
--        · 없다 → 그때 다시 보낸다 (3번까지 — 지금과 같다)
--        · 묻는 것마저 안 된다 → 다시 묻는다. 30분 넘게 모르면 포기하고 대표께 알린다
--          (사람이 보고 판단한다. 기계가 짐작으로 또 보내지 않는다)
--   ② 기다리는 시간 5초 → 20초 (solapi_send). 시간 초과 자체가 드물어진다.
--
-- 그대로 둔 것
--   · 응답이 왔는데 2xx 가 아니다(4xx·5xx) · 연결 자체가 안 됐다(error_msg, 시간 초과 아님)
--     → 솔라피가 안 받은 것이라 지금처럼 다시 보낸다
--   · 응답이 아예 없다 → 15분 기다렸다 포기(무응답) — 지금과 같다
--   · 상태 이름(sent·delivered·completed·failed·gaveup)은 그대로. 관리자 화면·
--     admin_alimtalk_log 의 「⏳ 결과 모름」(10/15) 이 그대로 읽는다. 확인 중에도 status 는 sent 다.
--
-- 시험: .backups/tests/pgrun/atknodouble.test.mjs (OLD=1 이면 지금 운영 판 — 시간 초과에 다시 보낸다)

alter table private.alimtalk_outbox
  add column if not exists verify_req_id bigint,   -- 「나갔나」 물어본 요청(net) 번호
  add column if not exists verify_result text;     -- 물어본 결과: sent(이미 나가 있었다) · not_sent(안 나가 다시 보냈다)

-- ② 기다리는 시간만 늘린다. 나머지는 한 글자도 안 바꾼다 (staff.test 가 본문을 본다)
create or replace function private.solapi_send(p_to text, p_template_key text, p_vars jsonb)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $function$
declare k text; s text; pf text; tpl text; dt text; salt text; sig text; hdr text; req bigint;
begin
  select val into k from private.solapi where key='api_key';
  select val into s from private.solapi where key='api_secret';
  -- 템플릿 전용 발신프로필이 있으면 그것을, 없으면 기본(손님 채널)
  select val into pf from private.solapi where key = 'pf_' || p_template_key;
  if pf is null then select val into pf from private.solapi where key='pf_id'; end if;
  select val into tpl from private.solapi where key=p_template_key;
  if k is null or tpl is null then raise exception 'solapi not configured (%)', p_template_key; end if;
  dt := to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  salt := encode(gen_random_bytes(32), 'hex');
  sig := encode(hmac(dt || salt, s, 'sha256'), 'hex');
  hdr := 'HMAC-SHA256 apiKey=' || k || ', date=' || dt || ', salt=' || salt || ', signature=' || sig;
  select net.http_post(
    url := 'https://api.solapi.com/messages/v4/send',
    body := jsonb_build_object('message', jsonb_build_object(
      'to', regexp_replace(p_to, '[^0-9]', '', 'g'),
      'kakaoOptions', jsonb_build_object('pfId', pf, 'templateId', tpl, 'variables', p_vars))),
    headers := jsonb_build_object('Content-Type','application/json','Authorization',hdr),
    -- 5초(기본)면 10시 묶음 발송 때 답이 늦어 「시간 초과」 가 났다 (2026-10-22)
    timeout_milliseconds := 20000
  ) into req;
  return req;
end$function$;

-- ① 「그 번호로 그 뒤에 나간 것」 을 솔라피에 묻는다 (조회만 한다)
create or replace function private.solapi_list_req(p_to text, p_since timestamptz)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $function$
declare k text; s text; dt text; salt text; sig text; hdr text; req bigint;
begin
  select val into k from private.solapi where key='api_key';
  select val into s from private.solapi where key='api_secret';
  if k is null or s is null then return null; end if;
  dt := to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  salt := encode(gen_random_bytes(32), 'hex');
  sig := encode(hmac(dt || salt, s, 'sha256'), 'hex');
  hdr := 'HMAC-SHA256 apiKey=' || k || ', date=' || dt || ', salt=' || salt || ', signature=' || sig;
  -- ⚠ startDate 만 주면 솔라피가 날짜를 안 거른다 (2026-10-22 재 봄 — 7월 것까지 왔다). endDate 를 꼭 같이.
  --   그래도 받는 쪽(alimtalk_retry_due)에서 번호·템플릿·시각을 다시 본다
  select net.http_get(
    url := 'https://api.solapi.com/messages/v4/list?limit=50&to=' || regexp_replace(p_to, '[^0-9]', '', 'g')
           || '&startDate=' || to_char(p_since at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
           || '&endDate=' || to_char((now() + interval '1 day') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    headers := jsonb_build_object('Authorization', hdr),
    timeout_milliseconds := 20000
  ) into req;
  return req;
end$function$;

revoke all on function private.solapi_list_req(text, timestamptz) from public, anon, authenticated;

create or replace function private.alimtalk_retry_due()
 returns integer
 language plpgsql
 security definer
 set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $function$
declare r record; resp record; v record; ok boolean; confirmed_fail boolean; n int := 0; newreq bigint;
  tpl text; mid text; parsed boolean; got boolean; ml jsonb;
begin
  for r in
    select * from private.alimtalk_outbox
    where status = 'sent' and last_attempt_at < now() - interval '1 minute'
    order by id limit 100
  loop
    -- (가) 「나갔나」 물어본 것이 있으면 그 답부터 본다
    if r.verify_req_id is not null then
      select status_code, timed_out, error_msg, content into v from net._http_response where id = r.verify_req_id;
      got := found;   -- ⚠ 아래 select 들이 found 를 덮는다. 여기서 붙잡아 둔다
      mid := null; parsed := false;
      if got and v.status_code between 200 and 299 and left(coalesce(v.content, ''), 1) = '{' then
        select val into tpl from private.solapi where key = 'tpl_' || r.template;
        begin
          ml := (v.content::jsonb) -> 'messageList';
          -- 아무것도 없으면 {} 로 온다 (재 봄). 다른 모양이면 「없다」 로 단정하지 않는다 — 아래 예외로 간다
          if ml is null or jsonb_typeof(ml) <> 'object' then raise exception 'messageList 모양이 다르다'; end if;
          select e.key into mid
            from jsonb_each(ml) e
           where regexp_replace(coalesce(e.value ->> 'to', ''), '[^0-9]', '', 'g') = regexp_replace(r.phone, '[^0-9]', '', 'g')
             and e.value #>> '{kakaoOptions,templateId}' = tpl
             and (e.value ->> 'dateCreated')::timestamptz >= r.last_attempt_at - interval '1 minute'
           order by e.value ->> 'dateCreated'
           limit 1;
          parsed := true;
        exception when others then
          parsed := false;   -- 답 모양이 이상하다 → 아래에서 다시 묻는다 (한 줄 때문에 전체가 멈추지 않게)
        end;
      end if;

      if parsed and mid is not null then
        -- 이미 나가 있었다 — 다시 보내지 않는다
        update private.alimtalk_outbox
          set status = 'delivered', message_id = mid, checked_at = now(),
              verify_req_id = null, verify_result = 'sent'
          where id = r.id;
      elsif parsed then
        -- 정말 안 나갔다 — 이제 다시 보낸다
        if r.attempts >= 3 then
          update private.alimtalk_outbox set status = 'gaveup', checked_at = now(),
            verify_req_id = null, verify_result = 'not_sent' where id = r.id;
          perform private.otb_push('⚠️ 알림톡 발송 실패',
            coalesce((select contractor_name from public.bookings where id=r.booking_id),'') || ' · ' || private.atk_kname(r.template) || ' 발송실패(접수오류)', '/admin');
        else
          newreq := private.solapi_send(r.phone, 'tpl_' || r.template, r.vars);
          update private.alimtalk_outbox
            set req_id = newreq, attempts = attempts + 1, last_attempt_at = now(), checked_at = now(),
                verify_req_id = null, verify_result = 'not_sent'
            where id = r.id;
          n := n + 1;
        end if;
      elsif not got and r.last_attempt_at > now() - interval '30 minutes' then
        null;  -- 아직 답이 없다 → 다음 차례에 다시 본다
      elsif r.last_attempt_at < now() - interval '30 minutes' then
        -- 30분 넘게 나갔는지 모른다 — 짐작으로 또 보내지 않고 대표께 알린다
        update private.alimtalk_outbox set status = 'gaveup', checked_at = now(), verify_req_id = null where id = r.id;
        perform private.otb_push('⚠️ 알림톡 발송 확인 안 됨',
          coalesce((select contractor_name from public.bookings where id=r.booking_id),'') || ' · ' || private.atk_kname(r.template) || ' 나갔는지 확인 안 됨', '/admin');
      else
        -- 묻는 것이 실패했다 (시간 초과·2xx 아님·이상한 답) → 다시 묻는다
        update private.alimtalk_outbox
          set verify_req_id = private.solapi_list_req(r.phone, r.last_attempt_at - interval '1 minute'), checked_at = now()
          where id = r.id;
      end if;
      continue;
    end if;

    select status_code, error_msg, timed_out, content into resp from net._http_response where id = r.req_id;
    got := found;
    if got then
      ok := (resp.status_code between 200 and 299) and coalesce(resp.timed_out, false) = false and resp.error_msg is null;
      confirmed_fail := not ok;  -- 응답 왔는데 2xx 아님 = 확실한 실패(발송 안 됨)
    else
      ok := false; confirmed_fail := false;  -- 응답 없음 = 지연/대기 (실패 단정 안 함)
    end if;

    if ok then
      update private.alimtalk_outbox set status = 'delivered', checked_at = now(),
        message_id = coalesce(message_id, case when left(resp.content,1)='{' then (resp.content::jsonb)->>'messageId' end)
        where id = r.id;
    elsif got and coalesce(resp.timed_out, false) then
      -- ★ 시간 초과 = 솔라피가 받았는지 모른다 (2026-10-22: 이것을 실패로 보고 다시 보내 두 통이 갔다)
      --   다시 보내기 전에 나갔는지부터 묻는다. 답은 다음 차례에 (가) 에서 본다
      update private.alimtalk_outbox
        set verify_req_id = private.solapi_list_req(r.phone, r.last_attempt_at - interval '1 minute'), checked_at = now()
        where id = r.id;
    elsif confirmed_fail then
      if r.attempts >= 3 then
        update private.alimtalk_outbox set status = 'gaveup', checked_at = now() where id = r.id;
        perform private.otb_push('⚠️ 알림톡 발송 실패',
          coalesce((select contractor_name from public.bookings where id=r.booking_id),'') || ' · ' || private.atk_kname(r.template) || ' 발송실패(접수오류)', '/admin');
      else
        newreq := private.solapi_send(r.phone, 'tpl_' || r.template, r.vars);
        update private.alimtalk_outbox
          set req_id = newreq, attempts = attempts + 1, last_attempt_at = now(), checked_at = now()
          where id = r.id;
        n := n + 1;
      end if;
    else
      -- 응답 없음(지연): 15분까지 대기 후에도 없으면 재발송 없이 실패표시(중복 방지, 수동 확인용)
      if r.created_at < now() - interval '15 minutes' then
        update private.alimtalk_outbox set status = 'gaveup', checked_at = now() where id = r.id;
        perform private.otb_push('⚠️ 알림톡 발송 실패',
          coalesce((select contractor_name from public.bookings where id=r.booking_id),'') || ' · ' || private.atk_kname(r.template) || ' 발송실패(무응답)', '/admin');
      end if;
      -- 그 외엔 그대로 두고 다음 분에 재확인
    end if;
  end loop;
  return n;
end$function$;
