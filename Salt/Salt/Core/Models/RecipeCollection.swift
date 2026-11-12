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
    static let maxPeople = 10

    let id: UUID
    let ownerId: UUID
    var name: String
    let createdAt: String?
    /// People the owner invited (not including the owner)
    var memberIds: [UUID]
    /// What each member can do; members missing here can add & edit
    var memberRoles: [UUID: CollectionRole]
    /// Role people get when they join with the invite link ("New members can")
    var newMemberRole: CollectionRole
    /// How many days a new invite link works; nil = never expires
    var inviteExpiryDays: Int?
    /// When the current invite link stops working; nil = no link, or it doesn't expire
    var inviteExpiresAt: Date?
    /// False before the database has link expiry (collection_roles.sql), so the row is hidden
    let supportsInviteExpiry: Bool
    /// Newest first
    var entries: [CollectionEntry]

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case createdAt = "created_at"
        case members = "collection_members"
        case entries = "collection_recipes"
        case newMemberRole = "new_member_role"
        case inviteExpiryDays = "invite_expiry_days"
        case inviteExpiresAt = "invite_expires_at"
    }

    private struct Member: Decodable {
        let userId: UUID
        /// Missing before the roles migration (collection_roles.sql); then everyone can edit
        let role: String?
        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case role
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        ownerId = try container.decode(UUID.self, forKey: .ownerId)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        let members = try container.decodeIfPresent([Member].self, forKey: .members) ?? []
        memberIds = members.map(\.userId)
        memberRoles = Dictionary(
            members.compactMap { member in member.role.flatMap(CollectionRole.init(rawValue:)).map { (member.userId, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        newMemberRole = (try? container.decodeIfPresent(String.self, forKey: .newMemberRole))
            .flatMap { $0.flatMap(CollectionRole.init(rawValue:)) } ?? .editor
        supportsInviteExpiry = container.contains(.inviteExpiryDays)
        inviteExpiryDays = try? container.decodeIfPresent(Int.self, forKey: .inviteExpiryDays)
        inviteExpiresAt = (try? container.decodeIfPresent(String.self, forKey: .inviteExpiresAt))
            .flatMap { $0.flatMap(Self.parseDate) }
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

    /// Postgres timestamps, with or without fractional seconds
    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    /// Choices for "Link expires"; nil = never
    static let inviteExpiryOptions: [Int?] = [1, 7, 30, nil]

    /// "1 day", "7 days", "Never"
    static func inviteExpiryTitle(_ days: Int?) -> String {
        guard let days else { return String(localized: "Never") }
        return days == 1 ? String(localized: "1 day") : String(localized: "\(days) days")
    }

    /// "In 7 days" for the current link, or how long a new one will last
    var inviteExpiryStatus: String {
        guard let days = inviteExpiryDays else { return String(localized: "Never") }
        guard let inviteExpiresAt else { return Self.inviteExpiryTitle(days) }
        let left = inviteExpiresAt.timeIntervalSinceNow
        if left <= 0 { return String(localized: "Expired") }
        let daysLeft = Int((left / 86_400).rounded(.up))
        return daysLeft <= 1 ? String(localized: "Within a day") : String(localized: "In \(daysLeft) days")
    }

    /// The owner, or a member who can add & edit: adds and removes recipes
    var canCurrentUserEdit: Bool {
        if isOwnedByCurrentUser { return true }
        guard let me = AuthManager.shared.currentUser?.id.lowercased(),
              let myId = memberIds.first(where: { $0.uuidString.lowercased() == me }) else { return false }
        return memberRoles[myId] != .viewer
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
/// What a member of a shared collection can do
enum CollectionRole: String, CaseIterable, Identifiable {
    /// Can add & edit: adds and removes recipes
    case editor
    /// Can only view
    case viewer

    var id: String { rawValue }

    /// "Can add & edit", under the member's name
    var title: String {
        switch self {
        case .editor: String(localized: "Can add & edit")
        case .viewer: String(localized: "Can only view")
        }
    }

    /// "Add & edit", after "New members can"
    var shortTitle: String {
        switch self {
        case .editor: String(localized: "Add & edit")
        case .viewer: String(localized: "Only view")
        }
    }
}

struct CollectionMember: Decodable, Identifiable {
    let userId: UUID
    let fullName: String?
    let profileImageUrl: String?
    let isOwner: Bool
    /// nil for the owner; editor before the roles migration
    var role: CollectionRole?

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
        case role
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
        profileImageUrl = try container.decodeIfPresent(String.self, forKey: .profileImageUrl)
        isOwner = try container.decode(Bool.self, forKey: .isOwner)
        let rawRole = try container.decodeIfPresent(String.self, forKey: .role)
        role = isOwner ? nil : (rawRole.flatMap(CollectionRole.init(rawValue:)) ?? .editor)
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
