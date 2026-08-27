-- 후기 갈래마다 «누구 이름을 적을지» 를 다르게 한다 (대표 지시 2026-08-27
-- «일반 후기는 신부이름 김ㅇㅇ 으로 해주고 촬영후 설문 후기만 작가 이름으로»).
--
-- 이치에 맞는다:
--   · 일반 후기        = 신부님이 **직접 쓰신 글**이다 → 쓰신 분(김○○)을 적는다
--   · 촬영 후 설문 후기 = **작가에 대한** 평이다 → 누구를 두고 한 말인지(작가)를 적는다
--
-- 신부님 이름은 여전히 **넣을 때 이미 가려서** 담는다 (김지은 → 김○○). 원본은 표에 없다.

drop function if exists public.reviews_public();
create or replace function public.reviews_public()
returns jsonb language sql stable security definer set search_path=public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', kind, 'url', url, 'body', body,
    -- 화면이 갈래에 따라 골라 쓴다. 둘 다 실어 보내되 who 는 **가려진 것**뿐이다
    'who', author_label, 'staff', staff_label, 'venue', venue,
    -- M 은 to_char 의 달 기호가 아니다(FMMM 이라야 앞 0 이 안 붙는다). 그냥 두면 «2026. M.» 이 나간다
    'ym', to_char(wedding_date, 'YYYY. FMMM.'))
    order by sort_at desc), '[]'::jsonb)
  from public.review_post where published
$$;
revoke all on function public.reviews_public() from public;
grant execute on function public.reviews_public() to anon, authenticated;
