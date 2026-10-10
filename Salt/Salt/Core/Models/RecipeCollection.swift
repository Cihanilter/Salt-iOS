//
//  RecipeCollection.swift
//  Salt
//
//  A user-named group of recipes (collections table), e.g. "Weeknight Dinners"
//

import Foundation

struct RecipeCollection: Identifiable, Decodable {
    /// Longest allowed name, also enforced by the database
    static let maxNameLength = 20

    let id: UUID
    var name: String
    let createdAt: String?
    /// Newest first
    var entries: [CollectionEntry]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
        case entries = "collection_recipes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        entries = (try container.decodeIfPresent([CollectionEntry].self, forKey: .entries) ?? [])
            .sorted { ($0.addedAt ?? "") > ($1.addedAt ?? "") }
    }

    /// Recipes that can still be shown (a recipe deleted elsewhere drops out)
    var items: [MyRecipeItem] {
        entries.compactMap(\.item)
    }

    /// Photos for the cover mosaic, newest recipes first
    var coverImageUrls: [String] {
        items.prefix(4).compactMap { item in
            let url = item.displayImageUrl
            return url.isEmpty ? nil : url
        }
    }

    func contains(_ ref: CollectionRecipeRef) -> Bool {
        entries.contains { $0.ref == ref }
    }
}

/// One recipe in a collection (collection_recipes table), with the recipe embedded
struct CollectionEntry: Identifiable, Decodable {
    let id: UUID
    let userRecipeId: UUID?
    let recipeId: UUID?
    let addedAt: String?
    let userRecipe: UserRecipe?
    let recipe: Recipe?

    enum CodingKeys: String, CodingKey {
        case id
        case userRecipeId = "user_recipe_id"
        case recipeId = "recipe_id"
        case addedAt = "added_at"
        case userRecipe = "user_recipes"
        case recipe = "recipes"
    }

    var ref: CollectionRecipeRef? {
        if let userRecipeId { return .own(userRecipeId) }
        if let recipeId { return .explore(recipeId) }
        return nil
    }

    var item: MyRecipeItem? {
        if let userRecipe { return .own(userRecipe) }
        if let recipe { return .saved(recipe) }
        return nil
    }
}

/// Which recipe a collection entry points to: the user's own (user_recipes)
/// or one from Explore (recipes)
enum CollectionRecipeRef: Hashable, Identifiable {
    case own(UUID)
    case explore(UUID)

    var id: String {
        switch self {
        case .own(let id): "own-\(id)"
        case .explore(let id): "explore-\(id)"
        }
    }

    init(_ item: MyRecipeItem) {
        switch item {
        case .own(let recipe): self = .own(recipe.id)
        case .saved(let recipe): self = .explore(recipe.id)
        }
    }
}

extension MyRecipeItem {
    var displayImageUrl: String {
        switch self {
        case .own(let recipe): recipe.displayImageUrl
        case .saved(let recipe): recipe.displayImageUrl
        }
    }

    var title: String {
        switch self {
        case .own(let recipe): recipe.title
        case .saved(let recipe): recipe.title
        }
    }
}
