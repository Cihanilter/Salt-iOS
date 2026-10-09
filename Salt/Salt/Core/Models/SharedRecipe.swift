//
//  SharedRecipe.swift
//  Salt
//
//  Snapshot of a recipe shared with a link (shared_recipes table)
//

import Foundation

struct SharedRecipe: Codable {
    let code: String
    /// Set when an Explore recipe was shared; saving it bookmarks the original
    let originalRecipeId: UUID?

    let title: String
    let description: String?
    let servingsText: String?
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let ingredients: [String]
    let instructions: [String]
    let notes: String?
    let images: [String]
    let sourceUrl: String?
    let sourceName: String?
    let nutrition: NutritionInfo?
    let nutritionEstimated: Bool?

    enum CodingKeys: String, CodingKey {
        case code
        case originalRecipeId = "original_recipe_id"
        case title
        case description
        case servingsText = "servings_text"
        case prepTimeMinutes = "prep_time_minutes"
        case cookTimeMinutes = "cook_time_minutes"
        case ingredients
        case instructions
        case notes
        case images
        case sourceUrl = "source_url"
        case sourceName = "source_name"
        case nutrition
        case nutritionEstimated = "nutrition_estimated"
    }

    /// The fields saved when sharing, taken from the recipe on screen
    struct Snapshot: Encodable {
        let ownerId: UUID
        let sourceRecipeId: UUID
        let originalRecipeId: UUID?
        let title: String
        let description: String?
        let servingsText: String?
        let prepTimeMinutes: Int?
        let cookTimeMinutes: Int?
        let ingredients: [String]
        let instructions: [String]
        let notes: String?
        let images: [String]
        let sourceUrl: String?
        let sourceName: String?
        let nutrition: NutritionInfo?
        let nutritionEstimated: Bool
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case ownerId = "owner_id"
            case sourceRecipeId = "source_recipe_id"
            case originalRecipeId = "original_recipe_id"
            case title
            case description
            case servingsText = "servings_text"
            case prepTimeMinutes = "prep_time_minutes"
            case cookTimeMinutes = "cook_time_minutes"
            case ingredients
            case instructions
            case notes
            case images
            case sourceUrl = "source_url"
            case sourceName = "source_name"
            case nutrition
            case nutritionEstimated = "nutrition_estimated"
            case updatedAt = "updated_at"
        }

        init(recipe: RecipeDetail, ownerId: UUID, sourceRecipeId: UUID, originalRecipeId: UUID?) {
            self.ownerId = ownerId
            self.sourceRecipeId = sourceRecipeId
            self.originalRecipeId = originalRecipeId
            title = recipe.title
            // RecipeDetail uses placeholder text for missing values
            description = ["No description available", "No description"].contains(recipe.description) ? nil : recipe.description
            servingsText = recipe.servings == "N/A" ? nil : recipe.servings
            prepTimeMinutes = Int(recipe.prepTime).flatMap { $0 > 0 ? $0 : nil }
            cookTimeMinutes = Int(recipe.cookTime).flatMap { $0 > 0 ? $0 : nil }
            ingredients = recipe.ingredients
            instructions = recipe.instructions
            notes = recipe.notes.isEmpty ? nil : recipe.notes
            images = recipe.images
            sourceUrl = recipe.sourceUrl
            sourceName = recipe.sourceName
            nutrition = recipe.nutrition
            nutritionEstimated = recipe.nutritionEstimated
            updatedAt = ISO8601DateFormatter().string(from: Date())
        }

        // Sends missing values as null, so sharing again clears fields removed since the last share
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(ownerId, forKey: .ownerId)
            try container.encode(sourceRecipeId, forKey: .sourceRecipeId)
            try container.encode(originalRecipeId, forKey: .originalRecipeId)
            try container.encode(title, forKey: .title)
            try container.encode(description, forKey: .description)
            try container.encode(servingsText, forKey: .servingsText)
            try container.encode(prepTimeMinutes, forKey: .prepTimeMinutes)
            try container.encode(cookTimeMinutes, forKey: .cookTimeMinutes)
            try container.encode(ingredients, forKey: .ingredients)
            try container.encode(instructions, forKey: .instructions)
            try container.encode(notes, forKey: .notes)
            try container.encode(images, forKey: .images)
            try container.encode(sourceUrl, forKey: .sourceUrl)
            try container.encode(sourceName, forKey: .sourceName)
            try container.encode(nutrition, forKey: .nutrition)
            try container.encode(nutritionEstimated, forKey: .nutritionEstimated)
            try container.encode(updatedAt, forKey: .updatedAt)
        }
    }
}

// MARK: - SharedRecipe to RecipeDetail Conversion

extension SharedRecipe {
    func toRecipeDetail() -> RecipeDetail {
        // Built through UserRecipe so durations, servings and images display the same way
        var recipe = UserRecipe.empty(userId: UUID())
        recipe.title = title
        recipe.description = description
        recipe.prepTimeMinutes = prepTimeMinutes
        recipe.cookTimeMinutes = cookTimeMinutes
        recipe.servingsText = servingsText
        recipe.ingredients = ingredients
        recipe.instructions = instructions
        recipe.notes = notes
        recipe.photos = images
        recipe.sourceUrl = sourceUrl
        recipe.sourceName = sourceName
        recipe.nutrition = nutrition
        recipe.nutritionEstimated = nutritionEstimated
        return recipe.toRecipeDetail()
    }
}
