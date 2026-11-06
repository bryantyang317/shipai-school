-- 貼到 Supabase 左側「SQL Editor」→ New query → Run（只需要執行一次）
-- 設計：資料表開啟 RLS 且不開放任何直接存取；只能透過下面幾個函式，而且每個函式都要帶「家庭代碼」。
-- 沒有家庭代碼的人，即使拿到網站上的 anon key，也讀不到任何資料。

create table if not exists public.docs (
  fam        text        not null,
  path       text        not null,
  data       jsonb       not null,
  updated_at timestamptz not null default now(),
  primary key (fam, path)
);
alter table public.docs enable row level security;
revoke all on table public.docs from anon, authenticated;

create or replace function public.get_doc(f text, p text)
returns jsonb language sql stable security definer set search_path = public as $$
  select data from public.docs where fam = f and path = p
$$;

create or replace function public.set_doc(f text, p text, d jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if length(f) < 10 then raise exception 'bad family code'; end if;
  if length(p) > 100 or length(d::text) > 1500000 then raise exception 'too large'; end if;
  insert into public.docs(fam, path, data, updated_at) values (f, p, d, now())
  on conflict (fam, path) do update set data = excluded.data, updated_at = now();
end $$;

create or replace function public.pull_docs(f text, since timestamptz)
returns table(path text, data jsonb, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select d.path, d.data, d.updated_at from public.docs d
  where d.fam = f and d.updated_at >= since order by d.updated_at
$$;

create or replace function public.family_exists(f text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.docs where fam = f)
$$;

grant execute on function public.get_doc(text, text)           to anon;
grant execute on function public.set_doc(text, text, jsonb)    to anon;
grant execute on function public.pull_docs(text, timestamptz)  to anon;
grant execute on function public.family_exists(text)           to anon;
