-- Step 2: make search_recipes filter on meal_types.
-- Run after 01_add_meal_types.sql, before shipping the app update.
--
-- * New p_meal_types param takes MealType raw values (new app).
-- * p_categories still works, so app 1.7 and earlier keep working; their
--   category names are translated to meal types, so they benefit too.
-- * Recipes without meal_types yet fall back to the old categories match.
--
-- Dropped and recreated (not CREATE OR REPLACE) because adding a param would
-- otherwise leave an overload that PostgREST can't choose between.
begin;

drop function if exists public.search_recipes(text, text[], integer, text[], text[], integer, integer);
drop function if exists public.search_recipes(text, text[], integer, text[], text[], integer, integer, text[]);

create function public.search_recipes(
    p_query text default null,
    p_ingredients text[] default null,
    p_max_minutes integer default null,
    p_cuisines text[] default null,
    p_categories text[] default null,
    p_offset integer default 0,
    p_limit integer default 20,
    p_meal_types text[] default null
)
returns table(recipe jsonb, total_count bigint)
language sql
stable
set search_path to 'public'
as $function$
    with legacy(meal_type, category) as (
        values ('breakfast', 'Breakfast and Brunch'),
               ('mainDish', 'Main Dishes'),
               ('appetizers', 'Appetizers and Snacks'),
               ('soups', 'Soups, Stews and Chili Recipes'),
               ('salads', 'Salad'),
               ('sides', 'Side Dish'),
               ('desserts', 'Desserts'),
               ('bread', 'Bread'),
               ('drinks', 'Drink Recipes'),
               ('sauces', 'Sauces and Condiments')
    ),
    -- Requested meal types, whether sent as raw values or legacy category names
    wanted as (
        select coalesce(array_agg(distinct l.meal_type), '{}') as meal_types,
               coalesce(array_agg(distinct l.category), '{}') || coalesce(p_categories, '{}') as categories,
               coalesce(cardinality(p_meal_types), 0) + coalesce(cardinality(p_categories), 0) > 0 as active
        from legacy l
        where l.meal_type = any(coalesce(p_meal_types, '{}'))
           or l.category = any(coalesce(p_categories, '{}'))
    ),
    matches as (
        select r.*
        from recipes r
        cross join wanted w
        where (coalesce(p_query, '') = '' or r.title ilike '%' || p_query || '%')
          and (p_max_minutes is null or
               coalesce(nullif(r.total_time_minutes, 0),
                        coalesce(r.prep_time_minutes, 0) + coalesce(r.cook_time_minutes, 0))
                   between 1 and p_max_minutes)
          and (coalesce(cardinality(p_cuisines), 0) = 0 or r.cuisines && p_cuisines)
          and (not w.active
               or (r.meal_types is not null and r.meal_types && w.meal_types)
               or (r.meal_types is null and r.categories && w.categories))
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
$function$;

grant execute on function public.search_recipes(text, text[], integer, text[], text[], integer, integer, text[])
    to anon, authenticated;

commit;

notify pgrst, 'reload schema';

-- Checks: expect 0, then 1
select count(*) as carbonara_in_side_dish
from public.search_recipes(p_query => 'Bacon Carbonara, Italian', p_categories => array['Side Dish']);

select count(*) as carbonara_in_main_dish
from public.search_recipes(p_query => 'Bacon Carbonara, Italian', p_meal_types => array['mainDish']);
