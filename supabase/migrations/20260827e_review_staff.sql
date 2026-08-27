-- 후기에 «누가 찍었는지» 를 싣는다 (대표 요청 2026-08-27 «신부이름대신 작가이름으로 변경»).
--
-- 대표가 세운 판매 방향과 맞닿아 있다 — «포트폴리오만 봐서는 누가 찍었는지 알 수 없다.
-- 그게 결과물을 가른다». 후기마다 작가 이름이 붙으면 그 근거가 된다.
--
-- 곁들여 얻는 것: **신부님 이름을 아예 안 내보내게 된다.** 가려 담긴 했지만
-- 내보내지 않는 것이 더 낫다. `reviews_public()` 에서 who 를 뺀다.

alter table public.review_post add column if not exists staff_label text;

-- 이미 실어둔 것들에 작가 이름을 채운다.
--   설문 글  → feedback.staff_id (그 예식을 찍은 사람이 설문에 박혀 있다)
--   링크 글  → bookings.assignee_id (그 예식의 메인)
update public.review_post p set staff_label = st.name
from public.feedback f join public.staff st on st.id = f.staff_id
where p.kind = 'survey' and p.src_booking_id = f.booking_id and p.staff_label is null;

update public.review_post p set staff_label = st.name
from public.bookings b join public.staff st on st.id = b.assignee_id
where p.kind = 'link' and p.src_booking_id = b.id and p.staff_label is null;

/* ===== 손님이 보는 쪽 — 이제 신부님 이름은 아예 안 나간다 ===== */
drop function if exists public.reviews_public();
create or replace function public.reviews_public()
returns jsonb language sql stable security definer set search_path=public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', kind, 'url', url, 'body', body,
    'staff', staff_label, 'venue', venue,
    -- M 은 to_char 의 달 기호가 아니다(FMMM 이라야 앞 0 이 안 붙는다). 그냥 두면 «2026. M.» 이 나간다
    'ym', to_char(wedding_date, 'YYYY. FMMM.'))
    order by sort_at desc), '[]'::jsonb)
  from public.review_post where published
$$;
revoke all on function public.reviews_public() from public;
grant execute on function public.reviews_public() to anon, authenticated;

/* ===== 관리자 — 후보에도 작가를 실어 보낸다 ===== */
drop function if exists public.admin_review_posts();
create or replace function public.admin_review_posts()
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
declare rows_ jsonb; cand jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'url', url, 'body', body, 'who', author_label,
    'staff', staff_label, 'venue', venue,
    'wedding_date', to_char(wedding_date, 'YYYY-MM-DD'),
    'site', site, 'published', published) order by sort_at desc), '[]'::jsonb) into rows_
  from public.review_post;

  -- 아직 안 실은 것들 — 이벤트 링크와 설문 글을 한 자리에서 집어넣을 수 있게
  select coalesce(jsonb_agg(x order by x->>'d' desc), '[]'::jsonb) into cand from (
    select jsonb_build_object('kind','link', 'url', er.link,
      'who', private.mask_name(bk.contractor_name), 'staff', ast.name, 'venue', bk.wedding_venue,
      'wedding_date', to_char(bk.wedding_date,'YYYY-MM-DD'), 'booking_id', er.booking_id,
      'd', to_char(er.created_at,'YYYY-MM-DD')) as x
    from public.event_review er
    join public.bookings bk on bk.id = er.booking_id
    left join public.staff ast on ast.id = bk.assignee_id
    where er.link <> '(관리자 처리)'
      and not exists (select 1 from public.review_post p where p.url = er.link)
    union all
    select jsonb_build_object('kind','survey', 'body', f.message,
      'who', private.mask_name(bk.contractor_name), 'staff', fst.name, 'venue', bk.wedding_venue,
      'wedding_date', to_char(bk.wedding_date,'YYYY-MM-DD'), 'booking_id', f.booking_id,
      'd', to_char(f.created_at,'YYYY-MM-DD'))
    from public.feedback f
    join public.bookings bk on bk.id = f.booking_id
    left join public.staff fst on fst.id = f.staff_id
    where coalesce(f.message,'') <> ''
      and not exists (select 1 from public.review_post p where p.src_booking_id = f.booking_id and p.kind = 'survey')
  ) t;

  return jsonb_build_object('rows', rows_, 'candidates', cand,
    'n', jsonb_array_length(rows_),
    'shown', (select count(*)::int from public.review_post where published),
    -- 작가 이름이 비어 있으면 화면에 「작가 미지정」 으로 뜬다. 몇 건인지 알려준다
    'no_staff', (select count(*)::int from public.review_post where coalesce(staff_label,'') = ''));
end$$;
revoke all on function public.admin_review_posts() from public, anon;
grant execute on function public.admin_review_posts() to authenticated;

-- 넣을 때도 작가를 같이 담는다. 안 주면 예약에서 찾아 채운다
drop function if exists public.admin_review_post_add(jsonb);
create or replace function public.admin_review_post_add(p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
declare it jsonb; n int := 0; skipped int := 0; k text; u text; b text; bid uuid; sname text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if jsonb_typeof(p_items) <> 'array' then raise exception 'bad items'; end if;

  for it in select * from jsonb_array_elements(p_items) loop
    k := coalesce(it->>'kind', 'link');
    u := nullif(trim(coalesce(it->>'url','')), '');
    b := nullif(trim(coalesce(it->>'body','')), '');
    bid := nullif(it->>'booking_id','')::uuid;
    if k = 'link' then
      if u is null or u !~* '^https?://' then skipped := skipped + 1; continue; end if;
    elsif k = 'survey' then
      if b is null or bid is null then skipped := skipped + 1; continue; end if;
    else
      skipped := skipped + 1; continue;
    end if;

    -- 손으로 적어준 이름이 있으면 그것을, 없고 예약을 알면 거기서 찾아 채운다
    sname := nullif(trim(coalesce(it->>'staff','')), '');
    if sname is null and bid is not null then
      select st.name into sname from public.bookings bk
        join public.staff st on st.id = bk.assignee_id where bk.id = bid;
    end if;

    insert into public.review_post(kind, url, body, author_label, staff_label, venue, wedding_date, site, src_booking_id)
    values (k, u, b,
      private.mask_name(coalesce(it->>'who','')), sname,
      nullif(trim(coalesce(it->>'venue','')), ''),
      nullif(it->>'wedding_date','')::date,
      case when k = 'link' then private.review_site(u) else '설문' end,
      bid)
    on conflict do nothing;                      -- 같은 글을 두 번 넣어도 조용히 넘어간다
    if found then n := n + 1; else skipped := skipped + 1; end if;
  end loop;

  return jsonb_build_object('ok', true, 'added', n, 'skipped', skipped);
end$$;
revoke all on function public.admin_review_post_add(jsonb) from public, anon;
grant execute on function public.admin_review_post_add(jsonb) to authenticated;

-- 고칠 때도 작가를 바꿀 수 있게
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
      staff_label  = coalesce(nullif(trim(coalesce(p_patch->>'staff','')), ''), staff_label),
      venue        = coalesce(nullif(trim(coalesce(p_patch->>'venue','')), ''), venue),
      wedding_date = coalesce(nullif(p_patch->>'wedding_date','')::date, wedding_date),
      body         = coalesce(nullif(trim(coalesce(p_patch->>'body','')), ''), body)
    where id = p_id;
  else raise exception 'bad action'; end if;
  return jsonb_build_object('ok', true);
end$$;
revoke all on function public.admin_review_post_set(uuid, text, jsonb) from public, anon;
grant execute on function public.admin_review_post_set(uuid, text, jsonb) to authenticated;

-- 배정이 나중에 되면 작가 이름이 비어 있던 것들을 다시 채운다.
-- 이름은 «옮겨 담은» 값이라 예약이 바뀌어도 저절로 안 따라온다 — 비어 있는 것만 손본다
-- (이미 적힌 것을 덮어쓰면 대표가 손으로 고쳐둔 것을 지운다)
create or replace function public.admin_review_post_refill()
returns jsonb language plpgsql security definer set search_path=public, pg_temp as $$
declare n int := 0; m int := 0;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;

  update public.review_post p set staff_label = st.name
  from public.feedback f join public.staff st on st.id = f.staff_id
  where p.kind = 'survey' and p.src_booking_id = f.booking_id and coalesce(p.staff_label,'') = '';
  get diagnostics n = row_count;

  update public.review_post p set staff_label = st.name
  from public.bookings b join public.staff st on st.id = b.assignee_id
  where p.kind = 'link' and p.src_booking_id = b.id and coalesce(p.staff_label,'') = '';
  get diagnostics m = row_count;

  return jsonb_build_object('ok', true, 'filled', n + m,
    'left', (select count(*)::int from public.review_post where coalesce(staff_label,'') = ''));
end$$;
revoke all on function public.admin_review_post_refill() from public, anon;
grant execute on function public.admin_review_post_refill() to authenticated;
