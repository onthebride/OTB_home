-- 20260714_staff_color.sql
-- 작가(담당자)별 색상 직접 지정. color 가 지정되면 그 색을 쓰고, 비어있으면 자동 팔레트.
-- Supabase 대시보드 → SQL Editor 에 붙여넣고 실행하면 됩니다.

alter table public.staff add column if not exists color text;

-- admin_staff_update 에 색상 파라미터 추가 (기존 5-인자 버전은 제거)
drop function if exists public.admin_staff_update(uuid, text, text, boolean, boolean);
create or replace function public.admin_staff_update(
  p_id uuid, p_name text, p_phone text, p_active boolean, p_rep boolean, p_color text default null)
returns public.staff language plpgsql security definer set search_path=public, pg_temp
as $$ declare r public.staff; begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if coalesce(p_rep,false) then
    update public.staff set is_rep = false where id <> p_id;  -- 대표는 1명만
  end if;
  update public.staff set
       name   = nullif(p_name,''),
       phone  = nullif(p_phone,''),
       active = coalesce(p_active,true),
       is_rep = coalesce(p_rep,false),
       -- p_color: null=변경안함 / ''=자동(색 해제) / '#RRGGBB'=지정
       color  = case when p_color is null then color else nullif(p_color,'') end
   where id=p_id returning * into r;
  return r;
end; $$;

revoke all on function public.admin_staff_update(uuid, text, text, boolean, boolean, text) from public, anon;
grant execute on function public.admin_staff_update(uuid, text, text, boolean, boolean, text) to authenticated;
