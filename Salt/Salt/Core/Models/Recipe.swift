//
//  Recipe.swift
//  Salt
//
//  Updated for AllRecipes database schema
//

import Foundation

// MARK: - Recipe Model (AllRecipes Schema)

struct Recipe: Identifiable, Codable {
    let id: UUID
    let createdAt: String?
    let updatedAt: String?

    // Basic info
    let title: String
    let description: String?
    let imageUrl: String?
    let sourceUrl: String?
    let sourceName: String?

    // Image dimensions
    let imageWidth: Int?
    let imageHeight: Int?

    // Time data (ISO format stored separately)
    let prepTimeIso: String?
    let cookTimeIso: String?
    let totalTimeIso: String?

    // Time data (parsed minutes)
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let totalTimeMinutes: Int?

    // Servings
    let servings: Int?
    let servingsText: String?

    // Recipe content (JSONB arrays of strings)
    let ingredients: [String]
    let instructions: [String]

    // Categories (PostgreSQL arrays)
    let categories: [String]?
    let cuisines: [String]?

    // Author & Source
    let author: String?

    // Rating
    let rating: Double?
    let ratingCount: Int?

    // Curated recipes sorting (added for high-quality recipe prioritization)
    let isCurated: Bool?       // True if recipe is in the curated/handpicked list
    let totalRating: Double?   // Computed: rating * rating_count (for sorting)

    // Nutrition (JSONB object)
    let nutrition: NutritionInfo?

    // Publication date
    let publishedAt: String?

    // MARK: - Computed Properties

    var durationText: String {
        let prep = prepTimeMinutes ?? 0
        let cook = cookTimeMinutes ?? 0
        let calculatedTotal = prep + cook

        // Use calculated sum if total_time doesn't match (DB may have errors)
        let total: Int
        if let dbTotal = totalTimeMinutes, dbTotal > 0 {
            // If we have prep and cook times and they don't match DB total, use calculated
            if calculatedTotal > 0 && dbTotal != calculatedTotal {
                total = calculatedTotal
            } else {
                total = dbTotal
            }
        } else {
            // No DB total, use calculated if available
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

    var cuisineText: String {
        guard let cuisines = cuisines, !cuisines.isEmpty else {
            return "Various"
        }
        return cuisines.prefix(2).joined(separator: ", ")
    }

    var categoryText: String {
        guard let categories = categories, !categories.isEmpty else {
            return "General"
        }
        return categories.first ?? "General"
    }

    var ingredientCount: Int {
        ingredients.count
    }

    var ratingText: String {
        guard let rating = rating else { return "N/A" }
        return String(format: "%.1f", rating)
    }

    var displayImageUrl: String {
        guard let url = imageUrl, !url.isEmpty else { return "" }

        // Extract original image URL from Meredith proxy URL
        // Format: https://imagesvc.meredithcorp.io/v3/mm/image?url=https%3A%2F%2Fimages.media-allrecipes.com%2F...
        if url.contains("imagesvc.meredithcorp.io") {
            if let range = url.range(of: "url="),
               let encodedUrl = url[range.upperBound...].removingPercentEncoding {
                return encodedUrl
            }
        }

        return url
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case title
        case description
        case imageUrl = "image_url"
        case sourceUrl = "source_url"
        case sourceName = "source_name"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case prepTimeIso = "prep_time_iso"
        case cookTimeIso = "cook_time_iso"
        case totalTimeIso = "total_time_iso"
        case prepTimeMinutes = "prep_time_minutes"
        case cookTimeMinutes = "cook_time_minutes"
        case totalTimeMinutes = "total_time_minutes"
        case servings
        case servingsText = "servings_text"
        case ingredients
        case instructions
        case categories
        case cuisines
        case author
        case rating
        case ratingCount = "rating_count"
        case isCurated = "is_curated"
        case totalRating = "total_rating"
        case nutrition
        case publishedAt = "published_at"
    }
}

// MARK: - Nutrition Info Model

struct NutritionInfo: Codable {
    let type: String?
    let calories: String?
    let carbohydrateContent: String?
    let proteinContent: String?
    let fatContent: String?
    let saturatedFatContent: String?
    let fiberContent: String?
    let sugarContent: String?
    let sodiumContent: String?
    let cholesterolContent: String?
    let servingSize: String?

    enum CodingKeys: String, CodingKey {
        case type = "@type"
        case calories
        case carbohydrateContent
        case proteinContent
        case fatContent
        case saturatedFatContent
        case fiberContent
        case sugarContent
        case sodiumContent
        case cholesterolContent
        case servingSize
    }

    // Helper computed properties
    var caloriesText: String {
        calories ?? "N/A"
    }

    var proteinText: String {
        proteinContent ?? "N/A"
    }

    var carbsText: String {
        carbohydrateContent ?? "N/A"
    }

    var fatText: String {
        fatContent ?? "N/A"
    }
}

// MARK: - Recipe Extensions for Backward Compatibility

extension Recipe {
    // For views that expect these properties
    var vegetarian: Bool { false }
    var vegan: Bool { false }
    var glutenFree: Bool { false }
    var dairyFree: Bool { false }
    var dishTypes: [String] { categories ?? [] }
}
