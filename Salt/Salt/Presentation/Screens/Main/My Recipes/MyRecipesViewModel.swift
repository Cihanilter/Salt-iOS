

import Foundation
import Combine

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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRecipe(id: UUID) async throws {
        try await recipeService.deleteRecipe(id)
        userRecipes.removeAll { $0.id == id }
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
