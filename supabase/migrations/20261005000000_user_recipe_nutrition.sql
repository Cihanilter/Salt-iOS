-- Nutrition for user recipes
--
-- Imported and hand-made recipes have no nutrition data, so it's estimated by
-- AI (Gemini via Salt-backend `/api/estimate-nutrition`) right after the
-- recipe is saved or edited, or the first time an older recipe is opened.
-- The app writes the result.
--
--   nutrition            per-serving values, same JSON shape as recipes.nutrition
--                        (schema.org NutritionInformation), e.g.
--                        {"calories": "347 calories", "fatContent": "21 g", "sodiumContent": "1493 mg", ...}
--   nutrition_estimated  true when the values came from AI rather than the source website
--
-- No RLS changes: the app writes these columns as the signed-in user, so the
-- existing "users can update their own recipes" policy covers it.
--
-- Safe to re-run.

alter table public.user_recipes
    add column if not exists nutrition jsonb,
    add column if not exists nutrition_estimated boolean not null default false;

-- To undo:
--   alter table public.user_recipes drop column if exists nutrition, drop column if exists nutrition_estimated;
