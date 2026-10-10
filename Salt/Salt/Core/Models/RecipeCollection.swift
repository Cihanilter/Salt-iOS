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

    /// Most people in a collection, owner included (also enforced by the database)
    static let maxPeople = 5

    let id: UUID
    let ownerId: UUID
    var name: String
    let createdAt: String?
    /// People the owner invited (not including the owner)
    var memberIds: [UUID]
    /// Newest first
    var entries: [CollectionEntry]

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case createdAt = "created_at"
        case members = "collection_members"
        case entries = "collection_recipes"
    }

    private struct Member: Decodable {
        let userId: UUID
        enum CodingKeys: String, CodingKey { case userId = "user_id" }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        ownerId = try container.decode(UUID.self, forKey: .ownerId)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        memberIds = (try container.decodeIfPresent([Member].self, forKey: .members) ?? []).map(\.userId)
        entries = (try container.decodeIfPresent([CollectionEntry].self, forKey: .entries) ?? [])
            .sorted { ($0.addedAt ?? "") > ($1.addedAt ?? "") }
    }

    /// Has people other than the owner
    var isShared: Bool {
        !memberIds.isEmpty
    }

    var peopleCount: Int {
        1 + memberIds.count
    }

    var isFull: Bool {
        peopleCount >= Self.maxPeople
    }

    /// Whether the signed-in user owns it (otherwise they joined it)
    var isOwnedByCurrentUser: Bool {
        ownerId.uuidString.lowercased() == AuthManager.shared.currentUser?.id.lowercased()
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

// MARK: - Sharing

/// What an invite link shows before joining (get_collection_invite)
struct CollectionInvite: Decodable {
    let collectionId: UUID
    let name: String
    let ownerName: String?
    let ownerImageUrl: String?
    let peopleCount: Int
    let recipeCount: Int
    /// Already in the collection (owner or member)
    let isMember: Bool

    enum CodingKeys: String, CodingKey {
        case collectionId = "collection_id"
        case name
        case ownerName = "owner_name"
        case ownerImageUrl = "owner_image_url"
        case peopleCount = "people_count"
        case recipeCount = "recipe_count"
        case isMember = "is_member"
    }

    var isFull: Bool {
        peopleCount >= RecipeCollection.maxPeople
    }
}

/// Someone in a collection (get_collection_members)
struct CollectionMember: Decodable, Identifiable {
    let userId: UUID
    let fullName: String?
    let profileImageUrl: String?
    let isOwner: Bool

    var id: UUID { userId }

    var displayName: String {
        let name = fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Salt user" : name
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case fullName = "full_name"
        case profileImageUrl = "profile_image_url"
        case isOwner = "is_owner"
    }
}

/// Reasons joining a collection can fail, from the database's error messages
enum CollectionShareError: LocalizedError {
    case inviteNotFound
    case collectionFull
    case linkUnavailable
    case other(Error)

    init(_ error: Error) {
        let message = String(describing: error)
        if message.contains("collection_full") {
            self = .collectionFull
        } else if message.contains("invite_not_found") {
            self = .inviteNotFound
        } else {
            self = .other(error)
        }
    }

    var errorDescription: String? {
        switch self {
        case .inviteNotFound:
            return "This invite link isn't valid anymore. Ask for a new one."
        case .collectionFull:
            return "This collection already has \(RecipeCollection.maxPeople) people."
        case .linkUnavailable:
            return "Inviting isn't available right now. Please try again later."
        case .other:
            return "Couldn't join the collection. Check your connection and try again."
        }
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

extension UserRecipe {
    /// False for recipes other people added to a shared collection
    var isByCurrentUser: Bool {
        userId.uuidString.lowercased() == AuthManager.shared.currentUser?.id.lowercased()
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
