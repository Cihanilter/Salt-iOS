-- Photo import source
--
-- Recipes imported from a photo (a cookbook page, recipe card or screenshot)
-- are saved with source 'imported_photo'. It starts with 'imported_', so the
-- on_user_recipe_imported trigger logs it in recipe_imports and it counts
-- toward the free import limit, like link imports.
--
-- Must be applied BEFORE an app build with photo import ships: saving a
-- photo-imported recipe fails while the enum doesn't have this value.
--
-- Safe to re-run.

alter type public.recipe_source add value if not exists 'imported_photo';

-- To undo: Postgres can't drop an enum value. Leaving it unused is harmless.
