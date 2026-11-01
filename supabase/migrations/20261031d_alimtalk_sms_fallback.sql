-- 알림톡이 실패하면 같은 글을 문자(장문)로 대신 보낸다 (2026-10-31 대표 «4번은 하자»)
--
-- 그날 11/1 경원재 신부님께 한달 전·일주일 전·전날 안내톡이 셋 다 실패(3058)했다. 문자 대체가 꺼져 있어
-- 신부님은 아무것도 못 받았고, 관리자 홈 빨간 칸을 봐야만 알 수 있었다.
--
-- 솔라피는 알림톡 발송에 「등록된 발신번호(from)」 를 함께 주면, 실패할 때 저절로 문자로 다시 보낸다
-- (kakaoOptions.disableSms 기본값 false). 지금은 from 이 비어 있어서 그대로 실패로 끝났다.
--   · 문자 글 = 템플릿 글 그대로, 단추는 「이름 + 주소」 가 글 안에 들어간다 (솔라피 대체발송 문서)
--   · 값: 알림톡 값은 돌려받고 문자 값(장문 45원)이 나간다. 반년 760통 중 실패 5통
-- ⚠ 발신번호는 이 파일에 적지 않는다 (저장소가 공개). 운영 DB private.solapi 의 'sms_from' 에만 둔다.
--   그 줄이 없으면 지금과 똑같이 from 없이 나간다 — 이 파일만 돌려서는 아무것도 안 바뀐다.
--
-- 결과 확인(alimtalk_check_delivery)도 맞춘다. 대체되면 솔라피는 원래 알림톡에 실패 코드를 두고
-- replacements 에 대신 보낸 문자를 단다(모양을 아직 진짜로 본 적이 없다 — 받은 그대로 sms_info 에 남긴다).
--   · replacements 에 문자 번호가 있으면 → 그 문자를 따라가 결과를 본다 (4000 이면 completed)
--   · 문자 결과가 바로 붙어 있으면 → 그것으로 판단
--   · 알림톡이 막 실패했는데 대체가 아직 안 붙었으면 → 10분까지 기다렸다 다시 본다
--   · 그 밖에는 지금처럼 실패. 문자까지 실패했으면 폰 알림 글에 그렇게 적는다
-- ⚠ 성공(문자로 간 것 포함)은 관리자 홈에 안 띄운다 — 대표 2026-10-15 «실패 하는것만 알려줘»

alter table private.alimtalk_outbox
  add column if not exists via text,              -- 'sms' = 알림톡 실패 → 문자로 대신 감
  add column if not exists ata_message_id text,   -- 문자로 넘어가기 전 알림톡 메시지 번호
  add column if not exists ata_fail_code text,    -- 그때 알림톡 실패 코드
  add column if not exists sms_info jsonb;        -- 솔라피가 준 replacements 그대로

-- 발신번호(from)만 더한다. 나머지는 한 글자도 안 바꾼다 (staff.test · atknodouble.test 가 본문을 본다)
create or replace function private.solapi_send(p_to text, p_template_key text, p_vars jsonb)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $function$
declare k text; s text; pf text; tpl text; dt text; salt text; sig text; hdr text; req bigint;
  fr text; msg jsonb;
begin
  select val into k from private.solapi where key='api_key';
  select val into s from private.solapi where key='api_secret';
  -- 템플릿 전용 발신프로필이 있으면 그것을, 없으면 기본(손님 채널)
  select val into pf from private.solapi where key = 'pf_' || p_template_key;
  if pf is null then select val into pf from private.solapi where key='pf_id'; end if;
  select val into tpl from private.solapi where key=p_template_key;
  if k is null or tpl is null then raise exception 'solapi not configured (%)', p_template_key; end if;
  -- 알림톡이 실패하면 이 번호로 문자를 대신 보낸다 (솔라피에 등록된 발신번호)
  select nullif(regexp_replace(val, '[^0-9]', '', 'g'), '') into fr from private.solapi where key = 'sms_from';
  dt := to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  salt := encode(gen_random_bytes(32), 'hex');
  sig := encode(hmac(dt || salt, s, 'sha256'), 'hex');
  hdr := 'HMAC-SHA256 apiKey=' || k || ', date=' || dt || ', salt=' || salt || ', signature=' || sig;
  msg := jsonb_build_object(
      'to', regexp_replace(p_to, '[^0-9]', '', 'g'),
      'kakaoOptions', jsonb_build_object('pfId', pf, 'templateId', tpl, 'variables', p_vars));
  if fr is not null then msg := msg || jsonb_build_object('from', fr); end if;
  select net.http_post(
    url := 'https://api.solapi.com/messages/v4/send',
    body := jsonb_build_object('message', msg),
    headers := jsonb_build_object('Content-Type','application/json','Authorization',hdr),
    -- 5초(기본)면 10시 묶음 발송 때 답이 늦어 「시간 초과」 가 났다 (2026-10-22)
    timeout_milliseconds := 20000
  ) into req;
  return req;
end$function$;

create or replace function private.alimtalk_check_delivery()
 returns integer
 language plpgsql
 security definer
 set search_path to 'private', 'public', 'extensions', 'pg_temp'
as $function$
declare r record; resp record; sc text; n int := 0; req bigint;
  k text; s text; dt text; salt text; sig text; hdr text;
  m jsonb; reps jsonb; rid text; rsc text; upd timestamptz;
begin
  select val into k from private.solapi where key='api_key';
  select val into s from private.solapi where key='api_secret';
  if k is null or s is null then return 0; end if;

  -- (A) 조회 응답 수집
  for r in
    select id, message_id, report_req_id, booking_id, template, via from private.alimtalk_outbox
    where status='delivered' and report_req_id is not null order by id limit 100
  loop
    select status_code, content into resp from net._http_response where id = r.report_req_id;
    if not found then
      continue;  -- 아직 응답 없음 → 다음 사이클
    end if;
    if resp.status_code between 200 and 299 and left(resp.content,1)='{' then
      m := (resp.content::jsonb) #> array['messageList', r.message_id];
      sc := m ->> 'statusCode';
      reps := case when jsonb_typeof(m -> 'replacements') = 'array' then m -> 'replacements' else '[]'::jsonb end;
      if sc = '4000' then
        update private.alimtalk_outbox set status='completed', report_checked_at=now(), report_req_id=null,
          via = case when m ->> 'replacement' = 'true' then 'sms' else via end
          where id=r.id;
      elsif sc is null or sc in ('2000','3000') then
        update private.alimtalk_outbox set report_req_id=null where id=r.id;  -- 진행중 → 재조회
      elsif jsonb_array_length(reps) > 0 then
        -- 알림톡은 실패했고 솔라피가 문자로 대신 보냈다
        select coalesce(e ->> 'messageId', e ->> '_id') into rid from jsonb_array_elements(reps) e
         where coalesce(e ->> 'messageId', e ->> '_id') is not null and coalesce(e ->> 'messageId', e ->> '_id') <> r.message_id
         limit 1;
        select e ->> 'statusCode' into rsc from jsonb_array_elements(reps) e where e ->> 'statusCode' is not null limit 1;
        if rid is not null then
          -- 그 문자를 따라간다 — 다음 사이클에 문자 번호로 결과를 묻는다
          update private.alimtalk_outbox set via='sms', sms_info=reps,
            ata_message_id = coalesce(ata_message_id, message_id), ata_fail_code = coalesce(ata_fail_code, sc),
            message_id = rid, report_req_id=null where id=r.id;
        elsif rsc = '4000' then
          update private.alimtalk_outbox set status='completed', via='sms', sms_info=reps,
            ata_fail_code = coalesce(ata_fail_code, sc), report_checked_at=now(), report_req_id=null where id=r.id;
        elsif rsc is null or rsc in ('2000','3000') then
          update private.alimtalk_outbox set via='sms', sms_info=reps,
            ata_fail_code = coalesce(ata_fail_code, sc), report_req_id=null where id=r.id;  -- 문자 진행중 → 재조회
        else
          update private.alimtalk_outbox set status='failed', fail_code=rsc, via='sms', sms_info=reps,
            ata_fail_code = coalesce(ata_fail_code, sc),
            rendered_text = m ->> 'text', report_checked_at=now(), report_req_id=null where id=r.id;
          perform private.otb_push('⚠️ 알림톡 전달 실패',
            coalesce((select contractor_name from public.bookings where id=r.booking_id),'') || ' · ' || private.atk_kname(r.template) || ' 알림톡·문자 모두 전달실패', '/admin');
          n := n + 1;
        end if;
      else
        begin upd := (m ->> 'dateUpdated')::timestamptz; exception when others then upd := null; end;
        if m ->> 'type' = 'ATA' and m #>> '{kakaoOptions,disableSms}' = 'false'
           and coalesce(m ->> 'unavailableSenderNumber', 'false') = 'false'
           and upd > now() - interval '10 minutes' then
          -- 알림톡이 막 실패했다 — 대신 보낼 문자가 아직 안 붙었을 수 있다. 조금 더 기다린다
          update private.alimtalk_outbox set report_req_id=null where id=r.id;
        else
          update private.alimtalk_outbox set status='failed', fail_code=sc,
            rendered_text = m ->> 'text',
            report_checked_at=now(), report_req_id=null where id=r.id;
          perform private.otb_push('⚠️ 알림톡 전달 실패',
            coalesce((select contractor_name from public.bookings where id=r.booking_id),'') || ' · ' || private.atk_kname(r.template)
              || case when r.via = 'sms' then ' 알림톡·문자 모두 전달실패' else ' 전달실패' end, '/admin');
          n := n + 1;
        end if;
      end if;
    else
      update private.alimtalk_outbox set report_req_id=null where id=r.id;  -- 비정상 응답 → 재조회
    end if;
  end loop;

  -- (B) 미확인 접수건 조회요청 발사 (접수 2분 경과, 3일 이내)
  for r in
    select id, message_id from private.alimtalk_outbox
    where status='delivered' and message_id is not null and report_req_id is null and report_checked_at is null
      and created_at < now() - interval '2 minutes' and created_at > now() - interval '3 days'
    order by id limit 50
  loop
    dt := to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
    salt := encode(gen_random_bytes(32), 'hex');
    sig := encode(hmac(dt || salt, s, 'sha256'), 'hex');
    hdr := 'HMAC-SHA256 apiKey=' || k || ', date=' || dt || ', salt=' || salt || ', signature=' || sig;
    select net.http_get(
      url := 'https://api.solapi.com/messages/v4/list?messageId=' || r.message_id,
      headers := jsonb_build_object('Authorization', hdr)
    ) into req;
    update private.alimtalk_outbox set report_req_id = req where id = r.id;
  end loop;

  return n;
end$function$;
