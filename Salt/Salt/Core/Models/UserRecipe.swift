//
//  UserRecipe.swift
//  Salt
//
//  User-created recipe model
//

import Foundation

// MARK: - User Recipe Model

struct UserRecipe: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let createdAt: String?
    let updatedAt: String?

    // Basic info
    var title: String
    var description: String?
    var imageUrl: String?

    // Time data
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var totalTimeMinutes: Int?

    // Servings
    var servings: Int?
    var servingsText: String?

    // Recipe content
    var ingredients: [String]
    var instructions: [String]

    // Categories
    var cuisines: [String]?
    var dishTypes: [String]?

    // Notes
    var notes: String?

    // Source (for imported recipes)
    var sourceUrl: String?
    var sourceName: String?

    // Photos (array of URLs)
    var photos: [String]?

    // MARK: - Computed Properties

    var durationText: String {
        let prep = prepTimeMinutes ?? 0
        let cook = cookTimeMinutes ?? 0
        let calculatedTotal = prep + cook

        // Use calculated sum if total_time doesn't match (DB may have errors)
        let total: Int
        if let dbTotal = totalTimeMinutes, dbTotal > 0 {
            if calculatedTotal > 0 && dbTotal != calculatedTotal {
                total = calculatedTotal
            } else {
                total = dbTotal
            }
        } else {
            total = calculatedTotal > 0 ? calculatedTotal : 0
        }

        if total > 0 {
            if total >= 60 {
                let hours = total / 60
                let mins = total % 60
                return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
            }
            return "\(total) min"
        }
        return "N/A"
    }

    var ingredientCount: Int {
        ingredients.count
    }

    var displayImageUrl: String {
        if let firstPhoto = photos?.first, !firstPhoto.isEmpty {
            return firstPhoto
        }
        return imageUrl ?? ""
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case title
        case description
        case imageUrl = "image_url"
        case prepTimeMinutes = "prep_time_minutes"
        case cookTimeMinutes = "cook_time_minutes"
        case totalTimeMinutes = "total_time_minutes"
        case servings
        case servingsText = "servings_text"
        case ingredients
        case instructions
        case cuisines
        case dishTypes = "dish_types"
        case notes
        case sourceUrl = "source_url"
        case sourceName = "source_name"
        case photos
    }

    // MARK: - Empty Recipe for Creation

    static func empty(userId: UUID) -> UserRecipe {
        UserRecipe(
            id: UUID(),
            userId: userId,
            createdAt: nil,
            updatedAt: nil,
            title: "",
            description: nil,
            imageUrl: nil,
            prepTimeMinutes: nil,
            cookTimeMinutes: nil,
            totalTimeMinutes: nil,
            servings: nil,
            servingsText: nil,
            ingredients: [],
            instructions: [],
            cuisines: nil,
            dishTypes: nil,
            notes: nil,
            sourceUrl: nil,
            sourceName: nil,
            photos: nil
        )
    }
}

// MARK: - UserRecipe to RecipeDetail Conversion

extension UserRecipe {
    func toRecipeDetail() -> RecipeDetail {
        // Handle servings
        let servingsDisplayText: String
        if let text = servingsText, !text.isEmpty {
            servingsDisplayText = text
        } else if let count = servings {
            servingsDisplayText = "\(count) servings"
        } else {
            servingsDisplayText = "N/A"
        }

        // Format prep/cook time
        let prepDisplay = prepTimeMinutes.map { "\($0)" } ?? "0"
        let cookDisplay = cookTimeMinutes.map { "\($0)" } ?? "0"

        // Notes text - empty string if no notes (don't show default text)
        let notesText = notes ?? ""

        // Build images array
        var images: [String] = []
        if let recipePhotos = photos {
            images.append(contentsOf: recipePhotos.filter { !$0.isEmpty })
        }
        if images.isEmpty, let imageUrl = imageUrl, !imageUrl.isEmpty {
            images.append(imageUrl)
        }

        return RecipeDetail(
            title: title,
            duration: durationText,
            ingredientsCount: "\(ingredientCount) ingredients",
            description: description ?? "No description available",
            servings: servingsDisplayText,
            prepTime: prepDisplay,
            cookTime: cookDisplay,
            ingredients: ingredients,
            instructions: instructions,
            notes: notesText,
            images: images,
            sourceUrl: sourceUrl,
            sourceName: sourceName
        )
    }
}

// MARK: - Bookmark Model

struct RecipeBookmark: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let recipeId: UUID
    let bookmarkedAt: String?
    let isFavorite: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case recipeId = "recipe_id"
        case bookmarkedAt = "bookmarked_at"
        case isFavorite = "is_favorite"
    }
}
