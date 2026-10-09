-- Shared recipe links (AppsFlyer OneLink).
-- Run once in the Supabase SQL editor.
--
-- A share stores a snapshot of the recipe so anyone with the link can see it,
-- while user_recipes stays private. Sharing the same recipe again updates the
-- snapshot and keeps its code, so earlier links keep working.

create table if not exists public.shared_recipes (
    id uuid primary key default gen_random_uuid(),
    -- Short code carried in the link (deep_link_sub1)
    code text not null unique default substr(replace(gen_random_uuid()::text, '-', ''), 1, 10),
    owner_id uuid not null references auth.users (id) on delete cascade,
    -- user_recipes.id or recipes.id the share was made from
    source_recipe_id uuid not null,
    -- Set when an Explore recipe (recipes table) was shared; saving it bookmarks the original
    original_recipe_id uuid,

    title text not null,
    description text,
    servings_text text,
    prep_time_minutes integer,
    cook_time_minutes integer,
    ingredients jsonb not null default '[]'::jsonb,
    instructions jsonb not null default '[]'::jsonb,
    notes text,
    images jsonb not null default '[]'::jsonb,
    source_url text,
    source_name text,
    nutrition jsonb,
    nutrition_estimated boolean not null default false,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    unique (owner_id, source_recipe_id)
);

alter table public.shared_recipes enable row level security;

-- Owners create and refresh their own shares. There's no public select policy,
-- so the table can't be listed; recipients read one share by code via the function below.
create policy "Owners can read their shares"
    on public.shared_recipes for select
    using (auth.uid() = owner_id);

create policy "Owners can create shares"
    on public.shared_recipes for insert
    with check (auth.uid() = owner_id);

create policy "Owners can update their shares"
    on public.shared_recipes for update
    using (auth.uid() = owner_id)
    with check (auth.uid() = owner_id);

create policy "Owners can delete their shares"
    on public.shared_recipes for delete
    using (auth.uid() = owner_id);

-- Look up one shared recipe by its link code (works for signed-out users too)
create or replace function public.get_shared_recipe(p_code text)
returns setof public.shared_recipes
language sql
stable
security definer
set search_path = public
as $$
    select * from public.shared_recipes where code = p_code limit 1;
$$;

revoke all on function public.get_shared_recipe(text) from public;
grant execute on function public.get_shared_recipe(text) to anon, authenticated;
