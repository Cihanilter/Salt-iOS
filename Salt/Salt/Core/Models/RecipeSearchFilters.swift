//
//  RecipeSearchFilters.swift
//  Salt
//
//  Filters for Explore search: ingredients, total time, cuisine and meal type
//

import Foundation

struct RecipeSearchFilters: Equatable {
    /// Every one must be in the recipe (e.g. "chicken" and "rice")
    var ingredients: [String] = []
    /// Total time up to this many minutes
    var maxTotalMinutes: Int?
    /// Any of these
    var cuisines: Set<String> = []
    /// Any of these
    var mealTypes: Set<MealType> = []

    var isActive: Bool {
        !ingredients.isEmpty || maxTotalMinutes != nil || !cuisines.isEmpty || !mealTypes.isEmpty
    }

    var activeCount: Int {
        [!ingredients.isEmpty, maxTotalMinutes != nil, !cuisines.isEmpty, !mealTypes.isEmpty]
            .filter { $0 }.count
    }

    // MARK: - Options

    /// Choices in the Total time filter
    static let timeOptions = [15, 30, 45, 60, 90]

    /// Quick picks in the Ingredients filter
    static let suggestedIngredients = [
        "Chicken", "Beef", "Salmon", "Shrimp", "Eggs", "Pasta", "Rice",
        "Potato", "Tomato", "Cheese", "Mushroom", "Tofu", "Chickpeas", "Spinach"
    ]

    /// Cuisines as stored in the recipes table
    static let cuisineOptions = [
        "African", "American", "Asian", "British", "Cajun", "Caribbean", "Chinese",
        "Eastern European", "European", "French", "German", "Greek", "Indian", "Irish",
        "Italian", "Japanese", "Jewish", "Korean", "Latin American", "Mexican",
        "Middle Eastern", "Nordic", "South American", "Southern", "Spanish", "Thai",
        "Ukrainian", "Vietnamese"
    ]

    // MARK: - Labels for the filter chips

    var ingredientsLabel: String? {
        guard let first = ingredients.first else { return nil }
        return ingredients.count == 1 ? first : "\(first) +\(ingredients.count - 1)"
    }

    var timeLabel: String? {
        maxTotalMinutes.map { "Under \($0) min" }
    }

    var cuisineLabel: String? {
        let sorted = cuisines.sorted()
        guard let first = sorted.first else { return nil }
        return sorted.count == 1 ? first : "\(first) +\(sorted.count - 1)"
    }

    var mealTypeLabel: String? {
        let sorted = MealType.allCases.filter(mealTypes.contains)
        guard let first = sorted.first else { return nil }
        return sorted.count == 1 ? first.displayName : "\(first.displayName) +\(sorted.count - 1)"
    }
}

/// Meal types; raw values match the recipes table's meal_types
enum MealType: String, CaseIterable, Identifiable {
    case breakfast, mainDish, appetizers, soups, salads, sides, desserts, bread, drinks, sauces

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: "Breakfast"
        case .mainDish: "Main Dish"
        case .appetizers: "Snacks"
        case .soups: "Soups"
        case .salads: "Salads"
        case .sides: "Side Dish"
        case .desserts: "Desserts"
        case .bread: "Bread"
        case .drinks: "Drinks"
        case .sauces: "Sauces"
        }
    }

    /// Source category, used for recipes that don't have meal_types yet
    var category: String {
        switch self {
        case .breakfast: "Breakfast and Brunch"
        case .mainDish: "Main Dishes"
        case .appetizers: "Appetizers and Snacks"
        case .soups: "Soups, Stews and Chili Recipes"
        case .salads: "Salad"
        case .sides: "Side Dish"
        case .desserts: "Desserts"
        case .bread: "Bread"
        case .drinks: "Drink Recipes"
        case .sauces: "Sauces and Condiments"
        }
    }

    /// Matches recipes with this meal type, or the source category if they aren't classified yet.
    /// PostgREST `or` filter; mirrors the meal type logic in the search_recipes function.
    var recipesFilter: String {
        "meal_types.cs.{\(rawValue)},and(meal_types.is.null,categories.cs.{\"\(category)\"})"
    }
}
