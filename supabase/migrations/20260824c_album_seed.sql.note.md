# 앨범 발주 — 쓰던 자료 옮겨심기 (2026-08-24)

단가 7종 / 발주 115건 / 라인 124건 / 합계 9,398,175원 (2026-04 ~ 2026-07).

**실제 INSERT 문은 이 저장소에 없습니다.** 고객 이름이 그대로 들어 있고
이 저장소는 공개(public)라서 올리면 안 됩니다.

- 실물: `.backups/album-seed-20260824.sql` (이 PC에만, `.gitignore` 로 막아둠)
- 원본: `이관패키지/seed.json` (마찬가지로 막아둠)
- 서울 DB에는 **이미 적용했습니다.** 다시 돌릴 일은 없습니다.

다시 심어야 하면 `.backups/album-seed-20260824.sql` 을 `NEW_DB_URL` 로 돌리면 됩니다.
`on conflict do nothing` 이라 두 번 돌려도 겹치지 않습니다.

옮긴 뒤 확인한 것 (사양서 8번):

```
select count(*) from public.album_orders;                 -- 115
select count(*) from public.album_order_lines;            -- 124
select sum(total) from public.album_orders;               -- 9398175
select sum(unit*qty) from public.album_order_lines;       -- 9398175
```
