-- Photo and note import sources
--
-- Recipes imported from photos or screenshots (a cookbook page, recipe card,
-- Instagram caption or recipe site) are saved with source 'imported_photo';
-- recipes pasted in or shared from the Notes app with 'imported_note'. Both
-- start with 'imported_', so the on_user_recipe_imported trigger logs them in
-- recipe_imports and they count toward the free import limit, like link imports.
--
-- Must be applied BEFORE an app build with photo/note import ships: saving
-- such a recipe fails while the enum doesn't have these values.
--
-- Safe to re-run.

alter type public.recipe_source add value if not exists 'imported_photo';
alter type public.recipe_source add value if not exists 'imported_note';

-- To undo: Postgres can't drop an enum value. Leaving them unused is harmless.
