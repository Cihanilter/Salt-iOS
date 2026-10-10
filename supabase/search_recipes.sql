-- Explore search with filters: title text, ingredients, total time, cuisine and meal type.
-- Run once in the Supabase SQL editor.
--
-- Every filter is optional; combined filters must all match:
--   p_query        part of the title
--   p_ingredients  each term must appear in the ingredient list (e.g. {chicken,rice})
--   p_max_minutes  total time (or prep + cook when total is missing) up to this many minutes
--   p_cuisines     any of these cuisines
--   p_categories   any of these categories (meal types)
-- Ordered like the rest of Explore: titles starting with the query, then curated, then rating.
--
-- To undo: drop function public.search_recipes(text, text[], int, text[], text[], int, int);

create or replace function public.search_recipes(
    p_query text default null,
    p_ingredients text[] default null,
    p_max_minutes int default null,
    p_cuisines text[] default null,
    p_categories text[] default null,
    p_offset int default 0,
    p_limit int default 20
)
returns table (recipe jsonb, total_count bigint)
language sql stable
set search_path = public
as $$
    with matches as (
        select r.*
        from recipes r
        where (coalesce(p_query, '') = '' or r.title ilike '%' || p_query || '%')
          and (p_max_minutes is null or
               coalesce(nullif(r.total_time_minutes, 0),
                        coalesce(r.prep_time_minutes, 0) + coalesce(r.cook_time_minutes, 0))
                   between 1 and p_max_minutes)
          and (coalesce(cardinality(p_cuisines), 0) = 0 or r.cuisines && p_cuisines)
          and (coalesce(cardinality(p_categories), 0) = 0 or r.categories && p_categories)
          and (coalesce(cardinality(p_ingredients), 0) = 0 or not exists (
                select 1 from unnest(p_ingredients) as term
                where r.ingredients::text not ilike '%' || term || '%'
              ))
    )
    select to_jsonb(m), count(*) over ()
    from matches m
    order by
        (coalesce(p_query, '') <> '' and m.title ilike p_query || '%') desc,
        m.is_curated desc nulls last,
        m.total_rating desc nulls last,
        m.rating_count desc nulls last,
        m.id
    offset greatest(p_offset, 0)
    limit least(greatest(p_limit, 1), 50);
$$;

grant execute on function public.search_recipes(text, text[], int, text[], text[], int, int) to anon, authenticated;
