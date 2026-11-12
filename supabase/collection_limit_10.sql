-- Shared collections: up to 10 people (the owner and up to 9 members), was 5.
-- Run once in the Supabase SQL editor, after collection_roles.sql.
-- Same join_collection as in collection_roles.sql, only the limit changed.
--
-- Older apps still say "already has 5 people" in their own text when a collection is
-- full, but joining follows this limit.
--
-- To undo: run this again with 5 instead of 10.

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
