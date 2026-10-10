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
    private static let collectionSelect = "id, name, created_at, collection_recipes(\(entrySelect))"
    private static let entrySelect = "id, user_recipe_id, recipe_id, added_at, user_recipes(*), recipes(*)"

    private init() {}

    private func userId() async throws -> UUID {
        guard let userId = try? await supabase.auth.session.user.id else {
            throw RecipeServiceError.notAuthenticated
        }
        return userId
    }

    /// The user's collections, oldest first
    func fetchCollections() async throws -> [RecipeCollection] {
        let userId = try await userId()
        let response = try await supabase
            .from("collections")
            .select(Self.collectionSelect)
            .eq("owner_id", value: userId.uuidString)
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
