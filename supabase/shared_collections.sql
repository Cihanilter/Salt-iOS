-- Shared collections: invite people to a collection with a link.
-- Run once in the Supabase SQL editor, after collections.sql.
--
-- - A collection has at most 5 people: the owner and up to 4 members.
-- - Members can view, add and remove recipes, and leave. Only the owner can rename or
--   delete the collection, manage the invite link and remove members.
-- - Each collection has one reusable invite code (null = link turned off).
-- - Members can read the owner's (and each other's) recipes that are in the collection.
--
-- To undo: run the "UNDO" block at the bottom.

-- ------------------------------------------------------------
-- Tables
-- ------------------------------------------------------------

create table if not exists public.collection_members (
    collection_id uuid not null references public.collections (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade,
    joined_at timestamptz not null default now(),
    primary key (collection_id, user_id)
);

create index if not exists collection_members_user_idx on public.collection_members (user_id);

alter table public.collections add column if not exists invite_code text unique;

-- ------------------------------------------------------------
-- Access helpers (security definer, so policies don't loop through each other)
-- ------------------------------------------------------------

create or replace function public.is_collection_owner(p_collection_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from collections where id = p_collection_id and owner_id = auth.uid()
    );
$$;

create or replace function public.can_access_collection(p_collection_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from collections where id = p_collection_id and owner_id = auth.uid()
    ) or exists (
        select 1 from collection_members where collection_id = p_collection_id and user_id = auth.uid()
    );
$$;

-- A user recipe is visible to the people of any collection it's in
create or replace function public.can_view_user_recipe(p_user_recipe_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from collection_recipes cr
        where cr.user_recipe_id = p_user_recipe_id and can_access_collection(cr.collection_id)
    );
$$;

-- ------------------------------------------------------------
-- Row level security
-- ------------------------------------------------------------

-- collections: owner and members read; only the owner changes
drop policy if exists "Owners manage their collections" on public.collections;

create policy "People in a collection can read it"
    on public.collections for select
    using (auth.uid() = owner_id or public.can_access_collection(id));

create policy "Owners create collections"
    on public.collections for insert
    with check (auth.uid() = owner_id);

create policy "Owners update collections"
    on public.collections for update
    using (auth.uid() = owner_id)
    with check (auth.uid() = owner_id);

create policy "Owners delete collections"
    on public.collections for delete
    using (auth.uid() = owner_id);

-- collection_recipes: owner and members read, add (their own recipes or Explore ones) and remove
drop policy if exists "Owners manage recipes in their collections" on public.collection_recipes;

create policy "People in a collection read its recipes"
    on public.collection_recipes for select
    using (public.can_access_collection(collection_id));

create policy "People in a collection add recipes"
    on public.collection_recipes for insert
    with check (
        public.can_access_collection(collection_id)
        and added_by = auth.uid()
        and (
            user_recipe_id is null
            or exists (select 1 from public.user_recipes ur where ur.id = user_recipe_id and ur.user_id = auth.uid())
        )
    );

create policy "People in a collection remove recipes"
    on public.collection_recipes for delete
    using (public.can_access_collection(collection_id));

-- collection_members: people in the collection see each other; members leave, the owner removes.
-- Joining only happens through join_collection().
alter table public.collection_members enable row level security;

create policy "People in a collection see its members"
    on public.collection_members for select
    using (public.can_access_collection(collection_id));

create policy "Members leave and owners remove members"
    on public.collection_members for delete
    using (user_id = auth.uid() or public.is_collection_owner(collection_id));

-- user_recipes: also readable when the recipe is in a collection the user is in
create policy "People in a collection read its recipes from others"
    on public.user_recipes for select
    using (public.can_view_user_recipe(id));

-- ------------------------------------------------------------
-- Invite link
-- ------------------------------------------------------------

-- The collection's invite code, created the first time (owner only)
create or replace function public.create_collection_invite(p_collection_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
    v_code text;
begin
    if not is_collection_owner(p_collection_id) then
        raise exception 'not_owner';
    end if;

    select invite_code into v_code from collections where id = p_collection_id;
    if v_code is null then
        v_code := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
        update collections set invite_code = v_code where id = p_collection_id;
    end if;
    return v_code;
end;
$$;

-- A new code; links sent before stop working (owner only)
create or replace function public.reset_collection_invite(p_collection_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
    v_code text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
begin
    if not is_collection_owner(p_collection_id) then
        raise exception 'not_owner';
    end if;
    update collections set invite_code = v_code where id = p_collection_id;
    return v_code;
end;
$$;

-- Turns the link off until a new one is created (owner only)
create or replace function public.disable_collection_invite(p_collection_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
    if not is_collection_owner(p_collection_id) then
        raise exception 'not_owner';
    end if;
    update collections set invite_code = null where id = p_collection_id;
end;
$$;

-- What an invite link shows before joining
create or replace function public.get_collection_invite(p_code text)
returns table (
    collection_id uuid,
    name text,
    owner_name text,
    owner_image_url text,
    people_count int,
    recipe_count int,
    is_member boolean
)
language sql stable security definer set search_path = public as $$
    select
        c.id,
        c.name,
        p.full_name,
        p.profile_image_url,
        1 + (select count(*) from collection_members m where m.collection_id = c.id)::int,
        (select count(*) from collection_recipes r where r.collection_id = c.id)::int,
        c.owner_id = auth.uid()
            or exists (select 1 from collection_members m where m.collection_id = c.id and m.user_id = auth.uid())
    from collections c
    left join profiles p on p.id = c.owner_id
    where c.invite_code = p_code and auth.uid() is not null
    limit 1;
$$;

-- Joins the collection the code belongs to and returns its id. At most 5 people.
create or replace function public.join_collection(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
    v_collection_id uuid;
    v_owner_id uuid;
    v_people int;
begin
    if auth.uid() is null then
        raise exception 'not_signed_in';
    end if;

    select id, owner_id into v_collection_id, v_owner_id from collections where invite_code = p_code;
    if v_collection_id is null then
        raise exception 'invite_not_found';
    end if;

    -- Already in it
    if v_owner_id = auth.uid() or exists (
        select 1 from collection_members where collection_id = v_collection_id and user_id = auth.uid()
    ) then
        return v_collection_id;
    end if;

    select 1 + count(*) into v_people from collection_members where collection_id = v_collection_id;
    if v_people >= 5 then
        raise exception 'collection_full';
    end if;

    insert into collection_members (collection_id, user_id) values (v_collection_id, auth.uid());
    return v_collection_id;
end;
$$;

-- Everyone in a collection (owner first), with names and photos
create or replace function public.get_collection_members(p_collection_id uuid)
returns table (
    user_id uuid,
    full_name text,
    profile_image_url text,
    is_owner boolean,
    joined_at timestamptz
)
language sql stable security definer set search_path = public as $$
    select c.owner_id, p.full_name, p.profile_image_url, true, c.created_at
    from collections c
    left join profiles p on p.id = c.owner_id
    where c.id = p_collection_id and can_access_collection(p_collection_id)
    union all
    select m.user_id, p.full_name, p.profile_image_url, false, m.joined_at
    from collection_members m
    left join profiles p on p.id = m.user_id
    where m.collection_id = p_collection_id and can_access_collection(p_collection_id)
    order by 4 desc, 5 asc;
$$;

revoke all on function public.create_collection_invite(uuid) from public;
revoke all on function public.reset_collection_invite(uuid) from public;
revoke all on function public.disable_collection_invite(uuid) from public;
revoke all on function public.get_collection_invite(text) from public;
revoke all on function public.join_collection(text) from public;
revoke all on function public.get_collection_members(uuid) from public;

grant execute on function public.create_collection_invite(uuid) to authenticated;
grant execute on function public.reset_collection_invite(uuid) to authenticated;
grant execute on function public.disable_collection_invite(uuid) to authenticated;
grant execute on function public.get_collection_invite(text) to authenticated;
grant execute on function public.join_collection(text) to authenticated;
grant execute on function public.get_collection_members(uuid) to authenticated;

-- ------------------------------------------------------------
-- UNDO (back to private collections)
-- ------------------------------------------------------------
-- drop policy "People in a collection read its recipes from others" on public.user_recipes;
-- drop function public.get_collection_members(uuid), public.join_collection(text),
--     public.get_collection_invite(text), public.disable_collection_invite(uuid),
--     public.reset_collection_invite(uuid), public.create_collection_invite(uuid);
-- drop policy "People in a collection can read it" on public.collections;
-- drop policy "Owners create collections" on public.collections;
-- drop policy "Owners update collections" on public.collections;
-- drop policy "Owners delete collections" on public.collections;
-- drop policy "People in a collection read its recipes" on public.collection_recipes;
-- drop policy "People in a collection add recipes" on public.collection_recipes;
-- drop policy "People in a collection remove recipes" on public.collection_recipes;
-- drop table public.collection_members;
-- drop function public.can_view_user_recipe(uuid), public.can_access_collection(uuid), public.is_collection_owner(uuid);
-- alter table public.collections drop column invite_code;
-- (then re-run the two "Owners manage ..." policies from collections.sql)
