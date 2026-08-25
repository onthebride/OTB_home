-- 100점 점수에 「추천 의향」을 넣는다. 대표 요청 2026-08-25 «점수도 수정해야겠어 / 추천 점수도 넣는게 좋겠는데».
--
-- 8/25 오전에는 안 넣기로 했었다 — 옛 응답 13건에는 이 문항이 없어서
-- 새 응답만 점수가 내려가 같은 잣대로 못 견준다는 이유였다.
-- 대표가 넣자고 하니 넣는다. 견주는 문제는 원래 있던 규칙이 알아서 다룬다:
--   «답이 없는 항목은 만점으로 안 치고 분모에서 뺀다»
-- 그래서 옛 응답은 옛 항목만으로, 새 응답은 추천까지 넣어 100점 만점으로 셈한다.
-- 다만 그 둘을 나란히 놓고 견주면 안 된다 — 화면에 그렇게 적어 둔다.
--
-- 저울 (합이 100):
--   도착 20 · 친절 20 · 요청 10 · 진행 15 · 하객 15 · 추천 20
-- 옛 저울은 도착 25 · 친절 25 · 요청 15 · 진행 15 · 하객 20 이었다.
-- 추천에 20 을 준 것은 이것만 실제로 갈리기 때문이다 —
-- 도착은 13/13 전부 「제시간」, 친절은 13/13 전부 만점이라 변별이 안 된다.
-- 도착·친절·요청에서 조금씩 떼어 추천에 줬다. 저울은 대표가 바꾸자면 여기만 고치면 된다.

create or replace function private.fb_score(f public.feedback)
returns numeric language sql immutable as $$
  select case when tot = 0 then null else round(got / tot * 100, 1) end
  from (
    select
      -- 도착은 늘 값이 있다 (안 고르면 저장이 안 된다)
      (case f.arrival when 'ontime' then 20 when 'late_small' then 16 else 12 end)
        + coalesce(f.kindness,  0) / 10.0 * 20
        + coalesce(f.requests,  0) / 10.0 * 10
        + coalesce(f.flow,      0) / 10.0 * 15
        + coalesce(f.family,    0) / 10.0 * 15
        + coalesce(f.recommend, 0) / 10.0 * 20                       as got,
      20
        + (case when f.kindness  is null then 0 else 20 end)
        + (case when f.requests  is null then 0 else 10 end)
        + (case when f.flow      is null then 0 else 15 end)
        + (case when f.family    is null then 0 else 15 end)
        + (case when f.recommend is null then 0 else 20 end)::numeric as tot
  ) w;
$$;
