-- Recipe import log
--
-- One row per imported recipe the user successfully saved. Backs the
-- "Total Recipes Imported" count on the Profile screen, and a future
-- free-tier import limit.
--
-- Rows are written by a trigger on user_recipes, so:
--   * only successful saves count (a failed save rolls back its log row too)
--   * editing a recipe doesn't count (trigger runs on INSERT only)
--   * deleting a recipe doesn't give the import back (log row is kept)
--   * the app can read its own rows but can't insert, update or delete them
--
-- user_recipes.source is the recipe_source enum, so it's cast to text
-- wherever it's matched or copied.
--
-- Applied 2026-09-29 via the Supabase SQL Editor. Safe to re-run.
-- Everything runs in one transaction: if any step fails, nothing is applied.

begin;

-- 1. Table ------------------------------------------------------------------

create table if not exists public.recipe_imports (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references auth.users (id) on delete cascade,
    recipe_id   uuid references public.user_recipes (id) on delete set null,
    source      text not null,   -- 'imported_instagram', 'imported_tiktok', 'imported_youtube', 'imported_web'
    source_url  text,
    created_at  timestamptz not null default now()
);

-- Counting "imports since <date>" per user is the main query
create index if not exists recipe_imports_user_created_idx
    on public.recipe_imports (user_id, created_at);

-- 2. Row Level Security ----------------------------------------------------

alter table public.recipe_imports enable row level security;

-- Read-only for the app. There are deliberately no insert/update/delete
-- policies, so users can't add or remove rows to change their count.
drop policy if exists "Users can read their own imports" on public.recipe_imports;
create policy "Users can read their own imports"
    on public.recipe_imports
    for select
    using (auth.uid() = user_id);

-- 3. Trigger ---------------------------------------------------------------

-- security definer: runs as the table owner, so it can write the log row
-- even though the app itself has no insert policy
create or replace function public.log_recipe_import()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.recipe_imports (user_id, recipe_id, source, source_url)
    values (new.user_id, new.id, new.source::text, new.source_url);
    return new;
end;
$$;

drop trigger if exists on_user_recipe_imported on public.user_recipes;
create trigger on_user_recipe_imported
    after insert on public.user_recipes
    for each row
    when (new.source::text like 'imported\_%')
    execute function public.log_recipe_import();

-- 4. Backfill existing imports --------------------------------------------

-- Seeds the log from imported recipes users already have. Recipes that were
-- deleted before this migration can't be recovered, so those aren't counted.
insert into public.recipe_imports (user_id, recipe_id, source, source_url, created_at)
select r.user_id, r.id, r.source::text, r.source_url, coalesce(r.created_at, now())
from public.user_recipes r
where r.source::text like 'imported\_%'
  and not exists (select 1 from public.recipe_imports i where i.recipe_id = r.id);

commit;

-- To undo (removes only what this migration added):
--   drop trigger if exists on_user_recipe_imported on public.user_recipes;
--   drop function if exists public.log_recipe_import();
--   drop table if exists public.recipe_imports;
