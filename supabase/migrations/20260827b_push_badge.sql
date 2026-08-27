-- ① 죽은 등록 정리 · ② 아이콘 뱃지. 대표 요청 2026-08-27 「정리해주고 / 아이콘에 알림 뱃지」
--
-- 죽은 등록 —
-- 대표 폰 등록이 6월부터 일곱 개 쌓였는데 다섯 개만 살아 있다.
-- 브라우저가 404·410 을 주면 엣지 함수가 알아서 지우지만, 그냥 실패(타임아웃·400)면
-- 안 지워지고 계속 쌓인다. 보낼 때마다 조금씩 느려진다.
--
-- 어느 것이 죽었는지 **DB 만 봐서는 모른다.** 그래서 엣지 함수가 실패를 여기 적게 하고,
-- 세 번 잇달아 실패하면 지운다. 한 번 실패했다고 지우면 잠깐 끊긴 폰을 잘라내게 된다.
alter table public.push_subscriptions add column if not exists fail_n integer not null default 0;
alter table public.push_subscriptions add column if not exists last_error text;
alter table public.push_subscriptions add column if not exists last_ok_at timestamptz;

comment on column public.push_subscriptions.fail_n is
  '잇달아 실패한 횟수. 성공하면 0 으로 돌아간다. 3 이 되면 엣지 함수가 지운다';

-- 관리자 화면에서 볼 수 있게 (지금은 안 쓰지만 «왜 안 오지» 할 때 필요하다)
create or replace function public.admin_push_subs()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select coalesce(jsonb_agg(t order by t.staff_name nulls first, t.created_at), '[]'::jsonb) into res
  from (
    select p.endpoint, s.name as staff_name, p.created_at, p.last_ok_at, p.fail_n, p.last_error,
           -- 어느 서비스인지만 (주소 전체는 열쇠나 마찬가지라 안 낸다)
           split_part(split_part(p.endpoint, '//', 2), '/', 1) as host
    from public.push_subscriptions p
    left join public.staff s on s.id = p.staff_id) t;
  return jsonb_build_object('ok', true, 'subs', res);
end$$;
revoke all on function public.admin_push_subs() from public, anon;
