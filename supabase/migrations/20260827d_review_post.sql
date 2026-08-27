-- 홈페이지에 싣는 후기 (대표 요청 2026-08-27 «후기 모아보기같은것도 홈페이지에 게시되면 좋겠어»)
--
-- ⚠ `event_review` 와 **섞지 않는다.** 그쪽은 «이벤트 참여 기록» 이라 예약 한 건에 후기 한 건으로
--   묶여 있고 혜택(할인·앨범)과 참여율을 낸다. 대표가 따로 모아둔 옛 후기는 우리 예약에 없는
--   예식이라 그 표에 넣을 수 없고, 억지로 넣으면 참여율·혜택 숫자가 통째로 틀어진다.
--
-- 여기는 «무엇을 밖에 내보일지» 만 담는다. 담는 것도 **내보일 것만** 담는다 —
-- 공개 화면이 feedback·bookings 를 아예 안 건드리게 해서, 실수로 고객 정보가 새는 길을 없앤다.
--
-- 이름은 **넣을 때 이미 가려서** 담는다 (김지은 → 김○○). 원본 이름은 여기 안 들어온다.

create table if not exists public.review_post (
  id            uuid primary key default gen_random_uuid(),
  kind          text not null check (kind in ('link', 'survey')),
  url           text,                    -- kind='link' — 신부님이 블로그·카페에 올린 글
  body          text,                    -- kind='survey' — 우리 설문에 남겨주신 글 (옮겨 담는다)
  author_label  text,                    -- 「김○○」. 이름 전체는 넣지 않는다
  venue         text,
  wedding_date  date,
  site          text,                    -- 블로그 / 카페 / 인스타 / 기타
  published     boolean not null default true,
  sort_at       timestamptz not null default now(),
  src_booking_id uuid references public.bookings(id) on delete set null,  -- 어디서 왔는지 (관리자만 본다)
  created_at    timestamptz not null default now(),
  -- 링크 글은 주소가, 설문 글은 본문이 있어야 한다
  constraint review_post_has_content check (
    (kind = 'link' and coalesce(url, '') <> '') or (kind = 'survey' and coalesce(body, '') <> '')),
  -- 같은 글이 두 번 실리지 않게
  constraint review_post_no_dup_survey check (kind <> 'survey' or src_booking_id is not null)
);
create unique index if not exists review_post_url_uq on public.review_post(url) where kind = 'link';
create unique index if not exists review_post_survey_uq on public.review_post(src_booking_id) where kind = 'survey';
create index if not exists review_post_show on public.review_post(published, sort_at desc);

alter table public.review_post enable row level security;
revoke all on table public.review_post from anon, authenticated;

-- 이름 가리기: 김지은 → 김○○ / 김민 → 김○ / 한 글자면 그대로.
-- 성이 두 글자인 분(남궁·황보…)까지 맞추려 들지 않는다 — 더 가려지는 쪽이라 틀려도 안전하다
create or replace function private.mask_name(p text)
returns text language sql immutable set search_path=public, pg_temp as $$
  select case
    when coalesce(trim(p), '') = '' then ''
    when char_length(trim(p)) = 1 then trim(p)
    else left(trim(p), 1) || repeat('○', char_length(trim(p)) - 1)
  end
$$;

-- 링크를 보고 어디에 올린 글인지
create or replace function private.review_site(p_url text)
returns text language sql immutable set search_path=public, pg_temp as $$
  select case
    when p_url ~* 'blog[.]naver|blog[.]me'      then '블로그'
    when p_url ~* 'cafe[.]naver|cafe[.]daum'    then '카페'
    when p_url ~* 'instagram'                   then '인스타'
    when p_url ~* 'place[.]naver|naver[.]me'    then '플레이스'
    when p_url ~* 'blog[.]daum|tistory|brunch'  then '블로그'
    else '기타' end
$$;

/* ===== 손님이 보는 쪽 ===== */
-- 실은 것만, 가린 이름으로만 낸다. 여기서 나가는 칸에는 고객을 되짚을 것이 하나도 없다
drop function if exists public.reviews_public();
create or replace function public.reviews_public()
returns jsonb language sql stable security definer set search_path=public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', kind, 'url', url, 'body', body,
    'who', author_label, 'venue', venue,
    -- M 은 to_char 의 달 기호가 아니다(FMMM 이라야 앞 0 이 안 붙는다). 그냥 두면 «2026. M.» 이 나간다
    'ym', to_char(wedding_date, 'YYYY. FMMM.'), 'site', site)
    order by sort_at desc), '[]'::jsonb)
  from public.review_post where published
$$;
revoke all on function public.reviews_public() from public;
grant execute on function public.reviews_public() to anon, authenticated;

/* ===== 관리자 ===== */
drop function if exists public.admin_review_posts();
create or replace function public.admin_review_posts()
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
declare rows_ jsonb; cand jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'url', url, 'body', body, 'who', author_label,
    'venue', venue, 'wedding_date', to_char(wedding_date, 'YYYY-MM-DD'),
    'site', site, 'published', published) order by sort_at desc), '[]'::jsonb) into rows_
  from public.review_post;

  -- 아직 안 실은 것들 — 이벤트 링크와 설문 글을 한 자리에서 집어넣을 수 있게
  select coalesce(jsonb_agg(x order by x->>'d' desc), '[]'::jsonb) into cand from (
    select jsonb_build_object('kind','link', 'url', er.link,
      'who', private.mask_name(bk.contractor_name), 'venue', bk.wedding_venue,
      'wedding_date', to_char(bk.wedding_date,'YYYY-MM-DD'), 'booking_id', er.booking_id,
      'd', to_char(er.created_at,'YYYY-MM-DD')) as x
    from public.event_review er join public.bookings bk on bk.id = er.booking_id
    where er.link <> '(관리자 처리)'
      and not exists (select 1 from public.review_post p where p.url = er.link)
    union all
    select jsonb_build_object('kind','survey', 'body', f.message,
      'who', private.mask_name(bk.contractor_name), 'venue', bk.wedding_venue,
      'wedding_date', to_char(bk.wedding_date,'YYYY-MM-DD'), 'booking_id', f.booking_id,
      'd', to_char(f.created_at,'YYYY-MM-DD'))
    from public.feedback f join public.bookings bk on bk.id = f.booking_id
    where coalesce(f.message,'') <> ''
      and not exists (select 1 from public.review_post p where p.src_booking_id = f.booking_id and p.kind = 'survey')
  ) t;

  return jsonb_build_object('rows', rows_, 'candidates', cand,
    'n', jsonb_array_length(rows_),
    'shown', (select count(*)::int from public.review_post where published));
end$$;
revoke all on function public.admin_review_posts() from public, anon;
grant execute on function public.admin_review_posts() to authenticated;

-- 한 건 넣기 / 여러 건 한꺼번에 넣기. p_items = [{kind,url,body,who,venue,wedding_date,booking_id}]
-- who 는 **이미 가려진 것** 을 받는다. 전체 이름이 들어오면 여기서 가려 담는다
drop function if exists public.admin_review_post_add(jsonb);
create or replace function public.admin_review_post_add(p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
declare it jsonb; n int := 0; skipped int := 0; k text; u text; b text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if jsonb_typeof(p_items) <> 'array' then raise exception 'bad items'; end if;

  for it in select * from jsonb_array_elements(p_items) loop
    k := coalesce(it->>'kind', 'link');
    u := nullif(trim(coalesce(it->>'url','')), '');
    b := nullif(trim(coalesce(it->>'body','')), '');
    if k = 'link' then
      if u is null or u !~* '^https?://' then skipped := skipped + 1; continue; end if;
    elsif k = 'survey' then
      if b is null or (it->>'booking_id') is null then skipped := skipped + 1; continue; end if;
    else
      skipped := skipped + 1; continue;
    end if;

    insert into public.review_post(kind, url, body, author_label, venue, wedding_date, site, src_booking_id)
    values (k, u, b,
      private.mask_name(coalesce(it->>'who','')),
      nullif(trim(coalesce(it->>'venue','')), ''),
      nullif(it->>'wedding_date','')::date,
      case when k = 'link' then private.review_site(u) else '설문' end,
      nullif(it->>'booking_id','')::uuid)
    on conflict do nothing;                      -- 같은 글을 두 번 넣어도 조용히 넘어간다
    if found then n := n + 1; else skipped := skipped + 1; end if;
  end loop;

  return jsonb_build_object('ok', true, 'added', n, 'skipped', skipped);
end$$;
revoke all on function public.admin_review_post_add(jsonb) from public, anon;
grant execute on function public.admin_review_post_add(jsonb) to authenticated;

-- 켜고 끄기 / 지우기 — 누가 «내려달라» 하면 바로 내릴 수 있어야 한다 (대표 약속)
drop function if exists public.admin_review_post_set(uuid, text, jsonb);
create or replace function public.admin_review_post_set(p_id uuid, p_action text, p_patch jsonb default null)
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_action = 'show' then
    update public.review_post set published = true where id = p_id;
  elsif p_action = 'hide' then
    update public.review_post set published = false where id = p_id;
  elsif p_action = 'delete' then
    delete from public.review_post where id = p_id;
  elsif p_action = 'edit' then
    update public.review_post set
      author_label = coalesce(private.mask_name(nullif(p_patch->>'who','')), author_label),
      venue        = coalesce(nullif(trim(coalesce(p_patch->>'venue','')), ''), venue),
      wedding_date = coalesce(nullif(p_patch->>'wedding_date','')::date, wedding_date),
      body         = coalesce(nullif(trim(coalesce(p_patch->>'body','')), ''), body)
    where id = p_id;
  else raise exception 'bad action'; end if;
  return jsonb_build_object('ok', true);
end$$;
revoke all on function public.admin_review_post_set(uuid, text, jsonb) from public, anon;
grant execute on function public.admin_review_post_set(uuid, text, jsonb) to authenticated;
