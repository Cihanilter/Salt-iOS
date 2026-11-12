-- Step 4: Meal type in search offers the same categories as Explore's chips.
-- Run before shipping the app update that sends p_dish_categories.
--
-- * New p_dish_categories param: categories that aren't meal types (Cookies, Cakes,
--   Pasta, Seafood, Vegetarian, Sandwich Recipes, Smoothie Recipes), matched on
--   recipes.categories like the Explore chips do.
-- * A recipe matches when it has any picked meal type OR any picked category, so
--   "Desserts + Cookies" means either.
-- * Older apps don't send the param and behave as before.
--
-- Dropped and recreated (not CREATE OR REPLACE) because adding a param would
-- otherwise leave an overload that PostgREST can't choose between.
begin;

drop function if exists public.search_recipes(text, text[], integer, text[], text[], integer, integer, text[]);
drop function if exists public.search_recipes(text, text[], integer, text[], text[], integer, integer, text[], text[]);

create function public.search_recipes(
    p_query text default null,
    p_ingredients text[] default null,
    p_max_minutes integer default null,
    p_cuisines text[] default null,
    p_categories text[] default null,
    p_offset integer default 0,
    p_limit integer default 20,
    p_meal_types text[] default null,
    p_dish_categories text[] default null
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
          and ((not w.active and coalesce(cardinality(p_dish_categories), 0) = 0)
               or (w.active and r.meal_types is not null and r.meal_types && w.meal_types)
               or (w.active and r.meal_types is null and r.categories && w.categories)
               or r.categories && coalesce(p_dish_categories, '{}'))
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

grant execute on function public.search_recipes(text, text[], integer, text[], text[], integer, integer, text[], text[])
    to anon, authenticated;

commit;

notify pgrst, 'reload schema';

-- Checks: cookies on their own, then desserts or cookies (expect >= the first)
select total_count as cookies
from public.search_recipes(p_dish_categories => array['Cookies'], p_limit => 1);

select total_count as desserts_or_cookies
from public.search_recipes(p_meal_types => array['desserts'], p_dish_categories => array['Cookies'], p_limit => 1);
