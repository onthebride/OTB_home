/* 후기 페이지 — 촬영 후 설문 후기를 예식장별로 골라 보기 (대표 2026-10-17
   «우리 작가후기받은것도 예식장별로 골라볼 수 있게 해줘» → 「2번」 = 홈페이지 후기 페이지)

   무엇이 어려운가 — review_post.venue 는 손님이 예약할 때 **손으로 적은 글자**를 옮긴 것이다.
   「아펠가모 공덕(공덕)」 · 「공덕 아펠가모 마리에홀」 처럼 한 예식장이 여러 꼴로 적힌다.
   그대로 고르개를 만들면 한 곳이 여러 개로 갈리고, 이름도 길고 들쭉날쭉하다.

   그래서 고르개에 쓸 이름(place)을 따로 하나 더 낸다:
   ① 갤러리에 같은 예식장 이름표가 있으면 **그 이름표**를 쓴다 — 홈 갤러리 고르개와 이름이 같아진다.
      잇는 규칙은 private.venue_gal_pairs 한 곳 (작가 캘린더 「예식장 샘플보기」 와 같은 것) —
      브랜드만 같은 다른 지점(아펠가모 공덕 ↔ 광화문)은 잇지 않는다
   ② 없으면 같은 예식장(private.venue_canon — 대표가 이어주신 venue_alias 까지 본다)끼리 묶어
      **가장 짧게 적힌 이름**을 쓴다
   ③ 그것도 없으면 적힌 그대로

   ⚠ 카드에 찍히는 예식장(venue)은 그대로 둔다. place 는 고르개에만 쓴다.
   ⚠ 이 함수는 손님이 부른다(anon). place 는 venue 와 갤러리 이름표에서만 나온다 — 고객을 되짚을 것이 없다.
     feedback·bookings 는 여전히 안 건드린다. */

drop function if exists public.reviews_public();
create or replace function public.reviews_public()
returns jsonb language sql stable security definer set search_path=public, pg_temp as $$
  with p as (
    select r.*, nullif(trim(r.venue), '') as v, private.venue_canon(r.venue) as k
    from public.review_post r where r.published
  ),
  -- ① 적힌 이름 하나 → 갤러리 이름표 하나. 여럿에 걸리면 같은 예식장(canon)인 것을 먼저, 그다음 긴(자세한) 이름표
  gm as (
    select distinct on (x.venue_in) x.venue_in, x.gal_venue
    from private.venue_gal_pairs(array(select distinct p.v from p where p.v is not null)) x
    order by x.venue_in,
             (private.venue_canon(x.gal_venue) = private.venue_canon(x.venue_in)) desc,
             char_length(x.gal_venue) desc, x.gal_venue
  ),
  -- 같은 예식장(canon)으로 묶인 글 가운데 하나라도 갤러리 이름표에 이어지면, 그 묶음 전부 그 이름표로
  gk as (
    select distinct on (p.k) p.k, gm.gal_venue
    from p join gm on gm.venue_in = p.v
    where p.k <> ''
    order by p.k, char_length(gm.gal_venue) desc, gm.gal_venue
  ),
  -- ② 갤러리 이름표가 없는 묶음은 가장 짧게 적힌 이름으로
  lbl as (
    select distinct on (p.k) p.k, p.v
    from p where p.v is not null and p.k <> ''
    order by p.k, char_length(p.v), p.v
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', p.kind, 'url', p.url, 'body', p.body,
    -- 화면이 갈래에 따라 골라 쓴다. 둘 다 실어 보내되 who 는 **가려진 것**뿐이다
    'who', p.author_label, 'staff', p.staff_label, 'venue', p.venue,
    -- 묶음(gk)을 먼저 본다 — 글마다(gm) 먼저 보면 같은 예식장이 이름표 둘로 갈릴 수 있다
    'place', coalesce(gk.gal_venue, gm.gal_venue, lbl.v, p.v),
    -- M 은 to_char 의 달 기호가 아니다(FMMM 이라야 앞 0 이 안 붙는다). 그냥 두면 «2026. M.» 이 나간다
    'ym', to_char(p.wedding_date, 'YYYY. FMMM.'))
    order by p.sort_at desc), '[]'::jsonb)
  from p
  left join gm on gm.venue_in = p.v
  left join gk on gk.k = p.k
  left join lbl on lbl.k = p.k
$$;
revoke all on function public.reviews_public() from public;
grant execute on function public.reviews_public() to anon, authenticated;
