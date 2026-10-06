// estimate-nutrition
//
// Estimates per-serving nutrition for one of the signed-in user's recipes with
// Claude Haiku 4.5 and stores it on user_recipes.nutrition (nutrition_estimated = true).
//
// Called by the app right after a recipe is saved, and again (force: true) when its
// ingredients or servings change. Request body: { "recipe_id": "<uuid>", "force"?: boolean }
//
// Secrets: ANTHROPIC_API_KEY (set with `supabase secrets set`). SUPABASE_URL and
// SUPABASE_ANON_KEY are provided automatically.

import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = "claude-haiku-4-5";

const anthropic = new Anthropic(); // reads ANTHROPIC_API_KEY

const SYSTEM_PROMPT = `You estimate nutrition for home-cooking recipes.

Given a recipe's title, servings and ingredient list, estimate the nutrition for ONE serving,
using typical values from standard nutrition databases (such as USDA FoodData Central).

- When quantities are vague ("a handful", "to taste", "a drizzle"), assume amounts a typical home cook would use.
- Ignore ingredients listed only for garnish or "optional" unless they clearly add meaningful calories.
- If the number of servings isn't given, choose a sensible number from the total quantities and report it.
- Give your best single estimate for every field; never leave one out.`;

// Per-serving values the model must return
const NUTRITION_SCHEMA = {
  type: "object",
  properties: {
    servings: { type: "integer", description: "Number of servings the per-serving values assume" },
    calories: { type: "number", description: "kcal per serving" },
    carbohydrates_g: { type: "number" },
    protein_g: { type: "number" },
    fat_g: { type: "number" },
    sugar_g: { type: "number" },
    fiber_g: { type: "number" },
    sodium_mg: { type: "number" },
  },
  required: ["servings", "calories", "carbohydrates_g", "protein_g", "fat_g", "sugar_g", "fiber_g", "sodium_mg"],
  additionalProperties: false,
};

type Estimate = {
  servings: number;
  calories: number;
  carbohydrates_g: number;
  protein_g: number;
  fat_g: number;
  sugar_g: number;
  fiber_g: number;
  sodium_mg: number;
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Not signed in" }, 401);

  let recipeId: string | undefined;
  let force = false;
  try {
    const body = await req.json();
    recipeId = body.recipe_id;
    force = body.force === true;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (!recipeId) return json({ error: "recipe_id is required" }, 400);

  // Act as the signed-in user, so row-level security limits this to their own recipes
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: recipe, error: loadError } = await supabase
    .from("user_recipes")
    .select("id, title, servings, servings_text, ingredients, nutrition")
    .eq("id", recipeId)
    .maybeSingle();

  if (loadError) return json({ error: loadError.message }, 500);
  if (!recipe) return json({ error: "Recipe not found" }, 404);

  // Don't pay for the same estimate twice; edits pass force: true
  if (recipe.nutrition && !force) return json({ status: "skipped", reason: "already has nutrition" });

  const ingredients: string[] = (recipe.ingredients ?? []).filter((i: string) => i?.trim());
  if (ingredients.length === 0) return json({ status: "skipped", reason: "no ingredients" });

  const servingsLine = recipe.servings_text || (recipe.servings ? `${recipe.servings}` : "not given");
  const userMessage = [
    `Recipe: ${recipe.title}`,
    `Servings: ${servingsLine}`,
    "Ingredients:",
    ...ingredients.map((i) => `- ${i}`),
  ].join("\n");

  let estimate: Estimate;
  try {
    const response = await anthropic.messages.create({
      model: MODEL,
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: userMessage }],
      output_config: { format: { type: "json_schema", schema: NUTRITION_SCHEMA } },
    });

    if (response.stop_reason === "refusal") return json({ error: "Estimate declined" }, 422);

    const text = response.content.find((block) => block.type === "text");
    if (!text || text.type !== "text") return json({ error: "Empty estimate" }, 502);
    estimate = JSON.parse(text.text) as Estimate;

    console.log(`Estimated ${recipeId}: ${response.usage.input_tokens} in / ${response.usage.output_tokens} out tokens`);
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) return json({ error: "Rate limited, try again later" }, 429);
    if (error instanceof Anthropic.APIError) {
      console.error(`Anthropic API error ${error.status}: ${error.message}`);
      return json({ error: "Estimate failed" }, 502);
    }
    console.error("Estimate failed:", error);
    return json({ error: "Estimate failed" }, 500);
  }

  // Same shape as recipes.nutrition (schema.org NutritionInformation) so the app reads both the same way
  const round = (n: number, digits = 0) => Number(Math.max(0, n).toFixed(digits));
  const nutrition = {
    "@type": "NutritionInformation",
    calories: `${round(estimate.calories)} calories`,
    carbohydrateContent: `${round(estimate.carbohydrates_g, 1)} g`,
    proteinContent: `${round(estimate.protein_g, 1)} g`,
    fatContent: `${round(estimate.fat_g, 1)} g`,
    sugarContent: `${round(estimate.sugar_g, 1)} g`,
    fiberContent: `${round(estimate.fiber_g, 1)} g`,
    sodiumContent: `${round(estimate.sodium_mg)} mg`,
    servingSize: `1 of ${estimate.servings} servings`,
  };

  const { error: saveError } = await supabase
    .from("user_recipes")
    .update({ nutrition, nutrition_estimated: true })
    .eq("id", recipeId);

  if (saveError) return json({ error: saveError.message }, 500);

  return json({ status: "estimated", nutrition });
});
