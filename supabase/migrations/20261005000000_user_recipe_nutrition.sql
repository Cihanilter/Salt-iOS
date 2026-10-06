-- Nutrition for user recipes
--
-- Imported and hand-made recipes have no nutrition data, so it's estimated by
-- AI (Claude Haiku 4.5) in the `estimate-nutrition` Edge Function right after
-- the recipe is saved or its ingredients change.
--
--   nutrition            per-serving values, same JSON shape as recipes.nutrition
--                        (schema.org NutritionInformation), e.g.
--                        {"calories": "347 calories", "fatContent": "21 g", "sodiumContent": "1493 mg", ...}
--   nutrition_estimated  true when the values came from AI rather than the source website
--
-- No RLS changes: the Edge Function runs as the signed-in user, so the existing
-- "users can update their own recipes" policy covers writing these columns.
--
-- Safe to re-run.

alter table public.user_recipes
    add column if not exists nutrition jsonb,
    add column if not exists nutrition_estimated boolean not null default false;

-- To undo:
--   alter table public.user_recipes drop column if exists nutrition, drop column if exists nutrition_estimated;
