-- Recipe collections (e.g. "Weeknight Dinners", "Atlas", "Turkish").
-- Run once in the Supabase SQL editor.
--
-- A collection holds the user's own recipes (user_recipes) and/or Explore recipes (recipes).
-- A recipe can be in several collections. Deleting a collection never deletes recipes;
-- deleting a recipe removes it from its collections.
--
-- To remove the feature completely:
--   drop table public.collection_recipes; drop table public.collections;

create table if not exists public.collections (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users (id) on delete cascade,
    name text not null check (char_length(btrim(name)) between 1 and 20),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists collections_owner_idx on public.collections (owner_id);

create table if not exists public.collection_recipes (
    id uuid primary key default gen_random_uuid(),
    collection_id uuid not null references public.collections (id) on delete cascade,
    -- Exactly one of these is set
    user_recipe_id uuid references public.user_recipes (id) on delete cascade,
    recipe_id uuid references public.recipes (id) on delete cascade,
    -- Who added it (the owner for now; collection members once collections can be shared)
    added_by uuid not null default auth.uid() references auth.users (id) on delete cascade,
    added_at timestamptz not null default now(),

    check (num_nonnulls(user_recipe_id, recipe_id) = 1),
    unique (collection_id, user_recipe_id),
    unique (collection_id, recipe_id)
);

create index if not exists collection_recipes_collection_idx on public.collection_recipes (collection_id);

alter table public.collections enable row level security;
alter table public.collection_recipes enable row level security;

-- Collections: only the owner (sharing will add member policies later)
create policy "Owners manage their collections"
    on public.collections for all
    using (auth.uid() = owner_id)
    with check (auth.uid() = owner_id);

-- Collection recipes: anyone who owns the collection
create policy "Owners manage recipes in their collections"
    on public.collection_recipes for all
    using (exists (
        select 1 from public.collections c
        where c.id = collection_id and c.owner_id = auth.uid()
    ))
    with check (exists (
        select 1 from public.collections c
        where c.id = collection_id and c.owner_id = auth.uid()
    ));
