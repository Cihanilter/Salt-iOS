//
//  CollectionService.swift
//  Salt
//
//  Supabase access for recipe collections (collections and collection_recipes tables)
//

import Foundation
import Supabase

final class CollectionService {
    static let shared = CollectionService()

    private var supabase: SupabaseClient {
        SupabaseClientManager.shared.client
    }

    /// Collection columns with each entry's recipe embedded, so a collection can be shown
    /// without loading the recipes separately
    private static let collectionSelect =
        "id, owner_id, name, created_at, collection_members(user_id), collection_recipes(\(entrySelect))"
    private static let entrySelect = "id, user_recipe_id, recipe_id, added_at, user_recipes(*), recipes(*)"

    private init() {}

    private func userId() async throws -> UUID {
        guard let userId = try? await supabase.auth.session.user.id else {
            throw RecipeServiceError.notAuthenticated
        }
        return userId
    }

    /// The user's own collections and the ones they joined, oldest first
    /// (access rules only return collections the user is in)
    func fetchCollections() async throws -> [RecipeCollection] {
        _ = try await userId()
        let response = try await supabase
            .from("collections")
            .select(Self.collectionSelect)
            .order("created_at", ascending: true)
            .execute()
        return try JSONDecoder().decode([RecipeCollection].self, from: response.data)
    }

    func createCollection(named name: String) async throws -> RecipeCollection {
        let userId = try await userId()
        let response = try await supabase
            .from("collections")
            .insert(["owner_id": userId.uuidString, "name": name])
            .select(Self.collectionSelect)
            .single()
            .execute()
        return try JSONDecoder().decode(RecipeCollection.self, from: response.data)
    }

    func renameCollection(_ id: UUID, to name: String) async throws {
        try await supabase
            .from("collections")
            .update(["name": name, "updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Deletes the collection only; its recipes stay in My Recipes
    func deleteCollection(_ id: UUID) async throws {
        try await supabase
            .from("collections")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func addRecipe(_ ref: CollectionRecipeRef, to collectionId: UUID) async throws -> CollectionEntry {
        var values = ["collection_id": collectionId.uuidString]
        switch ref {
        case .own(let id): values["user_recipe_id"] = id.uuidString
        case .explore(let id): values["recipe_id"] = id.uuidString
        }

        let response = try await supabase
            .from("collection_recipes")
            .insert(values)
            .select(Self.entrySelect)
            .single()
            .execute()
        return try JSONDecoder().decode(CollectionEntry.self, from: response.data)
    }

    // MARK: - Sharing

    /// The collection's invite code, created the first time (owner only)
    func inviteCode(for collectionId: UUID) async throws -> String {
        try await supabase
            .rpc("create_collection_invite", params: ["p_collection_id": collectionId.uuidString])
            .execute()
            .value
    }

    /// A new code; links sent before stop working (owner only)
    func resetInviteCode(for collectionId: UUID) async throws -> String {
        try await supabase
            .rpc("reset_collection_invite", params: ["p_collection_id": collectionId.uuidString])
            .execute()
            .value
    }

    /// Turns the invite link off (owner only)
    func disableInvite(for collectionId: UUID) async throws {
        try await supabase
            .rpc("disable_collection_invite", params: ["p_collection_id": collectionId.uuidString])
            .execute()
    }

    /// What an invite link shows before joining; nil if the link isn't valid anymore
    func invite(code: String) async throws -> CollectionInvite? {
        let invites: [CollectionInvite] = try await supabase
            .rpc("get_collection_invite", params: ["p_code": code])
            .execute()
            .value
        return invites.first
    }

    /// Joins the collection and returns its id
    func join(code: String) async throws -> UUID {
        do {
            return try await supabase
                .rpc("join_collection", params: ["p_code": code])
                .execute()
                .value
        } catch {
            throw CollectionShareError(error)
        }
    }

    func members(of collectionId: UUID) async throws -> [CollectionMember] {
        try await supabase
            .rpc("get_collection_members", params: ["p_collection_id": collectionId.uuidString])
            .execute()
            .value
    }

    /// Removes a member (owner), or the user themselves (leaving)
    func removeMember(_ userId: UUID, from collectionId: UUID) async throws {
        try await supabase
            .from("collection_members")
            .delete()
            .eq("collection_id", value: collectionId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    func leave(_ collectionId: UUID) async throws {
        try await removeMember(try await userId(), from: collectionId)
    }

    // MARK: - Recipes

    func removeRecipe(_ ref: CollectionRecipeRef, from collectionId: UUID) async throws {
        let query = supabase
            .from("collection_recipes")
            .delete()
            .eq("collection_id", value: collectionId.uuidString)

        switch ref {
        case .own(let id): try await query.eq("user_recipe_id", value: id.uuidString).execute()
        case .explore(let id): try await query.eq("recipe_id", value: id.uuidString).execute()
        }
    }
}
