

import Foundation
import Combine
import UIKit

@MainActor
class MyRecipesViewModel: ObservableObject {
    // MARK: - Shared Instance (for prefetch)

    static let shared = MyRecipesViewModel()

    // MARK: - Published Properties

    @Published var searchText = ""
    @Published var userRecipes: [UserRecipe] = []
    @Published var bookmarkedRecipes: [Recipe] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showAllRecipes = false
    @Published private(set) var hasPrefetched = false

    // MARK: - Private Properties

    private let recipeService = RecipeService.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var filteredUserRecipes: [UserRecipe] {
        if searchText.isEmpty {
            return userRecipes
        }
        return userRecipes.filter { recipe in
            recipe.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var filteredBookmarkedRecipes: [Recipe] {
        if searchText.isEmpty {
            return bookmarkedRecipes
        }
        return bookmarkedRecipes.filter { recipe in
            recipe.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var displayedUserRecipes: [UserRecipe] {
        if showAllRecipes {
            return filteredUserRecipes
        } else {
            return Array(filteredUserRecipes.prefix(4))
        }
    }
    
    var hasMoreUserRecipes: Bool {
        filteredUserRecipes.count > 4
    }

    var hasContent: Bool {
        !userRecipes.isEmpty || !bookmarkedRecipes.isEmpty
    }

    var totalRecipesCount: Int {
        userRecipes.count + bookmarkedRecipes.count
    }

    // MARK: - Init

    private init() {
        setupSearchDebounce()
    }

    private func setupSearchDebounce() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.showAllRecipes = false // Reset when searching
            }
            .store(in: &cancellables)
    }

    // MARK: - Prefetch (called at app start)

    func prefetch() async {
        guard !hasPrefetched else { return }
        print("🚀 Prefetching My Recipes data...")
        await loadRecipes()
        hasPrefetched = true
        print("✅ My Recipes prefetch complete")
    }

    // MARK: - Load Data

    func loadRecipes() async {
        isLoading = true
        errorMessage = nil

        do {
            // Load both user recipes and bookmarked recipes in parallel
            async let userRecipesTask = recipeService.getUserRecipes()
            async let bookmarkedTask = loadBookmarkedRecipes()

            userRecipes = try await userRecipesTask
            bookmarkedRecipes = await bookmarkedTask

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadBookmarkedRecipes() async -> [Recipe] {
        do {
            return try await recipeService.getBookmarkedRecipes()
        } catch {
            print("Failed to load bookmarked recipes: \(error)")
            return []
        }
    }

    // MARK: - Tab Items

    /// Recipes for a My Recipes tab, optionally filtered by the search text
    func items(for tab: MyRecipesTab, searchFiltered: Bool) -> [MyRecipeItem] {
        let userRecipes = searchFiltered ? filteredUserRecipes : self.userRecipes
        let bookmarked = searchFiltered ? filteredBookmarkedRecipes : bookmarkedRecipes

        let own = userRecipes.filter { !$0.isCustomizedCopy }.map(MyRecipeItem.own)
        // Customized copies of the app's recipes sit with the bookmarks, but open as the
        // user's own recipe (Edit / Delete). A customized original stays bookmarked;
        // only its copy is listed so it doesn't appear twice.
        let copies = userRecipes.filter(\.isCustomizedCopy)
        let customizedIds = Set(self.userRecipes.compactMap(\.originalRecipeId))
        let saved = copies.map(MyRecipeItem.own)
            + bookmarked
                .filter { !customizedIds.contains($0.id) }
                .map(MyRecipeItem.saved)

        switch tab {
        case .all: return own + saved
        case .imports: return own
        case .saved: return saved
        }
    }

    // MARK: - Refresh

    func refresh() async {
        showAllRecipes = false
        await loadRecipes()
    }
    // MARK: - Delete Recipe

    func deleteUserRecipe(_ recipe: UserRecipe) async {
        do {
            try await recipeService.deleteRecipe(recipe.id)
            userRecipes.removeAll { $0.id == recipe.id }
            CollectionsManager.shared.recipeWasDeleted(.own(recipe.id))
            Analytics.log(.recipeDeleted, ["screen": "my_recipes"])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRecipe(id: UUID) async throws {
        try await recipeService.deleteRecipe(id)
        userRecipes.removeAll { $0.id == id }
        CollectionsManager.shared.recipeWasDeleted(.own(id))
        Analytics.log(.recipeDeleted, ["screen": "recipe_detail"])
    }

    // MARK: - Edit Recipe

    /// Saves edits to one of the user's own recipes and updates it in the list.
    /// New photos are added after the existing ones. Nutrition is cleared when ingredients or
    /// servings changed; the caller runs the new estimate.
    func updateRecipe(id: UUID, with detail: RecipeDetail, newPhotos: [UIImage]) async throws -> UserRecipe {
        guard let index = userRecipes.firstIndex(where: { $0.id == id }) else {
            throw RecipeServiceError.recipeNotFound
        }

        let original = userRecipes[index]
        var updated = original
        updated.applyEdits(from: detail)
        try await setPhotos(of: &updated, existing: detail.images, newPhotos: newPhotos)

        let nutritionIsStale = updated.ingredients != original.ingredients
            || updated.servingsText != original.servingsText
        if nutritionIsStale {
            updated.nutrition = nil
            updated.nutritionEstimated = nil
        }

        try await recipeService.updateRecipe(updated, clearNutrition: nutritionIsStale)
        Analytics.log(.recipeEdited, [
            "ingredients_changed": updated.ingredients != original.ingredients,
            "photos_added": newPhotos.count
        ])
        // The list may have changed while saving
        if let index = userRecipes.firstIndex(where: { $0.id == id }) {
            userRecipes[index] = updated
        }
        return updated
    }

    /// Saves an edited copy of an Explore/saved recipe as the user's own recipe and bookmarks
    /// the original. The original stays as it is for everyone. The caller runs the nutrition estimate.
    func saveCustomizedCopy(of originalId: UUID, from detail: RecipeDetail, newPhotos: [UIImage]) async throws -> UserRecipe {
        guard let userIdString = AuthManager.shared.currentUser?.id,
              let userId = UUID(uuidString: userIdString) else {
            throw RecipeServiceError.notAuthenticated
        }

        var copy = UserRecipe.empty(userId: userId)
        copy.applyEdits(from: detail)
        copy.sourceUrl = detail.sourceUrl
        copy.sourceName = detail.sourceName
        copy.originalRecipeId = originalId
        try await setPhotos(of: &copy, existing: detail.images, newPhotos: newPhotos)

        // "manual" so the copy isn't logged as an import (free-tier limit)
        let created = try await recipeService.createRecipe(copy, source: "manual", estimateNutrition: false)
        userRecipes.insert(created, at: 0)
        Analytics.log(.recipeCustomized)

        // Customizing also saves the original, so it shows as bookmarked in Explore.
        // My Recipes lists the copy in its place.
        let bookmarkManager = BookmarkManager.shared
        if !bookmarkManager.isBookmarked(originalId) {
            _ = await bookmarkManager.toggleBookmark(for: originalId)
        }
        return created
    }

    /// Saves a recipe received with a share link as the user's own recipe.
    /// Saved as "manual", so it doesn't count as an import (free-tier limit).
    func saveSharedRecipe(from detail: RecipeDetail, newPhotos: [UIImage]) async throws -> UserRecipe {
        guard let userIdString = AuthManager.shared.currentUser?.id,
              let userId = UUID(uuidString: userIdString) else {
            throw RecipeServiceError.notAuthenticated
        }

        var copy = UserRecipe.empty(userId: userId)
        copy.applyEdits(from: detail)
        copy.sourceUrl = detail.sourceUrl
        copy.sourceName = detail.sourceName
        try await setPhotos(of: &copy, existing: detail.images, newPhotos: newPhotos)

        let created = try await recipeService.createRecipe(copy, source: "manual")
        userRecipes.insert(created, at: 0)
        return created
    }

    /// Uploads new photos and sets them after the existing image URLs
    private func setPhotos(of recipe: inout UserRecipe, existing: [String], newPhotos: [UIImage]) async throws {
        var photos = existing
        let validPhotos = newPhotos.filter { $0.size.width > 0 && $0.size.height > 0 }
        if !validPhotos.isEmpty {
            // Fresh folder: uploads are named by index, so reusing the recipe's folder
            // would overwrite its existing photos
            photos += try await recipeService.uploadRecipeImages(validPhotos, recipeId: UUID())
        }
        recipe.photos = photos.isEmpty ? nil : photos
        recipe.imageUrl = photos.first ?? recipe.imageUrl
    }

    /// Updates a recipe in place once its AI nutrition estimate arrives (avoids a full reload).
    /// If the recipe isn't loaded yet, the next load picks the value up from the database.
    func applyEstimatedNutrition(_ nutrition: NutritionInfo, toRecipeId recipeId: UUID) {
        guard let index = userRecipes.firstIndex(where: { $0.id == recipeId }) else { return }
        userRecipes[index].nutrition = nutrition
        userRecipes[index].nutritionEstimated = true
    }

    func removeBookmark(_ recipe: Recipe) async {
        do {
            try await recipeService.removeBookmark(recipeId: recipe.id)
            bookmarkedRecipes.removeAll { $0.id == recipe.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
