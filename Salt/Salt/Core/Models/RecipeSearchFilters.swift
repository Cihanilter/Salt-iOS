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
    /// Any of these; `DishType.name`s, the same choices as Explore's category chips
    var dishTypes: Set<String> = []

    var isActive: Bool {
        !ingredients.isEmpty || maxTotalMinutes != nil || !cuisines.isEmpty || !dishTypes.isEmpty
    }

    var activeCount: Int {
        [!ingredients.isEmpty, maxTotalMinutes != nil, !cuisines.isEmpty, !dishTypes.isEmpty]
            .filter { $0 }.count
    }

    /// The picked types that are meal types (search_recipes `p_meal_types`)
    var mealTypeValues: [String]? {
        let values = MealType.allCases.filter { dishTypes.contains($0.category) }.map(\.rawValue)
        return values.isEmpty ? nil : values
    }

    /// The other picked types, e.g. Cookies or Pasta, matched on the recipes' categories
    /// (search_recipes `p_dish_categories`)
    var otherCategoryValues: [String]? {
        let mealTypeCategories = Set(MealType.allCases.map(\.category))
        let values = DishType.all.map(\.name).filter { dishTypes.contains($0) && !mealTypeCategories.contains($0) }
        return values.isEmpty ? nil : values
    }

    // MARK: - Options

    /// Choices in the Total time filter
    static let timeOptions = [15, 30, 45, 60]

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

    /// What a chip shows once set: the chosen values ("Chicken, Garlic"), shortened when
    /// there are more or they're long ("Chicken +2")
    private static func label(for values: [String]) -> String? {
        guard let first = values.first else { return nil }
        if values.count == 1 { return first }
        let joined = values.joined(separator: ", ")
        if values.count == 2 && joined.count <= 18 { return joined }
        return "\(first) +\(values.count - 1)"
    }

    var ingredientsLabel: String? {
        Self.label(for: ingredients)
    }

    var timeLabel: String? {
        maxTotalMinutes.map { $0 == 60 ? "Under 1 hour" : "Under \($0) min" }
    }

    var cuisineLabel: String? {
        Self.label(for: cuisines.sorted())
    }

    var mealTypeLabel: String? {
        Self.label(for: DishType.all.filter { dishTypes.contains($0.name) }.map(\.displayName))
    }
}

/// A recipe category: Explore's chips and the Meal type filter in search
struct DishType: Identifiable {
    /// As stored in the recipes table's categories
    let name: String
    let displayName: String
    let icon: String

    var id: String { name }

    static let all = [
        DishType(name: "Desserts", displayName: "Desserts", icon: "dessertIcon"),
        DishType(name: "Side Dish", displayName: "Side Dish", icon: "pastaIcon"),
        DishType(name: "Main Dishes", displayName: "Main Dish", icon: "mainDishIcon"),
        DishType(name: "Appetizers and Snacks", displayName: "Snacks", icon: "tapasIcon"),
        DishType(name: "Soups, Stews and Chili Recipes", displayName: "Soups", icon: "soupIcon"),
        DishType(name: "Salad", displayName: "Salad", icon: "vegetarianIcon"),
        DishType(name: "Breakfast and Brunch", displayName: "Breakfast", icon: "bakeryIcon"),
        DishType(name: "Bread", displayName: "Bread", icon: "bakeryIcon"),
        DishType(name: "Drink Recipes", displayName: "Drinks", icon: "drinksIcon"),
        DishType(name: "Seafood", displayName: "Seafood", icon: "seafoodIcon"),
        DishType(name: "Cookies", displayName: "Cookies", icon: "cookiesIcon"),
        DishType(name: "Cakes", displayName: "Cakes", icon: "cakeIcon"),
        DishType(name: "Pasta", displayName: "Pasta", icon: "pastaIcon"),
        DishType(name: "Vegetarian", displayName: "Vegetarian", icon: "vegetarianIcon"),
        DishType(name: "Sandwich Recipes", displayName: "Sandwich", icon: "sandwichIcon"),
        DishType(name: "Smoothie Recipes", displayName: "Smoothies", icon: "vegetarianIcon"),
        DishType(name: "Sauces and Condiments", displayName: "Sauces", icon: "onePotIcon")
    ]
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
