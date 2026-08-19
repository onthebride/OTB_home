-- 20260819_staff_survey_alimtalk.sql
-- 예식 전날, 담당 작가에게 그 신부가 쓴 '예식 전 설문' 링크를 알림톡으로 보낸다(템플릿 T, 작가 채널).
-- 설문은 예약(신부)별이라 작가가 그날 두 건을 맡으면 두 통을 받는다.
-- 자동 발송은 하지 않는다 — '오늘 할 일'에 뜨고 대표가 [발송]을 눌러야 나간다.

insert into private.solapi (key, val)
values ('pf_tpl_T', 'KA01PF260818115233528kx6XV9fSau5')   -- 작가 채널
on conflict (key) do update set val = excluded.val;

-- 작가에게 보여줄 예식 정보 한 줄: "8월 29일(토) 오후 1:30 · 아펠가모 선릉 · 신부 김하늘"
create or replace function private.wedding_line(b public.bookings)
returns text language sql stable set search_path = public, pg_temp as $fn$
  select trim(both ' ·' from concat_ws(' · ',
    to_char(b.wedding_date, 'FMMM월 FMDD일')
      || '(' || (array['일','월','화','수','목','금','토'])[extract(dow from b.wedding_date)::int + 1] || ')'
      || coalesce(' ' || nullif(public.fmt_ktime(b.wedding_time), ''), ''),
    nullif(b.wedding_venue, ''),
    case when coalesce(nullif(b.bride_name,''), nullif(b.contractor_name,'')) is null then null
         else '신부 ' || coalesce(nullif(b.bride_name,''), b.contractor_name) end
  ));
$fn$;

-- 내일 예식 + 배정된 작가 목록 (메인·서브 각각 한 줄)
create or replace function public.admin_staff_survey_targets()
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $fn$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(t order by t.wedding_time nulls last, t.staff_name), '[]'::jsonb) into res from (
    select b.id as booking_id, s.id as staff_id, s.name as staff_name,
           (s.phone is not null and s.phone <> '') as has_phone,
           case when b.assignee_id = s.id then '메인' else '서브' end as role,
           b.wedding_time, private.wedding_line(b) as line,
           exists(select 1 from public.surveys sv where sv.booking_id = b.id) as has_survey,
           (coalesce(b.alimtalk_sent, '{}'::jsonb) -> ('T:' || s.id::text)) is not null as sent
    from public.bookings b
    join public.staff s on (s.id = b.assignee_id or s.id = b.sub_assignee_id)
    where b.status <> '취소' and b.wedding_date = current_date + 1
  ) t;
  return res;
end$fn$;
revoke all on function public.admin_staff_survey_targets() from public, anon;
grant execute on function public.admin_staff_survey_targets() to authenticated;

-- 발송. 같은 예약·작가에 두 번 보내지 않도록 alimtalk_sent 에 'T:<작가ID>' 로 표시한다
-- (템플릿 T 는 예약 하나에 작가 두 명까지 갈 수 있어 키를 작가별로 나눈다).
create or replace function public.admin_send_staff_survey(p_booking_id uuid, p_staff_id uuid)
returns jsonb language plpgsql security definer set search_path = public, private, extensions, pg_temp as $fn$
declare b public.bookings; st public.staff; vars jsonb; req bigint; line text; has_sv boolean;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select * into b from public.bookings where id = p_booking_id;
  if not found then raise exception 'booking not found'; end if;
  select * into st from public.staff where id = p_staff_id;
  if not found then raise exception 'staff not found'; end if;
  if st.phone is null or st.phone = '' then raise exception '작가 연락처가 없습니다'; end if;
  if b.assignee_id is distinct from p_staff_id and b.sub_assignee_id is distinct from p_staff_id then
    raise exception '이 예식에 배정된 작가가 아닙니다';
  end if;

  select exists(select 1 from public.surveys sv where sv.booking_id = b.id) into has_sv;
  line := private.wedding_line(b) || case when has_sv then '' else ' (설문 미작성)' end;

  vars := jsonb_build_object('#{작가명}', coalesce(st.name,''), '#{예식정보}', line, '#{예약ID}', b.id::text);
  req := private.alimtalk_dispatch(b.id, 'T', st.phone, vars);
  update public.bookings
     set alimtalk_sent = coalesce(alimtalk_sent,'{}'::jsonb) || jsonb_build_object('T:' || p_staff_id::text, to_jsonb(now()))
   where id = b.id;
  return jsonb_build_object('ok', true, 'req', req, 'staff', st.name, 'line', line);
end$fn$;
revoke all on function public.admin_send_staff_survey(uuid, uuid) from public, anon;
grant execute on function public.admin_send_staff_survey(uuid, uuid) to authenticated;

-- 실패 알림 문구
create or replace function private.atk_kname(p text) returns text language sql immutable as $fn$
  select case p when 'A' then '계약안내' when 'B' then '한달전' when 'C' then '잔금안내' when 'D' then '최종안내'
                when 'E' then '링크안내' when 'F' then '입금확인' when 'G' then '촬영 설문'
                when 'S' then '작가 스케줄확인' when 'T' then '작가 설문안내' else p end;
$fn$;

-- '오늘 할 일' 생성기 재작성. 기존 동작(7일 지난 알림 정리, 월요일 스케줄 체크 알림)은 그대로 두고,
-- 예약마다 한 줄씩 뜨던 '설문 공유'만 한 줄로 묶는다(거기서 바로 일괄 발송할 수 있게).
create or replace function private.generate_admin_reminders()
returns int language plpgsql security definer set search_path=private, public, extensions, pg_temp as $fn$
declare
  today_kst date := (now() at time zone 'Asia/Seoul')::date;
  r record;
  wk_cnt int; wk_staff int;
  n_new int := 0;
  n_t int := 0; names text := '';
begin
  -- 오래된 알림 정리 (기존 동작)
  update public.admin_reminders
     set dismissed = true, dismissed_at = now()
   where not dismissed and due_date < today_kst - 7;

  -- 월요일: 작가 스케줄 체크 (대표 규칙 = 월요일 기준 +3 ~ +9 일 예식)
  if extract(dow from today_kst) = 1 then
    select count(*), count(distinct s.id) into wk_cnt, wk_staff
      from public.bookings b
      join public.staff s on (s.id = b.assignee_id or s.id = b.sub_assignee_id)
     where b.status <> '취소' and s.active
       and b.wedding_date between today_kst + 3 and today_kst + 9;
    insert into public.admin_reminders (kind, due_date, title, body, url)
    values ('weekly_schedule', today_kst,
            '작가 스케줄 톡 발송' || case when wk_staff > 0 then ' (' || wk_staff || '명)' else '' end,
            case when wk_cnt > 0
                 then to_char(today_kst + 3, 'FMMM/FMDD') || '~' || to_char(today_kst + 9, 'FMMM/FMDD')
                      || ' 예식 ' || wk_cnt || '건'
                 else '이번 주기에는 예식이 없습니다.' end,
            '/admin')
    on conflict do nothing;
    if found then
      n_new := n_new + 1;
      perform private.otb_push('🗓 작가 스케줄 톡',
        case when wk_cnt > 0 then '작가 ' || wk_staff || '명 · 예식 ' || wk_cnt || '건 — 관리자에서 발송하세요.'
             else '이번 주기에는 예식이 없습니다.' end, '/admin');
    end if;
  end if;

  -- 매일: 내일 예식 담당 작가에게 설문 안내 (한 줄로 묶음)
  for r in
    select coalesce(nullif(b.bride_name,''), nullif(b.contractor_name,''), '고객') as who
    from public.bookings b
    where b.status <> '취소' and b.wedding_date = today_kst + 1 and b.assignee_id is not null
    order by b.wedding_time nulls last
  loop
    n_t := n_t + 1;
    names := names || case when names = '' then '' else ', ' end || r.who;
  end loop;

  if n_t > 0 then
    insert into public.admin_reminders (kind, due_date, title, body, url)
    values ('staff_survey', today_kst,
            '작가에게 설문 안내 발송 (내일 예식 ' || n_t || '건)', names, '/admin')
    on conflict do nothing;
    if found then
      n_new := n_new + 1;
      perform private.otb_push('📋 작가 설문 안내',
        '내일 예식 ' || n_t || '건 · ' || names || ' — 관리자에서 발송하세요.', '/admin');
    end if;
  end if;

  return n_new;
end$fn$;
revoke all on function private.generate_admin_reminders() from public, anon, authenticated;
