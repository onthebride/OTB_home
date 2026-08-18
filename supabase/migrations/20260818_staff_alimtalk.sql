-- 20260818_staff_alimtalk.sql
-- 작가 전용 카카오톡 채널(otb0416)로 '스케줄 확인' 알림톡을 보내기 위한 배관.
--
-- 지금까지 solapi_send 는 발신프로필(pf_id)을 하나만 읽어서 모든 알림톡이 손님 채널로
-- 나갔다. 작가에게는 작가 채널로 나가야 하므로, 템플릿별로 발신프로필을 고를 수 있게 한다.
--   private.solapi 에 'pf_' || 템플릿키 가 있으면 그 채널로, 없으면 기존 'pf_id'(손님 채널).
--   예: pf_tpl_S = 작가 채널

insert into private.solapi (key, val)
values ('pf_tpl_S', 'KA01PF260818115233528kx6XV9fSau5')
on conflict (key) do update set val = excluded.val;

create or replace function private.solapi_send(p_to text, p_template_key text, p_vars jsonb)
returns bigint language plpgsql security definer set search_path=private, public, extensions, pg_temp as $fn$
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
    headers := jsonb_build_object('Content-Type','application/json','Authorization',hdr)
  ) into req;
  return req;
end$fn$;

-- ── 작가에게 스케줄 확인 알림톡 (템플릿 S) ─────────────────────
-- 예약 건별이 아니라 작가 1명당 1통. 링크는 그 작가의 전체 일정 페이지(staff_schedule).
create or replace function public.admin_send_staff_check(p_staff_id uuid)
returns jsonb language plpgsql security definer set search_path=public, private, extensions, pg_temp as $fn$
declare st public.staff; req bigint; vars jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select * into st from public.staff where id = p_staff_id;
  if not found then raise exception 'staff not found'; end if;
  if st.phone is null or st.phone = '' then raise exception '작가 연락처가 없습니다'; end if;

  vars := jsonb_build_object('#{작가명}', coalesce(st.name, ''), '#{작가ID}', st.id::text);
  req := private.alimtalk_dispatch(null, 'S', st.phone, vars);   -- 예약 1건에 묶이지 않으므로 booking_id 는 null
  return jsonb_build_object('ok', true, 'req', req, 'staff', st.name);
end$fn$;
revoke all on function public.admin_send_staff_check(uuid) from public, anon;
grant execute on function public.admin_send_staff_check(uuid) to authenticated;

-- 확인이 필요한 작가 목록 — 앞으로 예식이 있는데 아직 체크 안 한 작가(메인·서브 모두)
create or replace function public.admin_staff_check_targets()
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $fn$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(t order by t.unchecked desc, t.name), '[]'::jsonb) into res from (
    select s.id, s.name, (s.phone is not null and s.phone <> '') as has_phone,
           count(*) filter (where c.checked_at is null) as unchecked,
           count(*) as total,
           min(b.wedding_date) as nearest
    from public.staff s
    join public.bookings b
      on (b.assignee_id = s.id or b.sub_assignee_id = s.id)
     and b.status <> '취소'
     and b.wedding_date >= current_date
    left join public.assignment_checks c on c.booking_id = b.id and c.staff_id = s.id
    where s.active
    group by s.id, s.name, s.phone
    having count(*) filter (where c.checked_at is null) > 0
  ) t;
  return res;
end$fn$;
revoke all on function public.admin_staff_check_targets() from public, anon;
grant execute on function public.admin_staff_check_targets() to authenticated;

-- 실패 알림 문구에 S 추가
create or replace function private.atk_kname(p text) returns text language sql immutable as $fn$
  select case p when 'A' then '계약안내' when 'B' then '한달전' when 'C' then '잔금안내' when 'D' then '최종안내'
                when 'E' then '링크안내' when 'F' then '입금확인' when 'G' then '촬영 설문'
                when 'S' then '작가 스케줄확인' else p end;
$fn$;
