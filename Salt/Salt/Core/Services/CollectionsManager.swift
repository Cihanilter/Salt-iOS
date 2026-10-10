//
//  CollectionsManager.swift
//  Salt
//
//  The user's recipe collections, shared by My Recipes, collection screens and the
//  Add to Collection sheet so they all stay in sync.
//

import Foundation
import Combine

@MainActor
final class CollectionsManager: ObservableObject {
    static let shared = CollectionsManager()

    @Published private(set) var collections: [RecipeCollection] = []
    @Published private(set) var hasLoaded = false

    /// Empty example collection every new user starts with
    static let starterNames = ["Planned"]

    private let service = CollectionService.shared

    private init() {}

    // MARK: - Loading

    /// A load already running, so screens appearing together don't load (or seed) twice
    private var loadTask: Task<Void, Never>?

    func load() async {
        if let loadTask {
            return await loadTask.value
        }
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        do {
            var loaded = try await service.fetchCollections()
            if loaded.isEmpty, let userId = AuthManager.shared.currentUser?.id, !hasSeededStarters(for: userId) {
                // First time: add the example collections (once, so deleting them sticks)
                for name in Self.starterNames {
                    loaded.append(try await service.createCollection(named: name))
                }
                markStartersSeeded(for: userId)
            }
            collections = loaded
            hasLoaded = true
        } catch {
            print("⚠️ Failed to load collections: \(error)")
        }
    }

    private func seededKey(for userId: String) -> String {
        "collectionsStartersSeeded.\(userId)"
    }

    private func hasSeededStarters(for userId: String) -> Bool {
        UserDefaults.standard.bool(forKey: seededKey(for: userId))
    }

    private func markStartersSeeded(for userId: String) {
        UserDefaults.standard.set(true, forKey: seededKey(for: userId))
    }

    func collection(id: UUID) -> RecipeCollection? {
        collections.first { $0.id == id }
    }

    /// IDs of the collections a recipe is in
    func collectionIds(containing ref: CollectionRecipeRef) -> Set<UUID> {
        Set(collections.filter { $0.contains(ref) }.map(\.id))
    }

    // MARK: - Names

    /// Trims spaces and cuts the name to the allowed length
    static func cleanedName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(RecipeCollection.maxNameLength))
    }

    // MARK: - Collections

    @discardableResult
    func createCollection(named name: String) async throws -> RecipeCollection {
        let collection = try await service.createCollection(named: Self.cleanedName(name))
        collections.append(collection)
        Analytics.log(.collectionCreated)
        return collection
    }

    func renameCollection(_ id: UUID, to name: String) async throws {
        let name = Self.cleanedName(name)
        try await service.renameCollection(id, to: name)
        if let index = collections.firstIndex(where: { $0.id == id }) {
            collections[index].name = name
        }
    }

    func deleteCollection(_ id: UUID) async throws {
        try await service.deleteCollection(id)
        collections.removeAll { $0.id == id }
        Analytics.log(.collectionDeleted)
    }

    // MARK: - Recipes

    /// Adds the recipe, or removes it if it's already in the collection
    func toggle(_ ref: CollectionRecipeRef, in collectionId: UUID, source: String) async throws {
        guard let collection = collection(id: collectionId) else { return }
        if collection.contains(ref) {
            try await removeRecipe(ref, from: collectionId)
        } else {
            try await addRecipe(ref, to: collectionId, source: source)
        }
    }

    func addRecipe(_ ref: CollectionRecipeRef, to collectionId: UUID, source: String) async throws {
        guard collection(id: collectionId)?.contains(ref) == false else { return }

        let entry = try await service.addRecipe(ref, to: collectionId)
        if let index = collections.firstIndex(where: { $0.id == collectionId }) {
            collections[index].entries.insert(entry, at: 0)
        }

        // An Explore recipe in a collection is also saved, so it shows under Saved
        if case .explore(let recipeId) = ref, !BookmarkManager.shared.isBookmarked(recipeId) {
            _ = await BookmarkManager.shared.toggleBookmark(for: recipeId)
            await MyRecipesViewModel.shared.refresh()
        }
        Analytics.log(.recipeAddedToCollection, ["source": source])
    }

    func removeRecipe(_ ref: CollectionRecipeRef, from collectionId: UUID) async throws {
        try await service.removeRecipe(ref, from: collectionId)
        if let index = collections.firstIndex(where: { $0.id == collectionId }) {
            collections[index].entries.removeAll { $0.ref == ref }
        }
        Analytics.log(.recipeRemovedFromCollection)
    }

    /// Drops a deleted recipe from every collection (the database already removed the rows)
    func recipeWasDeleted(_ ref: CollectionRecipeRef) {
        for index in collections.indices {
            collections[index].entries.removeAll { $0.ref == ref }
        }
    }
}
