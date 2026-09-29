/* 작가 캘린더 「예식장 샘플보기」 (대표 2026-09-29)

   «작가 캘린더 상단에 몇일 후 스케줄 뜨잖아? 거기 예식장 촬영샘플을 우리 갤러리에서 끌어와서
    보여줬음 하는데 / 눌러서 보이게 하고 하나씩 넘겨볼 수 있게»
   «캘린더 위쪽에 사진을 넣는게 아니고 / 예식장 샘플보기 누르면 팝업으로 사진 볼 수 있게
    일단 내 캘린더에만 적용해서 보여주고 전체 공개»

   ── 무엇을 하나
   예식 카드에 「예식장 샘플보기」 단추를 달고, 누르면 그 예식장에서 찍은 갤러리 사진을 넘겨 본다.
   ⚠ 새로 여는 것이 아니다. 갤러리 사진은 이미 홈에 공개돼 있다 (gallery_public).
   ⚠ **앞으로 있을 촬영만.** 지난 예식은 준비할 것이 없다.

   ── 어떻게 잇나 (이게 이 판의 거의 전부다)
   예약의 예식장은 **손님이 적은 글**이고, 갤러리의 예식장은 **대표가 붙인 이름표**다.
     예약    「서울 신도림 라마다 호텔」 「신도림라마다호텔 하늘정원홀」 「계산CN」
     갤러리  「라마다호텔-신도림」                                  「cn웨딩홀-계산」
   ① 이름을 묶은 키(private.venue_canon)가 같으면 같은 곳이다.
      배정 화면 「이 예식장 가본 작가」 가 쓰는 셈 그대로다 (대표가 이어두신 venue_alias 까지 따른다)
   ② 갤러리 이름표의 낱말이 **전부** 예약 이름 안에 들어 있으면 같은 곳이다.
      띄어쓰기·기호는 떼고 본다. 낱말 꼬리의 호텔·웨딩홀·컨벤션 따위도 떼고 본다
      (「라마다호텔」 → 「라마다」 — 「신도림 라마다 그랜드볼룸」 에는 「호텔」 이 없다)
   2026-09-29 실측: 앞으로 예약 182건 중 ①만으로는 67건(37%), ①②로 **104건(57%)**.
   나머지는 갤러리에 그 예식장 사진이 아예 없다 (더베뉴지서울 3 · 아펠가모 반포 3 · 아벤티움 …).
   ②로만 이어지는 것을 작가 이력의 예식장 이름 2,111개에 걸어 **하나씩 눈으로 봤다** —
   틀린 곳에 붙는 것은 아래 셋(월드컵·롯데호텔·노블발렌티)뿐이었고 셋 다 막았다.

   ⚠⚠ **틀린 예식장을 보여주지 않는다 — 못 잇는 것보다 나쁘다.**
     · 지점 없이 **브랜드만** 적힌 이름표(「아펠가모」·「더컨벤션」·「메리빌리아」)는 ②로 잇지 않는다.
       「아펠가모 반포」 예식에 어느 지점인지 모르는 사진이 붙는다.
       갤러리에 같은 브랜드의 지점 이름표(「아펠가모-광화문」)가 따로 있으면 브랜드만 적힌 것으로 본다.
     · 지점이 여럿인 브랜드 목록(public.venue_stem_block)에 있는 것도 ②로 잇지 않는다.
       「롯데호텔」 ≠ 「L7 광명 바이 롯데호텔」 — 이 판에서 그 목록에 「롯데호텔」·「노블발렌티」 를 넣는다
     · 떼고 남은 것이 짧으면 안 뗀다. 「공군호텔」 → 「공군」 은 너무 넓다. **세 글자부터**.
       이름표 낱말이 둘 이상이면 서로 좁혀주니 두 글자도 된다 (「cn웨딩홀-계산」 → 「cn」 + 「계산」)
     · 떼고 남은 것이 흔한 말이면 안 뗀다 (「그랜드컨벤션」 → 「그랜드」, 「월드컵컨벤션」 → 「월드컵」)
     · 두 글자짜리 이름표(「루벨」·「라움」)는 **낱말 첫머리**에 있을 때만 — 「블루벨」 에 걸리지 않게
   ⚠ 팝업에는 사진마다 **갤러리 이름표**가 같이 뜬다. 혹시 잘못 이어도 작가님이 보고 안다.

   ── 누구에게
   ⚠ 처음에는 **대표 캘린더에만** (대표 «일단 내 캘린더에만 적용해서 보여주고 전체 공개»).
     private.gal_sample_on 한 곳에서 정한다. 전체 공개는 그 함수 한 줄만 바꾼다.

   ── 캘린더와 따로 받는다
   staff_calendar 에 섞지 않고 함수를 따로 둔다. 갤러리 쪽에서 무엇이 틀어져도 달력은 그대로 떠야 한다.
   화면은 달력과 **같이** 부르고(기다리는 시간이 안 는다), 못 받으면 단추만 안 단다. */


-- ── ① 글자만 남긴 한 줄 ─────────────────────────────────────
-- 띄어쓰기·기호를 떼고, 흔한 두 표기 하나(씨티/시티)를 맞춘다.
-- 갤러리에 「웨딩씨티-신도림」 27장과 「웨딩시티-신도림」 7장이 따로 있다 — 같은 곳이다
create or replace function private.venue_flat(v text)
returns text language sql immutable as $$
  select replace(regexp_replace(lower(coalesce(v, '')), '[^[:alnum:]]+', '', 'g'), '씨티', '시티')
$$;
revoke all on function private.venue_flat(text) from public, anon, authenticated;


-- ── ② 갤러리 이름표의 낱말마다 «핵심» ────────────────────────
-- 「라마다호텔-신도림」 → {라마다, 신도림}   「cn웨딩홀-계산」 → {cn, 계산}
-- 「공군호텔」 → {공군호텔} (「공군」 은 두 글자라 너무 넓다)
-- 「CN웨딩홀-주안점」 → {cn, 주안} (지점의 「점」 은 venue_key 처럼 뗀다)
create or replace function private.venue_gal_cores(v text)
returns text[] language sql immutable as $$
  with w as (
    select u.ord, replace(u.t, '씨티', '시티') as t
    from unnest(string_to_array(regexp_replace(lower(coalesce(v, '')), '[^[:alnum:]]+', ' ', 'g'), ' '))
         with ordinality as u(t, ord)
    where u.t <> ''
  ),
  n as (select count(*)::int as c from w),
  x as (
    select w.ord, w.t,
           regexp_replace(
             regexp_replace(w.t, '^(.{2,}?)(지점|점)$', '\1'),
             '(웨딩컨벤션|웨딩하우스|웨딩홀|웨딩|컨벤션|호텔|하우스)$', '') as core
    from w
  )
  select coalesce(array_agg(
           case when x.core <> x.t
                 -- 「월드컵」 은 경기장 이름이다 — 상암 월드컵컨벤션과 수원월드컵경기장 WI컨벤션이
                 -- 둘 다 품는다 (작가 이력에 실제로 있다, 2026-09-29)
                 and x.core not in ('', '더', '뉴', '그랜드', '웨딩', '파티', '가든', '센터', '타워',
                                    '로얄', '아트', '스카이', '시티', '홀', '월드컵')
                 and (char_length(x.core) >= 3 or ((select c from n) >= 2 and char_length(x.core) >= 2))
                then x.core else x.t end
           order by x.ord), '{}')
  from x
$$;
revoke all on function private.venue_gal_cores(text) from public, anon, authenticated;


-- ── ③ 예약 예식장 이름들 → 이어지는 갤러리 이름표들 ──────────
-- 여러 이름을 한 번에 받는다. 갤러리 쪽 셈(이름표 80여 개)을 한 번만 하려고.
-- ⚠ 잇는 규칙은 **여기 한 곳에만** 둔다. 장수 세기와 사진 목록이 같은 것을 부른다 —
--   둘이 따로 셈하면 「샘플보기 12」 를 눌렀는데 9장이 뜬다
create or replace function private.venue_gal_pairs(p_venues text[])
returns table (venue_in text, gal_venue text)
language sql stable
set search_path to 'private', 'public', 'pg_temp' as $$
  with gv as (
    select g.venue, private.venue_canon(g.venue) as k, private.venue_gal_cores(g.venue) as cores
    from (select distinct venue from public.gallery where coalesce(venue, '') <> '') g
  ),
  amb as (
    -- 브랜드만 적힌 이름표 — ②로는 잇지 않는다 (①로는 잇는다: 예약도 「아펠가모」 라고만 적었으면)
    select a.venue from gv a
    where cardinality(a.cores) = 1
      and (exists (select 1 from gv b where cardinality(b.cores) >= 2 and a.cores[1] = any (b.cores))
           or exists (select 1 from public.venue_stem_block s where s.stem = private.venue_key(a.venue)))
  ),
  bv as (
    select distinct v as venue_in, private.venue_canon(v) as k, private.venue_flat(v) as flat,
           -- 낱말 첫머리를 볼 때 쓴다 (두 글자짜리 이름표)
           string_to_array(regexp_replace(replace(lower(v), '씨티', '시티'), '[^[:alnum:]]+', ' ', 'g'), ' ') as words
    from unnest(p_venues) as v
    where private.venue_flat(v) <> ''
  )
  select bv.venue_in, gv.venue
  from bv join gv on (
       (gv.k <> '' and gv.k = bv.k)
    or (gv.venue not in (select venue from amb)
        and cardinality(gv.cores) > 0
        -- 낱말이 전부 들어 있어야 한다
        and not exists (select 1 from unnest(gv.cores) c where strpos(bv.flat, c) = 0)
        -- 두 글자짜리 이름표 하나뿐이면 낱말 첫머리에 있어야 한다 (「블루벨」 에 「루벨」 이 걸리지 않게)
        and not (cardinality(gv.cores) = 1 and char_length(gv.cores[1]) <= 2
                 and not exists (select 1 from unnest(bv.words) bw where bw like gv.cores[1] || '%'))))
$$;
revoke all on function private.venue_gal_pairs(text[]) from public, anon, authenticated;


-- ── ④ 누구에게 보여주나 — 한 곳에서만 정한다 ────────────────
-- ⚠ 지금은 대표만 (대표 2026-09-29 «일단 내 캘린더에만 적용해서 보여주고 전체 공개»).
--   전체 공개는 «and coalesce(s.is_rep, false)» 한 줄을 지우는 것이다
create or replace function private.gal_sample_on(p_staff_id uuid)
returns boolean language sql stable
set search_path to 'public', 'pg_temp' as $$
  select exists (select 1 from public.staff s
                 where s.id = p_staff_id and coalesce(s.active, false)
                   and coalesce(s.is_rep, false))
$$;
revoke all on function private.gal_sample_on(uuid) from public, anon, authenticated;


-- ── ⑤ 앞으로 있을 내 예식마다 샘플이 몇 장인가 ──────────────
-- 캘린더를 열 때 달력과 같이 부른다. { 예약ID: 장수 } — 0장인 예식은 안 싣는다
create or replace function public.staff_gal_counts(p_staff_id uuid)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp' as $$
declare today date := (now() at time zone 'Asia/Seoul')::date; res jsonb;
begin
  if not private.gal_sample_on(p_staff_id) then return '{}'::jsonb; end if;
  with bk as (
    select b.id, b.wedding_venue from public.bookings b
    where (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
      and b.status <> '취소' and b.wedding_date >= today
      and coalesce(b.wedding_venue, '') <> ''
  ),
  pr as (select * from private.venue_gal_pairs(array(select distinct bk.wedding_venue from bk))),
  n as (
    select pr.venue_in, count(*)::int as n
    from pr join public.gallery g on g.venue = pr.gal_venue
    group by pr.venue_in
  )
  select coalesce(jsonb_object_agg(bk.id, n.n), '{}'::jsonb) into res
  from bk join n on n.venue_in = bk.wedding_venue;
  return res;
end$$;
revoke all on function public.staff_gal_counts(uuid) from public;
grant execute on function public.staff_gal_counts(uuid) to anon, authenticated;


-- ── ⑥ 그 예식의 샘플 사진 ────────────────────────────────────
-- ⚠ 내 예식이어야 한다 (메인이든 서브든). 취소·지난 것은 안 준다 — 장수 세기와 같은 조건이다.
-- ⚠ 사진 주소와 이름표만. 원본 경로(image_path)·찍은 작가는 싣지 않는다
create or replace function public.staff_gal_samples(p_staff_id uuid, p_booking_id uuid)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp' as $$
declare bk public.bookings; today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if not private.gal_sample_on(p_staff_id) then return jsonb_build_object('ok', false); end if;
  select * into bk from public.bookings b
   where b.id = p_booking_id
     and (b.assignee_id = p_staff_id or b.sub_assignee_id = p_staff_id)
     and b.status <> '취소' and b.wedding_date >= today;
  if not found then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object('ok', true, 'venue', bk.wedding_venue, 'items', coalesce((
    select jsonb_agg(jsonb_build_object('image_url', g.image_url, 'venue', g.venue)
                     order by g.created_at desc, g.id)
    from public.gallery g
    where g.venue in (select p.gal_venue from private.venue_gal_pairs(array[bk.wedding_venue]) p)),
    '[]'::jsonb));
end$$;
revoke all on function public.staff_gal_samples(uuid, uuid) from public;
grant execute on function public.staff_gal_samples(uuid, uuid) to anon, authenticated;


-- ── ⑦ 지점이 여럿인 브랜드 둘을 목록에 ──────────────────────
-- 갤러리에 지점 없이 브랜드만 적힌 이름표인데, 같은 브랜드의 지점 이름표가 갤러리에 따로 없어서
-- 위 ③의 「브랜드만」 셈이 못 알아보는 것들이다. 작가 이력(2,111개 이름)에서 찾았다.
--   롯데호텔   — 갤러리 1장이 「L7 광명 바이 롯데호텔」 예식에 붙는다
--   노블발렌티 — 이력에 「노블발렌티 대치점」·「노블발렌티 삼성점」 이 따로 있다. 갤러리 7장은 어느 쪽인지 모른다
-- (이 목록은 예식장 이름 잇기 제안 admin_venue_alias_suggest 도 본다 — 거기서도 이 둘은
--  «모으는 자리» 가 되면 안 되니 뜻이 같다)
insert into public.venue_stem_block (stem, note) values
  ('롯데호텔', '서울·월드·L7 … 지점이 여럿이다. 갤러리 「롯데호텔」 사진이 L7 광명 예식에 붙지 않게 (2026-09-29 예식장 샘플)'),
  ('노블발렌티', '대치점·삼성점 두 곳이다. 갤러리 「노블발렌티」 는 어느 지점인지 모른다 (2026-09-29 예식장 샘플)')
on conflict (stem) do nothing;
