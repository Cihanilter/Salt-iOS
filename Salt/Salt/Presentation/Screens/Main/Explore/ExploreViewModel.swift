//
//  ExploreViewModel.swift
//  Salt
//

import Foundation
import Supabase
import Combine

// MARK: - Cuisine Section Model

struct CuisineSection: Identifiable {
    let id = UUID()
    let cuisine: String
    var recipes: [Recipe]
    var hasMore: Bool = true  // Whether there are more recipes to load
    var currentPage: Int = 0  // Current page (0 = first 10 recipes)
    var isLoadingMore: Bool = false  // Whether we are currently loading more recipes
    var isLoaded: Bool = false  // Whether initial recipes for this section are loaded
    var totalCount: Int = 0  // Total number of recipes in DB for this cuisine
}

@MainActor
class ExploreViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var cuisineSections: [CuisineSection] = []
    @Published var searchResults: [Recipe] = []
    @Published var autocompleteSuggestions: [String] = []  // Autocomplete suggestions
    @Published var currentFilterTitle: String? = nil  // Title for filtered results
    @Published var selectedDishType: String? = nil  // Currently selected dish type

    @Published var isLoading = false
    @Published var isLoadingMore = false  // For pagination
    @Published var searchHasMore = false  // Whether there are more search results
    @Published var categoryHasMore = false  // Whether there are more category results
    @Published var totalResultsCount: Int = 0  // Total count for search/category results
    @Published var errorMessage: String?

    private var autocompleteTask: Task<Void, Never>?  // For debouncing
    private var currentSearchQuery: String = ""  // Current search query for pagination
    private var searchOffset: Int = 0  // Current offset for pagination
    private var categoryOffset: Int = 0  // Current offset for category pagination
    private let searchPageSize: Int = 20  // Results per page

    // MARK: - Private Properties

    private let supabase = SupabaseClientManager.shared.client
    private var cancellables = Set<AnyCancellable>()

    // Section item - can be either a cuisine or a category
    private struct SectionItem {
        let name: String           // Database value (e.g., "Seafood", "Mexican")
        let displayName: String    // UI display name
        let isCuisine: Bool        // true = query 'cuisines' field, false = query 'categories' field
    }

    // Priority sections requested by client (in order)
    // Seafood, Salad, Pasta, Desserts are categories (query 'categories' field)
    // Mexican, Chinese, Thai, Italian, French are cuisines (query 'cuisines' field)
    private let prioritySections: [SectionItem] = [
        SectionItem(name: "Seafood", displayName: "Seafood", isCuisine: false),
        SectionItem(name: "Mexican", displayName: "Mexican", isCuisine: true),
        SectionItem(name: "Chinese", displayName: "Chinese", isCuisine: true),
        SectionItem(name: "Salad", displayName: "Salad", isCuisine: false),
        SectionItem(name: "Pasta", displayName: "Pasta", isCuisine: false),
        SectionItem(name: "Thai", displayName: "Thai", isCuisine: true),
        SectionItem(name: "Italian", displayName: "Italian", isCuisine: true),
        SectionItem(name: "French", displayName: "French", isCuisine: true),
        SectionItem(name: "Desserts", displayName: "Dessert", isCuisine: false)
    ]

    // Remaining cuisines (ordered by popularity, excluding those in prioritySections)
    private let remainingCuisines = [
        "American",         // 32,837
        "European",         // 2,407
        "Southern",         // 1,888
        "Latin American",   // 1,856
        "Asian",            // 1,836
        "Indian",           // 1,802
        "Jewish",           // 1,761
        "Greek",            // 1,635
        "Middle Eastern",   // 938
        "German",           // 890
        "Japanese",         // 838
        "Cajun",            // 718
        "Nordic",           // 513
        "Spanish",          // 500
        "Eastern European", // 481
        "Caribbean",        // 477
        "British",          // 442
        "Irish",            // 411
        "African",          // 270
        "Korean",           // 196
        "Vietnamese",       // 183
        "South American",   // 116
        "Ukrainian"         // 35
    ]

    // Combined list of all sections (priority + remaining cuisines)
    private var allSections: [SectionItem] {
        var sections = prioritySections
        for cuisine in remainingCuisines {
            sections.append(SectionItem(name: cuisine, displayName: cuisine, isCuisine: true))
        }
        return sections
    }

    // Reference to curated recipes manager for fast local loading
    private let curatedManager = CuratedRecipesManager.shared

    // MARK: - Initialization

    init() {
        Task {
            await loadInitialData()
        }
    }

    // MARK: - Public Methods

    /// Load initial data: instant from local bundle + fetch from server in parallel
    func loadInitialData() async {
        isLoading = true
        errorMessage = nil

        let sectionsToLoad = allSections
        var sections: [CuisineSection] = []

        // STEP 1: Load from local curated recipes bundle - INSTANT!
        for section in sectionsToLoad {
            let recipes = curatedManager.recipes(forSection: section.name, isCuisine: section.isCuisine, limit: 6)

            if !recipes.isEmpty {
                sections.append(CuisineSection(
                    cuisine: section.displayName,
                    recipes: recipes,
                    hasMore: true,
                    currentPage: 0,
                    isLoadingMore: false,
                    isLoaded: true,
                    totalCount: 0
                ))
            }
        }

        // Sort sections to maintain order
        let sectionOrder = sectionsToLoad.map { $0.displayName }
        sections.sort {
            (sectionOrder.firstIndex(of: $0.cuisine) ?? 999) < (sectionOrder.firstIndex(of: $1.cuisine) ?? 999)
        }

        // Update UI immediately with local data
        if !sections.isEmpty {
            self.cuisineSections = sections
            print("✅ Loaded \(sections.count) sections from local bundle (instant!)")
        }

        isLoading = false

        // STEP 2: Fetch additional recipes from server in background (4 per section)
        await fetchAdditionalRecipesFromServer(sectionsToLoad: sectionsToLoad)
    }

    /// Fetch additional recipes from server and merge with existing (avoiding duplicates)
    private func fetchAdditionalRecipesFromServer(sectionsToLoad: [SectionItem]) async {
        await withTaskGroup(of: (String, [Recipe])?.self) { group in
            for section in sectionsToLoad {
                group.addTask {
                    do {
                        let recipes = try await self.fetchRecipesForSection(section, page: 0, limit: 4)
                        return (section.displayName, recipes)
                    } catch {
                        print("⚠️ Failed to fetch \(section.displayName) from server: \(error)")
                        return nil
                    }
                }
            }

            for await result in group {
                guard let (displayName, newRecipes) = result, !newRecipes.isEmpty else { continue }

                // Find section and merge recipes (avoid duplicates)
                if let index = cuisineSections.firstIndex(where: { $0.cuisine == displayName }) {
                    let existingIds = Set(cuisineSections[index].recipes.map { $0.id })
                    let uniqueNewRecipes = newRecipes.filter { !existingIds.contains($0.id) }

                    if !uniqueNewRecipes.isEmpty {
                        cuisineSections[index].recipes.append(contentsOf: uniqueNewRecipes)
                        print("✅ Added \(uniqueNewRecipes.count) server recipes to '\(displayName)'")
                    }
                } else {
                    // Section doesn't exist yet (no curated recipes for it) - create new
                    cuisineSections.append(CuisineSection(
                        cuisine: displayName,
                        recipes: newRecipes,
                        hasMore: newRecipes.count >= 4,
                        currentPage: 0,
                        isLoadingMore: false,
                        isLoaded: true,
                        totalCount: 0
                    ))
                    print("✅ Created new section '\(displayName)' with \(newRecipes.count) server recipes")
                }
            }
        }

        // Re-sort sections after adding new ones
        let sectionOrder = allSections.map { $0.displayName }
        cuisineSections.sort {
            (sectionOrder.firstIndex(of: $0.cuisine) ?? 999) < (sectionOrder.firstIndex(of: $1.cuisine) ?? 999)
        }
    }

    /// Fetch all recipes in one query
    private func fetchAllRecipes(limit: Int = 100) async throws -> [Recipe] {
        let response = try await supabase
            .from("recipes")
            .select()
            .order("id", ascending: true)
            .limit(limit)
            .execute()

        let recipes = try JSONDecoder().decode([Recipe].self, from: response.data)
        print("✅ Fetched \(recipes.count) recipes in ONE query")
        return recipes
    }

    /// Search recipes by text query (with pagination support)
    /// First shows local curated results instantly, then fetches from server
    func searchRecipes(_ query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            currentFilterTitle = nil
            errorMessage = nil
            searchHasMore = false
            totalResultsCount = 0
            return
        }

        // Reset pagination for new search
        currentSearchQuery = query
        searchOffset = 0
        isLoading = true
        errorMessage = nil
        totalResultsCount = 0

        // STEP 1: Search in local curated recipes FIRST (instant!)
        let localResults = curatedManager.search(query, limit: 10)
        if !localResults.isEmpty {
            searchResults = localResults
            isLoading = false
            print("✅ Instant search: \(localResults.count) curated results for '\(query)'")
        }

        // STEP 2: Fetch from server in parallel
        do {
            async let countTask = fetchSearchCount(query)

            // Prefix search first (faster)
            let response = try await supabase
                .from("recipes")
                .select()
                .ilike("title", pattern: "\(query)%")
                .order("is_curated", ascending: false)
                .order("total_rating", ascending: false)
                .order("rating_count", ascending: false)
                .order("rating", ascending: false)
                .order("id", ascending: true)
                .range(from: 0, to: searchPageSize - 1)
                .execute()

            var serverRecipes = try JSONDecoder().decode([Recipe].self, from: response.data)

            // If not enough results, also try contains search
            if serverRecipes.count < 10 {
                let containsResponse = try await supabase
                    .from("recipes")
                    .select()
                    .ilike("title", pattern: "%\(query)%")
                    .order("is_curated", ascending: false)
                    .order("total_rating", ascending: false)
                    .order("rating_count", ascending: false)
                    .order("rating", ascending: false)
                    .order("id", ascending: true)
                    .range(from: 0, to: searchPageSize - 1)
                    .execute()

                let containsRecipes = try JSONDecoder().decode([Recipe].self, from: containsResponse.data)

                // Deduplicate by ID and title
                var existingIds = Set(serverRecipes.map { $0.id })
                var existingTitles = Set(serverRecipes.map { $0.title.lowercased() })
                for recipe in containsRecipes {
                    let titleLower = recipe.title.lowercased()
                    if !existingIds.contains(recipe.id) && !existingTitles.contains(titleLower) {
                        existingIds.insert(recipe.id)
                        existingTitles.insert(titleLower)
                        serverRecipes.append(recipe)
                    }
                }
            }

            // Merge local + server results, local (curated) first
            // Deduplicate by BOTH id AND title to avoid showing same recipe twice
            var allResults = localResults
            var seenIds = Set(localResults.map { $0.id })
            var seenTitles = Set(localResults.map { $0.title.lowercased() })

            for recipe in serverRecipes {
                let titleLower = recipe.title.lowercased()
                // Skip if we already have this recipe (by ID or by title)
                if seenIds.contains(recipe.id) || seenTitles.contains(titleLower) {
                    continue
                }
                seenIds.insert(recipe.id)
                seenTitles.insert(titleLower)
                allResults.append(recipe)
            }

            // Sort: curated first, then by rating
            allResults.sort { r1, r2 in
                let c1 = r1.isCurated ?? false
                let c2 = r2.isCurated ?? false
                if c1 != c2 { return c1 && !c2 }

                let tr1 = r1.totalRating ?? 0
                let tr2 = r2.totalRating ?? 0
                if tr1 != tr2 { return tr1 > tr2 }

                return (r1.ratingCount ?? 0) > (r2.ratingCount ?? 0)
            }

            let count = await countTask

            searchResults = Array(allResults.prefix(searchPageSize))
            searchOffset = searchResults.count
            searchHasMore = count > searchResults.count
            totalResultsCount = count
            currentFilterTitle = nil
            isLoading = false

            print("✅ Search: \(searchResults.count) total results for '\(query)' (local: \(localResults.count), server: \(serverRecipes.count))")
        } catch {
            print("⚠️ Search timeout, trying simpler query...")
            await searchRecipesSimple(query)
        }
    }

    /// Simplified search for when main search times out
    /// Still applies curated-first sorting
    private func searchRecipesSimple(_ query: String) async {
        do {
            // Only prefix search, smaller limit, but still with proper sorting
            let response = try await supabase
                .from("recipes")
                .select()  // Need all fields for proper sorting
                .ilike("title", pattern: "\(query)%")
                .order("is_curated", ascending: false)
                .order("total_rating", ascending: false)
                .order("rating_count", ascending: false)
                .order("rating", ascending: false)
                .order("id", ascending: true)
                .limit(20)
                .execute()

            let recipes = try JSONDecoder().decode([Recipe].self, from: response.data)
            searchResults = recipes
            searchOffset = recipes.count
            searchHasMore = recipes.count >= 20
            isLoading = false

            print("✅ Simple search: found \(recipes.count) recipes")
        } catch {
            errorMessage = "Search failed. Please try again."
            searchResults = []
            searchHasMore = false
            isLoading = false
            print("❌ Simple search also failed: \(error)")
        }
    }

    /// Load more search results (pagination)
    /// Sorting: curated first, then by total_rating (rating * rating_count), with tie-breakers
    func loadMoreSearchResults() async {
        guard !currentSearchQuery.isEmpty, searchHasMore, !isLoadingMore else { return }

        isLoadingMore = true

        do {
            let from = searchOffset
            let to = searchOffset + searchPageSize - 1

            let response = try await supabase
                .from("recipes")
                .select()
                .ilike("title", pattern: "%\(currentSearchQuery)%")
                .order("is_curated", ascending: false)
                .order("total_rating", ascending: false)
                .order("rating_count", ascending: false)
                .order("rating", ascending: false)
                .order("id", ascending: true)
                .range(from: from, to: to)
                .execute()

            let newRecipes = try JSONDecoder().decode([Recipe].self, from: response.data)

            // Deduplicate by ID and title before adding
            let existingIds = Set(searchResults.map { $0.id })
            let existingTitles = Set(searchResults.map { $0.title.lowercased() })
            let uniqueNewRecipes = newRecipes.filter { recipe in
                !existingIds.contains(recipe.id) && !existingTitles.contains(recipe.title.lowercased())
            }

            searchResults.append(contentsOf: uniqueNewRecipes)
            searchOffset += newRecipes.count  // Use original count for offset
            // Has more if we haven't loaded all results yet
            searchHasMore = searchResults.count < totalResultsCount

            isLoadingMore = false
            print("✅ Loaded \(newRecipes.count) more recipes. Total: \(searchResults.count)/\(totalResultsCount)")
        } catch {
            isLoadingMore = false
            print("❌ Load more error: \(error)")
        }
    }

    /// Clear search results
    func clearSearchResults() {
        searchResults = []
        autocompleteSuggestions = []
        currentFilterTitle = nil
        selectedDishType = nil
        errorMessage = nil
        currentSearchQuery = ""
        searchOffset = 0
        searchHasMore = false
        totalResultsCount = 0
    }

    /// Fetch autocomplete suggestions based on query
    func fetchAutocompleteSuggestions(_ query: String) async {
        // Cancel previous task
        autocompleteTask?.cancel()

        // Debounce - wait 300ms before fetching
        autocompleteTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)

            guard !Task.isCancelled else { return }
            guard !query.isEmpty else {
                await MainActor.run {
                    self.autocompleteSuggestions = []
                }
                return
            }

            do {
                struct TitleResult: Decodable {
                    let title: String
                }

                // Use Set to ensure uniqueness
                var uniqueTitles = Set<String>()
                var orderedSuggestions: [String] = []

                // Fetch titles that START with query (more relevant)
                let startsWithResponse = try await supabase
                    .from("recipes")
                    .select("title")
                    .ilike("title", pattern: "\(query)%")
                    .limit(15)  // Fetch more to account for duplicates
                    .execute()

                let startsWithResults = try JSONDecoder().decode([TitleResult].self, from: startsWithResponse.data)

                for result in startsWithResults {
                    if !uniqueTitles.contains(result.title) {
                        uniqueTitles.insert(result.title)
                        orderedSuggestions.append(result.title)
                    }
                    if orderedSuggestions.count >= 8 { break }
                }

                // If we need more, search for CONTAINS
                if orderedSuggestions.count < 6 {
                    let containsResponse = try await supabase
                        .from("recipes")
                        .select("title")
                        .ilike("title", pattern: "%\(query)%")
                        .limit(15)
                        .execute()

                    let containsResults = try JSONDecoder().decode([TitleResult].self, from: containsResponse.data)

                    for result in containsResults {
                        if !uniqueTitles.contains(result.title) {
                            uniqueTitles.insert(result.title)
                            orderedSuggestions.append(result.title)
                        }
                        if orderedSuggestions.count >= 8 { break }
                    }
                }

                await MainActor.run {
                    self.autocompleteSuggestions = Array(orderedSuggestions.prefix(8))
                }

                print("✅ Autocomplete: \(orderedSuggestions.count) unique suggestions for '\(query)'")
            } catch {
                print("❌ Autocomplete error: \(error)")
            }
        }
    }

    /// Fetch recipes by specific cuisine with pagination
    /// Sorting: curated first, then by total_rating (rating * rating_count), with tie-breakers
    func fetchRecipesByCuisine(_ cuisine: String, page: Int = 0, limit: Int = 10) async throws -> [Recipe] {
        // PostgreSQL array contains syntax: cuisines @> '{cuisine}'
        let from = page * limit
        let to = from + limit - 1

        let response = try await supabase
            .from("recipes")
            .select()
            .filter("cuisines", operator: "cs", value: "{\"\(cuisine)\"}")
            .order("is_curated", ascending: false)
            .order("total_rating", ascending: false)
            .order("rating_count", ascending: false)
            .order("rating", ascending: false)
            .order("id", ascending: true)
            .range(from: from, to: to)
            .execute()

        let recipes = try JSONDecoder().decode([Recipe].self, from: response.data)
        print("✅ Loaded \(recipes.count) recipes for cuisine: \(cuisine) (page \(page))")
        return recipes
    }

    /// Fetch recipes for a section (either cuisine or category based on isCuisine flag)
    /// Sorting: curated first, then by total_rating (rating * rating_count)
    /// Falls back to simpler sorting if curated query times out
    private func fetchRecipesForSection(_ section: SectionItem, page: Int = 0, limit: Int = 6) async throws -> [Recipe] {
        let from = page * limit
        let to = from + limit - 1

        // Use different field based on whether it's a cuisine or category
        let field = section.isCuisine ? "cuisines" : "categories"

        do {
            // Try with curated sorting first
            let response = try await supabase
                .from("recipes")
                .select()
                .filter(field, operator: "cs", value: "{\"\(section.name)\"}")
                .order("is_curated", ascending: false)
                .order("total_rating", ascending: false)
                .order("id", ascending: true)
                .range(from: from, to: to)
                .execute()

            let recipes = try JSONDecoder().decode([Recipe].self, from: response.data)
            print("✅ Loaded \(recipes.count) recipes for \(section.isCuisine ? "cuisine" : "category"): \(section.name) (page \(page))")
            return recipes
        } catch {
            // Fallback: simpler query without curated sorting (for large categories)
            print("⚠️ Curated query timeout for \(section.name), trying fallback...")

            let response = try await supabase
                .from("recipes")
                .select()
                .filter(field, operator: "cs", value: "{\"\(section.name)\"}")
                .order("rating", ascending: false)
                .range(from: from, to: to)
                .execute()

            let recipes = try JSONDecoder().decode([Recipe].self, from: response.data)
            print("✅ Loaded \(recipes.count) recipes for \(section.name) (fallback, page \(page))")
            return recipes
        }
    }

    /// Fetch recipes by dish type (category) - server-side filtering with pagination
    /// Sorting: curated first, then by total_rating (rating * rating_count), with tie-breakers
    func fetchRecipesByDishType(_ dishType: String, from: Int = 0, limit: Int = 30) async throws -> [Recipe] {
        print("🔍 Searching for category: '\(dishType)' (offset: \(from))")

        // Use PostgreSQL array contains operator for server-side filtering
        // categories @> '{"dessert"}' - checks if categories array contains the value
        // Sorting: curated first, then by total_rating with tie-breakers
        let response = try await supabase
            .from("recipes")
            .select()
            .filter("categories", operator: "cs", value: "{\"\(dishType)\"}")
            .order("is_curated", ascending: false)
            .order("total_rating", ascending: false)
            .order("rating_count", ascending: false)
            .order("rating", ascending: false)
            .order("id", ascending: true)
            .range(from: from, to: from + limit - 1)
            .execute()

        let recipes = try JSONDecoder().decode([Recipe].self, from: response.data)
        print("✅ Loaded \(recipes.count) recipes for category: '\(dishType)'")

        return recipes
    }

    /// Get total count for category (fast, no data transfer)
    private func fetchCategoryCount(_ dishType: String) async -> Int {
        do {
            let response = try await supabase
                .from("recipes")
                .select("id", head: true, count: .exact)
                .filter("categories", operator: "cs", value: "{\"\(dishType)\"}")
                .execute()

            return response.count ?? 0
        } catch {
            print("⚠️ Failed to get category count: \(error)")
            return 0
        }
    }

    /// Get total count for search query (fast, no data transfer)
    private func fetchSearchCount(_ query: String) async -> Int {
        do {
            let response = try await supabase
                .from("recipes")
                .select("id", head: true, count: .exact)
                .ilike("title", pattern: "%\(query)%")
                .execute()

            return response.count ?? 0
        } catch {
            print("⚠️ Failed to get search count: \(error)")
            return 0
        }
    }

    /// Fetch top-rated recipes
    /// Sorting: curated first, then by total_rating (rating * rating_count), with tie-breakers
    func fetchTopRatedRecipes(limit: Int = 10) async throws -> [Recipe] {
        let response = try await supabase
            .from("recipes")
            .select()
            .order("is_curated", ascending: false)
            .order("total_rating", ascending: false)
            .order("rating_count", ascending: false)
            .order("rating", ascending: false)
            .order("id", ascending: true)
            .limit(limit)
            .execute()

        let recipes = try JSONDecoder().decode([Recipe].self, from: response.data)
        return recipes
    }

    /// Search recipes by title containing keyword
    /// Sorting: curated first, then by total_rating (rating * rating_count), with tie-breakers
    func fetchRecipesByKeyword(_ keyword: String, limit: Int = 10) async throws -> [Recipe] {
        let response = try await supabase
            .from("recipes")
            .select()
            .ilike("title", pattern: "%\(keyword)%")
            .order("is_curated", ascending: false)
            .order("total_rating", ascending: false)
            .order("rating_count", ascending: false)
            .order("rating", ascending: false)
            .order("id", ascending: true)
            .limit(limit)
            .execute()

        let recipes = try JSONDecoder().decode([Recipe].self, from: response.data)
        return recipes
    }

    /// Fetch recipes by maximum cooking time
    /// Sorting: curated first, then by time (ascending), then by total_rating with tie-breakers
    func fetchRecipesByTime(maxMinutes: Int, limit: Int = 10) async throws -> [Recipe] {
        let response = try await supabase
            .from("recipes")
            .select()
            .lte("total_time_minutes", value: maxMinutes)
            .order("is_curated", ascending: false)
            .order("total_time_minutes", ascending: true)
            .order("total_rating", ascending: false)
            .order("id", ascending: true)
            .limit(limit)
            .execute()

        let recipes = try JSONDecoder().decode([Recipe].self, from: response.data)
        return recipes
    }

    /// Load recipes for a specific category
    /// Note: categoryName should match exactly the value in database 'categories' array
    func loadRecipesForCategory(_ categoryName: String) async {
        isLoading = true
        errorMessage = nil

        do {
            // Use fetchRecipesByDishType which queries the 'categories' array field
            let recipes = try await fetchRecipesByDishType(categoryName, limit: 20)
            searchResults = recipes
            isLoading = false
        } catch {
            errorMessage = "Failed to load \(categoryName): \(error.localizedDescription)"
            isLoading = false
            print("❌ Error loading category \(categoryName): \(error)")
        }
    }

    /// Toggle dish type filter (select or deselect)
    func toggleDishTypeFilter(_ dishType: String, displayName: String) async {
        // If same dish type is tapped again, clear the filter
        if selectedDishType == dishType {
            clearFilter()
            return
        }

        // Otherwise, apply the filter
        selectedDishType = dishType
        await loadRecipesByDishType(dishType, displayName: displayName)
    }

    /// Clear all filters and return to cuisine sections
    func clearFilter() {
        searchResults = []
        currentFilterTitle = nil
        selectedDishType = nil
        categoryHasMore = false
        categoryOffset = 0
        totalResultsCount = 0
        errorMessage = nil
    }

    /// Load recipes by dish type (internal)
    private func loadRecipesByDishType(_ dishType: String, displayName: String) async {
        isLoading = true
        errorMessage = nil
        categoryOffset = 0  // Reset pagination
        totalResultsCount = 0

        do {
            // Fetch data and count in parallel
            async let recipesTask = fetchRecipesByDishType(dishType, from: 0, limit: searchPageSize)
            async let countTask = fetchCategoryCount(dishType)

            let recipes = try await recipesTask
            let count = await countTask

            searchResults = recipes
            currentFilterTitle = displayName
            categoryOffset = recipes.count
            categoryHasMore = recipes.count >= searchPageSize
            totalResultsCount = count

            isLoading = false
            print("✅ Category '\(dishType)': \(recipes.count) loaded, \(count) total")

            // Debug: Print first 5 results with curated status
            print("📋 Top 5 category results:")
            for (index, recipe) in recipes.prefix(5).enumerated() {
                let curated = recipe.isCurated ?? false
                let totalRating = recipe.totalRating ?? 0
                print("   \(index + 1). [\(curated ? "⭐ CURATED" : "  regular")] \(recipe.title) (rating: \(totalRating))")
            }
        } catch {
            errorMessage = "Failed to load \(dishType): \(error.localizedDescription)"
            searchResults = []
            currentFilterTitle = nil
            categoryHasMore = false
            totalResultsCount = 0
            isLoading = false
            print("❌ Error loading dish type \(dishType): \(error)")
        }
    }

    /// Load more category results (pagination)
    func loadMoreCategoryResults() async {
        guard let dishType = selectedDishType, categoryHasMore, !isLoadingMore else { return }

        isLoadingMore = true

        do {
            let newRecipes = try await fetchRecipesByDishType(dishType, from: categoryOffset, limit: searchPageSize)

            searchResults.append(contentsOf: newRecipes)
            categoryOffset += newRecipes.count
            categoryHasMore = newRecipes.count >= searchPageSize

            isLoadingMore = false
            print("✅ Loaded \(newRecipes.count) more category recipes. Total: \(searchResults.count)")
        } catch {
            isLoadingMore = false
            print("❌ Load more category error: \(error)")
        }
    }

    /// Load initial 10 recipes for a specific section (lazy loading)
    func loadInitialRecipes(for sectionName: String) async {
        // Find the section index
        guard let index = cuisineSections.firstIndex(where: { $0.cuisine == sectionName }) else {
            print("⚠️ Section not found: \(sectionName)")
            return
        }

        // Skip if already loaded
        guard !cuisineSections[index].isLoaded else {
            print("ℹ️ Section '\(sectionName)' already loaded")
            return
        }

        // Find the corresponding SectionItem to know if it's cuisine or category
        guard let sectionItem = allSections.first(where: { $0.displayName == sectionName }) else {
            print("⚠️ SectionItem not found for: \(sectionName)")
            return
        }

        print("🔄 Loading initial recipes for: \(sectionName)")

        do {
            let recipes = try await fetchRecipesForSection(sectionItem, page: 0, limit: 6)

            cuisineSections[index].recipes = recipes
            cuisineSections[index].isLoaded = true
            cuisineSections[index].currentPage = 0
            cuisineSections[index].hasMore = recipes.count >= 6

            print("✅ Loaded \(recipes.count) recipes for '\(sectionName)'")
        } catch {
            print("❌ Error loading recipes for \(sectionName): \(error)")
        }
    }

    /// Refresh all data
    func refresh() async {
        searchResults = []
        currentFilterTitle = nil
        selectedDishType = nil
        errorMessage = nil
        await loadInitialData()
    }

    /// Load more recipes for a specific section (pagination)
    func loadMoreRecipes(for sectionName: String) async {
        // Find the section index
        guard let index = cuisineSections.firstIndex(where: { $0.cuisine == sectionName }) else {
            print("⚠️ Section not found: \(sectionName)")
            return
        }

        // Check if already loading or no more recipes
        guard !cuisineSections[index].isLoadingMore && cuisineSections[index].hasMore else {
            print("⚠️ Already loading or no more recipes for: \(sectionName)")
            return
        }

        // Find the corresponding SectionItem to know if it's cuisine or category
        guard let sectionItem = allSections.first(where: { $0.displayName == sectionName }) else {
            print("⚠️ SectionItem not found for: \(sectionName)")
            return
        }

        // Set loading state
        cuisineSections[index].isLoadingMore = true

        do {
            let nextPage = cuisineSections[index].currentPage + 1
            let newRecipes = try await fetchRecipesForSection(sectionItem, page: nextPage, limit: 6)

            // If we got fewer than 6 recipes, there are no more
            if newRecipes.count < 6 {
                cuisineSections[index].hasMore = false
            }

            // Append new recipes
            cuisineSections[index].recipes.append(contentsOf: newRecipes)
            cuisineSections[index].currentPage = nextPage
            cuisineSections[index].isLoadingMore = false

            print("✅ Loaded \(newRecipes.count) more recipes for \(sectionName). Total: \(cuisineSections[index].recipes.count)")
        } catch {
            cuisineSections[index].isLoadingMore = false
            print("❌ Error loading more recipes for \(sectionName): \(error)")
        }
    }
}
