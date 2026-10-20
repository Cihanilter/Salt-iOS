//
//  DisplayText.swift
//  Salt
//
//  Text the app builds in code, in the app's language: recipe times and counts, and the
//  names of cuisines and categories (stored in English in the database)
//

import Foundation

enum DisplayText {

    // MARK: Recipe times and counts

    /// "25 min", "1h 30m"; "N/A" without a time
    static func duration(minutes: Int) -> String {
        guard minutes > 0 else { return String(localized: "N/A", comment: "No cooking time") }
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return mins > 0
                ? String(localized: "\(hours)h \(mins)m", comment: "Cooking time in hours and minutes, e.g. 1h 30m")
                : String(localized: "\(hours)h", comment: "Cooking time in whole hours, e.g. 2h")
        }
        return String(localized: "\(minutes) min", comment: "Cooking time in minutes, e.g. 25 min")
    }

    /// "5 ingredients"
    static func ingredientCount(_ count: Int) -> String {
        String(localized: "\(count) ingredients", comment: "Number of ingredients in a recipe")
    }

    /// Recipes without a description carry one of these placeholders in RecipeDetail
    static let descriptionPlaceholders = ["No description available", "No description"]

    /// The recipe description, or "No description available" in the app's language
    static func description(_ text: String) -> String {
        descriptionPlaceholders.contains(text)
            ? String(localized: "No description available", comment: "Shown when a recipe has no description")
            : text
    }

    // MARK: Cuisines and categories

    /// A cuisine, category, meal type or quick-pick ingredient as shown in the app. The database
    /// values stay in English (they're what queries match); unknown names show as they are.
    static func food(_ name: String) -> String {
        switch name {
        // Cuisines
        case "African": String(localized: "African", comment: "Cuisine")
        case "American": String(localized: "American", comment: "Cuisine")
        case "Asian": String(localized: "Asian", comment: "Cuisine")
        case "British": String(localized: "British", comment: "Cuisine")
        case "Cajun": String(localized: "Cajun", comment: "Cuisine")
        case "Caribbean": String(localized: "Caribbean", comment: "Cuisine")
        case "Chinese": String(localized: "Chinese", comment: "Cuisine")
        case "Eastern European": String(localized: "Eastern European", comment: "Cuisine")
        case "European": String(localized: "European", comment: "Cuisine")
        case "French": String(localized: "French", comment: "Cuisine")
        case "German": String(localized: "German", comment: "Cuisine")
        case "Greek": String(localized: "Greek", comment: "Cuisine")
        case "Indian": String(localized: "Indian", comment: "Cuisine")
        case "Irish": String(localized: "Irish", comment: "Cuisine")
        case "Italian": String(localized: "Italian", comment: "Cuisine")
        case "Japanese": String(localized: "Japanese", comment: "Cuisine")
        case "Jewish": String(localized: "Jewish", comment: "Cuisine")
        case "Korean": String(localized: "Korean", comment: "Cuisine")
        case "Latin American": String(localized: "Latin American", comment: "Cuisine")
        case "Mediterranean": String(localized: "Mediterranean", comment: "Cuisine")
        case "Mexican": String(localized: "Mexican", comment: "Cuisine")
        case "Middle Eastern": String(localized: "Middle Eastern", comment: "Cuisine")
        case "Nordic": String(localized: "Nordic", comment: "Cuisine")
        case "South American": String(localized: "South American", comment: "Cuisine")
        case "Southern": String(localized: "Southern", comment: "Cuisine, food of the US South")
        case "Spanish": String(localized: "Spanish", comment: "Cuisine")
        case "Thai": String(localized: "Thai", comment: "Cuisine")
        case "Turkish": String(localized: "Turkish", comment: "Cuisine")
        case "Ukrainian": String(localized: "Ukrainian", comment: "Cuisine")
        case "Vietnamese": String(localized: "Vietnamese", comment: "Cuisine")

        // Categories and meal types
        case "Desserts": String(localized: "Desserts", comment: "Recipe category")
        case "Dessert": String(localized: "Dessert", comment: "Recipe category")
        case "Side Dish": String(localized: "Side Dish", comment: "Recipe category")
        case "Main Dish", "Main Dishes": String(localized: "Main Dish", comment: "Recipe category")
        case "Snacks", "Appetizers and Snacks": String(localized: "Snacks", comment: "Recipe category")
        case "Soups", "Soups, Stews and Chili Recipes": String(localized: "Soups", comment: "Recipe category")
        case "Salad": String(localized: "Salad", comment: "Recipe category")
        case "Salads": String(localized: "Salads", comment: "Recipe category")
        case "Breakfast", "Breakfast and Brunch": String(localized: "Breakfast", comment: "Recipe category")
        case "Bread": String(localized: "Bread", comment: "Recipe category")
        case "Drinks", "Drink Recipes": String(localized: "Drinks", comment: "Recipe category")
        case "Sauces", "Sauces and Condiments": String(localized: "Sauces", comment: "Recipe category")
        case "Seafood": String(localized: "Seafood", comment: "Recipe category")
        case "Cookies": String(localized: "Cookies", comment: "Recipe category")
        case "Cakes": String(localized: "Cakes", comment: "Recipe category")
        case "Pasta": String(localized: "Pasta", comment: "Recipe category")
        case "Vegetarian": String(localized: "Vegetarian", comment: "Recipe category")
        case "Sandwich", "Sandwich Recipes": String(localized: "Sandwich", comment: "Recipe category")
        case "Smoothies", "Smoothie Recipes": String(localized: "Smoothies", comment: "Recipe category")

        // Cooking interests on the profile
        case "Baking": String(localized: "Baking", comment: "Cooking interest")
        case "Healthy Eating": String(localized: "Healthy Eating", comment: "Cooking interest")
        case "Meal Prep": String(localized: "Meal Prep", comment: "Cooking interest")
        case "Quick & Easy": String(localized: "Quick & Easy", comment: "Cooking interest")

        default: name
        }
    }

    /// Quick picks in the Explore ingredients filter, in the app's language (they're matched
    /// against the ingredient text, which is Turkish for Turkish recipes)
    static var suggestedIngredients: [String] {
        [
            String(localized: "Chicken", comment: "Ingredient"), String(localized: "Beef", comment: "Ingredient"),
            String(localized: "Salmon", comment: "Ingredient"), String(localized: "Shrimp", comment: "Ingredient"),
            String(localized: "Eggs", comment: "Ingredient"), String(localized: "Pasta", comment: "Ingredient"),
            String(localized: "Rice", comment: "Ingredient"), String(localized: "Potato", comment: "Ingredient"),
            String(localized: "Tomato", comment: "Ingredient"), String(localized: "Cheese", comment: "Ingredient"),
            String(localized: "Mushroom", comment: "Ingredient"), String(localized: "Tofu", comment: "Ingredient"),
            String(localized: "Chickpeas", comment: "Ingredient"), String(localized: "Spinach", comment: "Ingredient")
        ]
    }

    /// Popular searches on Explore, searched in the app's language
    static var popularSearches: [String] {
        [
            String(localized: "Chicken", comment: "Popular search"), String(localized: "Pasta", comment: "Popular search"),
            String(localized: "Salad", comment: "Popular search"), String(localized: "search.dessert", defaultValue: "Dessert", comment: "Popular search; a search term, so singular (e.g. Turkish Tatlı)"),
            String(localized: "Soup", comment: "Popular search"), String(localized: "Breakfast", comment: "Popular search"),
            String(localized: "Pizza", comment: "Popular search"), String(localized: "search.cookies", defaultValue: "Cookies", comment: "Popular search; a search term, so singular (e.g. Turkish Kurabiye)")
        ]
    }
}
