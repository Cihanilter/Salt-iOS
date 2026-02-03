//
//  CuratedRecipesManager.swift
//  Salt
//
//  Manages loading and caching of curated recipes from bundle
//

import Foundation

// MARK: - Curated Recipe (for JSON decoding with String ratings)

/// Intermediate model for decoding curated_recipes.json
/// Handles String ratings that need conversion to Double
private struct CuratedRecipeJSON: Codable {
    let id: UUID
    let createdAt: String?
    let updatedAt: String?
    let title: String
    let description: String?
    let imageUrl: String?
    let sourceUrl: String?
    let sourceName: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let prepTimeIso: String?
    let cookTimeIso: String?
    let totalTimeIso: String?
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let totalTimeMinutes: Int?
    let servings: Int?
    let servingsText: String?
    let ingredients: [String]
    let instructions: [String]
    let categories: [String]?
    let cuisines: [String]?
    let author: String?
    let rating: String?  // String in JSON
    let ratingCount: Int?
    let isCurated: Bool?
    let totalRating: String?  // String in JSON
    let nutrition: NutritionInfo?
    let publishedAt: String?

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

    /// Convert to Recipe model
    func toRecipe() -> Recipe {
        Recipe(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            title: title,
            description: description,
            imageUrl: imageUrl,
            sourceUrl: sourceUrl,
            sourceName: sourceName,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            prepTimeIso: prepTimeIso,
            cookTimeIso: cookTimeIso,
            totalTimeIso: totalTimeIso,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            totalTimeMinutes: totalTimeMinutes,
            servings: servings,
            servingsText: servingsText,
            ingredients: ingredients,
            instructions: instructions,
            categories: categories,
            cuisines: cuisines,
            author: author,
            rating: rating.flatMap { Double($0) },
            ratingCount: ratingCount,
            isCurated: isCurated,
            totalRating: totalRating.flatMap { Double($0) },
            nutrition: nutrition,
            publishedAt: publishedAt
        )
    }
}

// MARK: - Curated Recipes Manager

@MainActor
class CuratedRecipesManager {
    static let shared = CuratedRecipesManager()

    // MARK: - Cached Data

    private var allRecipes: [Recipe] = []
    private var recipesByCuisine: [String: [Recipe]] = [:]
    private var recipesByCategory: [String: [Recipe]] = [:]
    private var isLoaded = false

    private init() {
        loadFromBundle()
    }

    // MARK: - Load from Bundle

    private func loadFromBundle() {
        guard let url = Bundle.main.url(forResource: "curated_recipes", withExtension: "json") else {
            print("❌ curated_recipes.json not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let jsonRecipes = try decoder.decode([CuratedRecipeJSON].self, from: data)
            allRecipes = jsonRecipes.map { $0.toRecipe() }

            // Index by cuisine
            for recipe in allRecipes {
                if let cuisines = recipe.cuisines {
                    for cuisine in cuisines {
                        recipesByCuisine[cuisine, default: []].append(recipe)
                    }
                }
            }

            // Index by category
            for recipe in allRecipes {
                if let categories = recipe.categories {
                    for category in categories {
                        recipesByCategory[category, default: []].append(recipe)
                    }
                }
            }

            isLoaded = true
            print("✅ Loaded \(allRecipes.count) curated recipes from bundle")
            print("   Cuisines: \(recipesByCuisine.keys.sorted().joined(separator: ", "))")
            print("   Categories: \(recipesByCategory.keys.count) total")
        } catch {
            print("❌ Failed to load curated_recipes.json: \(error)")
        }
    }

    // MARK: - Public API

    /// Get all curated recipes
    var recipes: [Recipe] {
        allRecipes
    }

    /// Get curated recipes for a specific cuisine
    func recipes(forCuisine cuisine: String) -> [Recipe] {
        recipesByCuisine[cuisine] ?? []
    }

    /// Get curated recipes for a specific category
    func recipes(forCategory category: String) -> [Recipe] {
        recipesByCategory[category] ?? []
    }

    /// Get curated recipes for a section (cuisine or category)
    func recipes(forSection name: String, isCuisine: Bool, limit: Int = 6) -> [Recipe] {
        let recipes = isCuisine ? recipesByCuisine[name] : recipesByCategory[name]
        guard let recipes = recipes else { return [] }

        // Sort by total rating (highest first)
        let sorted = recipes.sorted { ($0.totalRating ?? 0) > ($1.totalRating ?? 0) }
        return Array(sorted.prefix(limit))
    }

    /// Get available cuisines that have recipes
    var availableCuisines: [String] {
        Array(recipesByCuisine.keys).sorted()
    }

    /// Get available categories that have recipes
    var availableCategories: [String] {
        Array(recipesByCategory.keys).sorted()
    }

    /// Check if a recipe ID is in curated list
    func isCurated(_ recipeId: UUID) -> Bool {
        allRecipes.contains { $0.id == recipeId }
    }

    /// Search curated recipes by title
    func search(_ query: String, limit: Int = 20) -> [Recipe] {
        guard !query.isEmpty else { return [] }

        let lowercasedQuery = query.lowercased()
        let results = allRecipes.filter { $0.title.lowercased().contains(lowercasedQuery) }

        // Sort: prefix matches first, then by rating
        let sorted = results.sorted { r1, r2 in
            let r1Prefix = r1.title.lowercased().hasPrefix(lowercasedQuery)
            let r2Prefix = r2.title.lowercased().hasPrefix(lowercasedQuery)

            if r1Prefix != r2Prefix {
                return r1Prefix
            }
            return (r1.totalRating ?? 0) > (r2.totalRating ?? 0)
        }

        return Array(sorted.prefix(limit))
    }
}
