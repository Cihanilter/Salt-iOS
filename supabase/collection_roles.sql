-- Member roles and invite link expiry in shared collections.
-- Run once in the Supabase SQL editor, after shared_collections.sql.
--
-- Roles:
-- - Each member is an "editor" (can add & edit: add and remove recipes) or a "viewer"
--   (can only view). The owner can always do everything.
-- - The owner changes a member's role, and picks the role people get when they join with
--   the invite link ("New members can"). Existing members stay editors.
-- - Everyone can still leave; only the owner removes members (unchanged).
--
-- Invite link expiry ("Link expires"):
-- - The owner picks 1, 7 or 30 days, or never. New collections default to 7 days.
-- - The clock starts when the link is created, reset, or the setting changes. Links that
--   exist today keep working (no expiry) until the owner resets them or changes the setting.
-- - An expired link can't be opened or joined; "Copy link" / "Invite people" then make a new one.
--
-- To undo: run the "UNDO" block at the bottom.

-- ------------------------------------------------------------
-- Columns
-- ------------------------------------------------------------

alter table public.collection_members
    add column if not exists role text not null default 'editor'
    check (role in ('editor', 'viewer'));

alter table public.collections
    add column if not exists new_member_role text not null default 'editor'
    check (new_member_role in ('editor', 'viewer'));

-- ------------------------------------------------------------
-- Access helper
-- ------------------------------------------------------------

-- The owner, or a member who can add & edit
create or replace function public.can_edit_collection(p_collection_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from collections where id = p_collection_id and owner_id = auth.uid()
    ) or exists (
        select 1 from collection_members
        where collection_id = p_collection_id and user_id = auth.uid() and role = 'editor'
    );
$$;

-- ------------------------------------------------------------
-- Row level security: only editors add and remove recipes
-- ------------------------------------------------------------

drop policy if exists "People in a collection add recipes" on public.collection_recipes;
drop policy if exists "People in a collection remove recipes" on public.collection_recipes;

create policy "Editors add recipes"
    on public.collection_recipes for insert
    with check (
        public.can_edit_collection(collection_id)
        and added_by = auth.uid()
        and (
            user_recipe_id is null
            or exists (select 1 from public.user_recipes ur where ur.id = user_recipe_id and ur.user_id = auth.uid())
        )
    );

create policy "Editors remove recipes"
    on public.collection_recipes for delete
    using (public.can_edit_collection(collection_id));

-- ------------------------------------------------------------
-- Functions
-- ------------------------------------------------------------

-- Changes a member's role (owner only)
create or replace function public.set_collection_member_role(p_collection_id uuid, p_user_id uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
    if not is_collection_owner(p_collection_id) then
        raise exception 'not_owner';
    end if;
    if p_role not in ('editor', 'viewer') then
        raise exception 'invalid_role';
    end if;
    update collection_members set role = p_role
    where collection_id = p_collection_id and user_id = p_user_id;
end;
$$;

-- (join_collection is updated in the invite link section below: role + expiry)

-- Everyone in a collection (owner first), with names, photos and roles ('owner' for the owner).
-- The return type changes, so the old function is dropped first.
drop function if exists public.get_collection_members(uuid);

create function public.get_collection_members(p_collection_id uuid)
returns table (
    user_id uuid,
    full_name text,
    profile_image_url text,
    is_owner boolean,
    role text,
    joined_at timestamptz
)
language sql stable security definer set search_path = public as $$
    select c.owner_id, p.full_name, p.profile_image_url, true, 'owner'::text, c.created_at
    from collections c
    left join profiles p on p.id = c.owner_id
    where c.id = p_collection_id and can_access_collection(p_collection_id)
    union all
    select m.user_id, p.full_name, p.profile_image_url, false, m.role, m.joined_at
    from collection_members m
    left join profiles p on p.id = m.user_id
    where m.collection_id = p_collection_id and can_access_collection(p_collection_id)
    order by 4 desc, 6 asc;
$$;

revoke all on function public.can_edit_collection(uuid) from public;
revoke all on function public.set_collection_member_role(uuid, uuid, text) from public;
revoke all on function public.get_collection_members(uuid) from public;

grant execute on function public.can_edit_collection(uuid) to authenticated;
grant execute on function public.set_collection_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.get_collection_members(uuid) to authenticated;

-- ------------------------------------------------------------
-- Invite link expiry
-- ------------------------------------------------------------

alter table public.collections
    add column if not exists invite_expiry_days int default 7
    check (invite_expiry_days is null or invite_expiry_days between 1 and 365);

alter table public.collections
    add column if not exists invite_expires_at timestamptz;

-- The collection's invite code; a new one when there's none or it expired (owner only)
create or replace function public.create_collection_invite(p_collection_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
    v_code text;
    v_expires timestamptz;
    v_days int;
begin
    if not is_collection_owner(p_collection_id) then
        raise exception 'not_owner';
    end if;

    select invite_code, invite_expires_at, invite_expiry_days into v_code, v_expires, v_days
    from collections where id = p_collection_id;
    if v_code is null or (v_expires is not null and v_expires <= now()) then
        v_code := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
        update collections
        set invite_code = v_code,
            invite_expires_at = case when v_days is null then null else now() + make_interval(days => v_days) end
        where id = p_collection_id;
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
    update collections
    set invite_code = v_code,
        invite_expires_at = case when invite_expiry_days is null then null
                                 else now() + make_interval(days => invite_expiry_days) end
    where id = p_collection_id;
    return v_code;
end;
$$;

-- How long the link works (null = never); restarts the current link's clock (owner only)
create or replace function public.set_collection_invite_expiry(p_collection_id uuid, p_days int)
returns void language plpgsql security definer set search_path = public as $$
begin
    if not is_collection_owner(p_collection_id) then
        raise exception 'not_owner';
    end if;
    if p_days is not null and (p_days < 1 or p_days > 365) then
        raise exception 'invalid_expiry';
    end if;
    update collections
    set invite_expiry_days = p_days,
        invite_expires_at = case when p_days is null or invite_code is null then null
                                 else now() + make_interval(days => p_days) end
    where id = p_collection_id;
end;
$$;

-- What an invite link shows before joining; nothing for an expired link
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
    where c.invite_code = p_code
      and (c.invite_expires_at is null or c.invite_expires_at > now())
      and auth.uid() is not null
    limit 1;
$$;

-- Joining: the role for new members, and only with a link that hasn't expired
create or replace function public.join_collection(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
    v_collection_id uuid;
    v_owner_id uuid;
    v_role text;
    v_people int;
begin
    if auth.uid() is null then
        raise exception 'not_signed_in';
    end if;

    select id, owner_id, new_member_role into v_collection_id, v_owner_id, v_role
    from collections
    where invite_code = p_code and (invite_expires_at is null or invite_expires_at > now());
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
    if v_people >= 10 then
        raise exception 'collection_full';
    end if;

    insert into collection_members (collection_id, user_id, role)
    values (v_collection_id, auth.uid(), coalesce(v_role, 'editor'));
    return v_collection_id;
end;
$$;

revoke all on function public.set_collection_invite_expiry(uuid, int) from public;
grant execute on function public.set_collection_invite_expiry(uuid, int) to authenticated;

-- ------------------------------------------------------------
-- UNDO (everyone can add & edit again; links don't expire)
-- ------------------------------------------------------------
-- drop policy "Editors add recipes" on public.collection_recipes;
-- drop policy "Editors remove recipes" on public.collection_recipes;
-- (re-run the "People in a collection add recipes" / "remove recipes" policies,
--  join_collection and get_collection_members from shared_collections.sql;
--  get_collection_members needs `drop function public.get_collection_members(uuid);` first)
-- drop function public.set_collection_member_role(uuid, uuid, text), public.can_edit_collection(uuid);
-- alter table public.collections drop column new_member_role;
-- alter table public.collection_members drop column role;
-- drop function public.set_collection_invite_expiry(uuid, int);
-- alter table public.collections drop column invite_expires_at, drop column invite_expiry_days;
-- (and re-run create/reset_collection_invite and get_collection_invite from shared_collections.sql)
