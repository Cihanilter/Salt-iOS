//
//  ExploreRecipesView.swift
//  Salt
//
//  Explore (Figma "Explore — Final"): title, search, category circles, the import card,
//  cuisine sections with See all, search with Recent/Popular, filter chips and results.
//

import SwiftUI

// MARK: - Search State

enum SearchState {
    case idle           // Normal explore view
    case focused        // Search bar focused, showing recent/popular/suggestions
    case searching      // Loading results
    case results        // Showing search results
}

// MARK: - Main View

struct ExploreRecipesView: View {
    @StateObject private var viewModel = ExploreViewModel()
    @State private var searchText = ""
    @State private var searchState: SearchState = .idle
    @FocusState private var isSearchFocused: Bool
    /// Filter sheet being edited (Ingredients, Total time, Cuisine, Meal type)
    @State private var activeFilter: SearchFilterKind?
    /// The user's own searches, newest first
    @AppStorage("explore.recentSearches") private var recentSearchesData = ""

    // Trigger to scroll to top and reset (from tab bar tap)
    var scrollToTopTrigger: UUID = UUID()
    /// Opens the Add Recipe tab (from the import tutorial banner)
    var switchToAddRecipe: () -> Void = {}
    /// Opens the Add Recipe tab on Create (from the import tutorial banner)
    var openCreateRecipe: () -> Void = {}
    /// Opens the Link sheet on Add Recipe ("Import a recipe" when nothing is found)
    var openLinkImport: () -> Void = {}
    @State private var contentID = UUID()

    /// Terms that return results in the library
    let popularSearches = ["Chicken", "Pasta", "Salad", "Soup"]

    /// Only cuisines with this many recipes become sections
    private static let minimumSectionSize = 6

    /// The same list as Meal type in search (DishType.all)
    let dishTypes = DishType.all

    private var recentSearches: [String] {
        recentSearchesData.isEmpty ? [] : recentSearchesData.components(separatedBy: "\n")
    }

    private var isSearching: Bool { searchState != .idle }

    var body: some View {
        VStack(spacing: 0) {
            header
                .background(SaltColor.surfaceScreen)
                .zIndex(1)

            ZStack(alignment: .top) {
                SaltColor.surfaceScreen

                switch searchState {
                case .idle:
                    if viewModel.selectedDishType == nil {
                        exploreContent
                    } else {
                        categoryResultsContent
                    }
                case .focused:
                    searchOverlayContent
                case .searching:
                    ScrollView(showsIndicators: false) {
                        resultsSkeleton
                            .padding(.top, 16)
                    }
                case .results:
                    searchResultsContent
                }
            }
        }
        .background(SaltColor.surfaceScreen)
        .onChange(of: isSearchFocused) { _, focused in
            // Searching from a category (e.g. Desserts) starts with it picked under Meal type
            if focused, searchState == .idle, let dishType = viewModel.selectedDishType,
               !viewModel.filters.isActive {
                viewModel.filters.dishTypes = [dishType]
            }
            if focused && (searchState == .idle || searchState == .results) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    searchState = .focused
                }
                if !searchText.isEmpty {
                    Task { await viewModel.fetchAutocompleteSuggestions(searchText) }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            // Autocomplete while typing
            if searchState == .focused {
                if newValue.isEmpty {
                    viewModel.autocompleteSuggestions = []
                } else {
                    Task { await viewModel.fetchAutocompleteSuggestions(newValue) }
                }
            }
        }
        .sheet(item: $activeFilter) { kind in
            SearchFilterSheet(
                kind: kind,
                filters: $viewModel.filters,
                countResults: { draft in await viewModel.countResults(query: searchText, filters: draft) },
                onApply: filtersChanged
            )
        }
        .onChange(of: scrollToTopTrigger) { _, _ in
            // Tab was tapped while already on Explore - scroll to top and reset
            resetToInitialState()
        }
    }

    // MARK: - Header

    /// Title, search and (while searching) the filter chips; 16 apart
    private var header: some View {
        VStack(alignment: .leading, spacing: SaltSpacing.header) {
            Text("Explore")
                .font(SaltFont.h1)
                .foregroundStyle(SaltColor.textPrimary)
                .padding(.horizontal, SaltSpacing.screenMargin)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 16) {
                SearchBarView(
                    text: $searchText,
                    isSearchFocused: $isSearchFocused,
                    isActive: isSearching,
                    onSearch: performSearch
                )

                if isSearching {
                    Button("Cancel", action: cancelSearch)
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textAccent)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isSearching)
            .padding(.horizontal, SaltSpacing.screenMargin)

            if isSearching {
                SearchFiltersBar(filters: viewModel.filters) { kind in
                    // Set first, so losing focus doesn't leave search
                    activeFilter = kind
                    // The search keyboard would otherwise stay up over the sheet
                    isSearchFocused = false
                }
                .transition(.opacity)
            } else {
                DishTypesRow(dishTypes: dishTypes, viewModel: viewModel)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Reset to Initial State

    private func resetToInitialState() {
        withAnimation(.easeInOut(duration: 0.3)) {
            searchText = ""
            isSearchFocused = false
            searchState = .idle
            viewModel.clearFilter()
            viewModel.clearFilters()
            viewModel.clearSearchResults()
            // Change content ID to force scroll view to reset to top
            contentID = UUID()
        }
    }

    // MARK: - Explore Content (idle state)

    private var visibleSections: [CuisineSection] {
        viewModel.cuisineSections.filter { $0.recipes.count >= Self.minimumSectionSize }
    }

    private var exploreContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Helps new users get to their first import; empty once they've imported or dismissed it.
                // Outside the sections' stack, so while hidden it adds no gap above the first section.
                ImportTutorialBanner(switchToAddRecipe: switchToAddRecipe, openCreateRecipe: openCreateRecipe)
                    .padding(.horizontal, SaltSpacing.screenMargin)

                LazyVStack(alignment: .leading, spacing: SaltSpacing.section) {
                    if visibleSections.isEmpty && viewModel.isLoading {
                        ForEach(0..<2, id: \.self) { _ in
                            SkeletonSection()
                        }
                    }

                    ForEach(visibleSections) { section in
                        RecipeSection(section: section, viewModel: viewModel)
                    }
                }
            }
            .padding(.bottom, SaltSpacing.bottomTabPadding)
        }
        .id(contentID)  // Reset scroll position when ID changes
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Search Overlay Content (focused state)

    private var searchOverlayContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: SaltSpacing.section) {
                if searchText.isEmpty {
                    if !recentSearches.isEmpty {
                        searchList(
                            title: "Recent",
                            items: recentSearches,
                            onClear: { recentSearchesData = "" },
                            onRemove: removeRecentSearch
                        )
                    }
                    searchList(title: "Popular", items: popularSearches)
                } else {
                    autocompleteSuggestionsSection
                }
            }
            .padding(.top, 16)
            .padding(.bottom, SaltSpacing.bottomTabPadding)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// "Recent" (with Clear and × per row) or "Popular": search icon rows with thin dividers
    private func searchList(
        title: LocalizedStringKey,
        items: [String],
        onClear: (() -> Void)? = nil,
        onRemove: ((String) -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(SaltFont.h3)
                    .foregroundStyle(SaltColor.textPrimary)
                Spacer()
                if let onClear {
                    Button("Clear", action: onClear)
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textAccent)
                }
            }

            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                HStack(spacing: 16) {
                    Button {
                        searchText = item
                        performSearch()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 17))
                                .foregroundStyle(SaltColor.textSecondary)
                            Text(item)
                                .font(SaltFont.bodyLarge)
                                .foregroundStyle(SaltColor.textPrimary)
                            Spacer()
                        }
                        .frame(height: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if let onRemove {
                        Button {
                            onRemove(item)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14))
                                .foregroundStyle(SaltColor.textSecondary)
                                .frame(width: 44, height: 44)
                        }
                        .padding(.trailing, -12)
                        .accessibilityLabel("Remove \(item)")
                    }
                }
                if index < items.count - 1 {
                    Rectangle().fill(SaltColor.borderSubtle).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, SaltSpacing.screenMargin)
    }

    // MARK: - Autocomplete Suggestions Section

    private var autocompleteSuggestionsSection: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.autocompleteSuggestions, id: \.self) { suggestion in
                Button {
                    searchText = suggestion
                    performSearch()
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17))
                            .foregroundStyle(SaltColor.textSecondary)
                        highlightedText(suggestion, highlight: searchText)
                            .foregroundStyle(SaltColor.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .frame(height: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Rectangle().fill(SaltColor.borderSubtle).frame(height: 1)
            }

            Button(action: performSearch) {
                HStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17))
                        .foregroundStyle(SaltColor.iconAccent)
                    Text("Search for \u{201C}\(searchText)\u{201D}")
                        .font(SaltFont.bodyLargeStrong)
                        .foregroundStyle(SaltColor.textAccent)
                        .lineLimit(1)
                    Spacer()
                }
                .frame(height: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SaltSpacing.screenMargin)
    }

    /// The typed part in SemiBold (no Bold anywhere)
    private func highlightedText(_ text: String, highlight: String) -> Text {
        guard let range = text.range(of: highlight, options: .caseInsensitive) else {
            return Text(text).font(SaltFont.bodyLarge)
        }
        return Text(text[..<range.lowerBound]).font(SaltFont.bodyLarge)
            + Text(text[range]).font(SaltFont.bodyLargeStrong)
            + Text(text[range.upperBound...]).font(SaltFont.bodyLarge)
    }

    // MARK: - Search Results Content

    private var searchResultsContent: some View {
        ScrollView(showsIndicators: false) {
            if viewModel.searchResults.isEmpty {
                noResults
                    .padding(.top, 56)
                    .padding(.horizontal, SaltSpacing.screenMargin)
            } else {
                VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
                    resultsCountLine(showsClearAll: viewModel.filters.isActive)
                    recipeGrid(viewModel.searchResults, hasMore: viewModel.searchHasMore) {
                        await viewModel.loadMoreSearchResults()
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, SaltSpacing.bottomTabPadding)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// A smaller library misses more often: turn it into an import moment
    private var noResults: some View {
        SaltEmptyState(
            systemImage: "magnifyingglass",
            title: searchText.isEmpty
                ? String(localized: "No recipes match these filters yet")
                : String(localized: "No recipes for \u{201C}\(searchText)\u{201D} yet"),
            message: String(localized: "Found one you like somewhere else? Import it from Instagram, TikTok or any website."),
            buttonTitle: String(localized: "Import a recipe"),
            action: openLinkImport
        )
    }

    /// "5 recipes" with "Clear all" whenever a filter is on
    private func resultsCountLine(showsClearAll: Bool) -> some View {
        HStack {
            Text(viewModel.totalResultsCount == 1 ? "1 recipe" : "\(viewModel.totalResultsCount) recipes")
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textSecondary)
            Spacer()
            if showsClearAll {
                Button("Clear all", action: clearFilters)
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textAccent)
            }
        }
        .frame(minHeight: 32)
        .padding(.horizontal, SaltSpacing.screenMargin)
    }

    /// 2-column grid with infinite scroll
    private func recipeGrid(_ recipes: [Recipe], hasMore: Bool, loadMore: @escaping () async -> Void) -> some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: ExploreLayout.gridColumns, spacing: 24) {
                ForEach(recipes) { recipe in
                    GridRecipeCard(recipe: recipe)
                        .onAppear {
                            if recipe.id == recipes.last?.id, hasMore, !viewModel.isLoadingMore {
                                Task { await loadMore() }
                            }
                        }
                }
            }
            .padding(.horizontal, SaltSpacing.screenMargin)

            if viewModel.isLoadingMore {
                ProgressView()
                    .padding(.vertical, 20)
            }
        }
    }

    private var resultsSkeleton: some View {
        LazyVGrid(columns: ExploreLayout.gridColumns, spacing: 24) {
            ForEach(0..<6, id: \.self) { _ in
                SkeletonRecipeCard()
            }
        }
        .padding(.horizontal, SaltSpacing.screenMargin)
    }

    // MARK: - Category Results Content (filtered by dish type)

    private var categoryResultsContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
                if viewModel.isLoading {
                    SaltSkeleton(cornerRadius: 4)
                        .frame(width: 90, height: 16)
                        .padding(.horizontal, SaltSpacing.screenMargin)
                        .padding(.vertical, 8)
                    resultsSkeleton
                } else if viewModel.searchResults.isEmpty {
                    SaltEmptyState(systemImage: "fork.knife", title: String(localized: "No recipes here yet"))
                        .padding(.top, 56)
                } else {
                    resultsCountLine(showsClearAll: false)
                    recipeGrid(viewModel.searchResults, hasMore: viewModel.categoryHasMore) {
                        await viewModel.loadMoreCategoryResults()
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, SaltSpacing.bottomTabPadding)
        }
    }

    // MARK: - Actions

    private func performSearch() {
        // Filters alone are enough to search (e.g. Italian, under 30 minutes)
        guard !searchText.isEmpty || viewModel.filters.isActive else { return }

        isSearchFocused = false
        searchState = .searching
        rememberSearch(searchText)

        Task {
            await viewModel.searchRecipes(searchText)
            searchState = .results
        }
    }

    private func cancelSearch() {
        searchText = ""
        isSearchFocused = false
        withAnimation(.easeInOut(duration: 0.2)) {
            searchState = .idle
        }
        viewModel.clearFilters()
        viewModel.clearSearchResults()
    }

    /// Searches again with the new filters, or goes back to the search suggestions
    /// when there's neither text nor a filter left
    private func filtersChanged() {
        if searchText.isEmpty && !viewModel.filters.isActive {
            viewModel.clearSearchResults()
            withAnimation(.easeInOut(duration: 0.2)) {
                searchState = .focused
            }
        } else {
            performSearch()
        }
    }

    private func clearFilters() {
        viewModel.clearFilters()
        filtersChanged()
    }

    // MARK: - Recent Searches

    private func rememberSearch(_ text: String) {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        var terms = recentSearches.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        terms.insert(term, at: 0)
        recentSearchesData = terms.prefix(5).joined(separator: "\n")
    }

    private func removeRecentSearch(_ term: String) {
        recentSearchesData = recentSearches.filter { $0 != term }.joined(separator: "\n")
    }
}

// MARK: - Layout

enum ExploreLayout {
    /// Two 168pt cards + 30pt gap on a 402pt screen (18 margins)
    static let gridColumns = [
        GridItem(.flexible(), spacing: 30, alignment: .top),
        GridItem(.flexible(), alignment: .top)
    ]
}

// MARK: - Search Bar View

struct SearchBarView: View {
    @Binding var text: String
    var isSearchFocused: FocusState<Bool>.Binding
    /// While searching the field gets the dark (focused) border
    var isActive = false
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(SaltColor.textSecondary)

            TextField("", text: $text, prompt: Text("Search recipes").foregroundStyle(SaltColor.textSecondary))
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textPrimary)
                .tint(SaltColor.actionPrimary)
                .focused(isSearchFocused)
                .submitLabel(.search)
                .onSubmit(onSearch)

            if !text.isEmpty {
                Button {
                    text = ""
                    isSearchFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(SaltColor.textDisabled)
                }
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(SaltColor.surfaceScreen, in: RoundedRectangle(cornerRadius: SaltRadius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SaltRadius.input, style: .continuous)
                .stroke(isActive ? SaltColor.textPrimary : SaltColor.borderDefault, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused.wrappedValue = true }
    }
}

// MARK: - Skeletons

/// Grid card skeleton in the real card size (surface/control)
struct SkeletonRecipeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SaltSkeleton(cornerRadius: SaltRadius.recipeImage)
                .frame(height: 140)
            SaltSkeleton(cornerRadius: 4)
                .frame(height: 16)
                .padding(.top, 4)
            SaltSkeleton(cornerRadius: 4)
                .frame(width: 60, height: 14)
        }
    }
}

/// A cuisine section's skeleton: title + three carousel cards
private struct SkeletonSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
            SaltSkeleton(cornerRadius: 4)
                .frame(width: 110, height: 22)
                .padding(.horizontal, SaltSpacing.screenMargin)
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        SaltSkeleton(cornerRadius: SaltRadius.recipeImage)
                            .frame(width: 153, height: 200)
                        SaltSkeleton(cornerRadius: 4)
                            .frame(width: 120, height: 16)
                            .padding(.top, 4)
                        SaltSkeleton(cornerRadius: 4)
                            .frame(width: 50, height: 14)
                    }
                }
            }
            .padding(.horizontal, SaltSpacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
    }
}

// MARK: - Bookmark

/// Card bookmark: dark blurred circle (always readable over a photo); saved = orange filled
/// bookmark. Saving shows the standard saved toast.
struct ExploreBookmarkButton: View {
    let recipeId: UUID
    @ObservedObject private var bookmarkManager = BookmarkManager.shared

    private var isBookmarked: Bool {
        bookmarkManager.isBookmarked(recipeId)
    }

    var body: some View {
        Button {
            Task {
                let isNowBookmarked = await bookmarkManager.toggleBookmark(for: recipeId)
                if isNowBookmarked {
                    SaltToastCenter.shared.showSaved(.explore(recipeId))
                }
            }
        } label: {
            SaltBookmarkCircle(isBookmarked: isBookmarked)
                // 44pt tap area around the 34pt circle
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isBookmarked ? "Remove from Saved" : "Save recipe")
    }
}

// MARK: - Recipe Image

/// Recipe photo with the skeleton color while loading
struct RecipeCardImage: View {
    let url: String

    var body: some View {
        CachedAsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                SaltColor.surfaceControl
            }
        }
    }
}

// MARK: - Grid Recipe Card (search results, categories, See all)

struct GridRecipeCard: View {
    let recipe: Recipe

    var body: some View {
        NavigationLink(destination: RecipeDetailView(recipe: recipe.toRecipeDetail(), recipeId: recipe.id)) {
            VStack(alignment: .leading, spacing: 4) {
                RecipeCardImage(url: recipe.displayImageUrl)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 140, maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: SaltRadius.recipeImage, style: .continuous))
                    // Keep taps inside the visible image
                    .contentShape(RoundedRectangle(cornerRadius: SaltRadius.recipeImage, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        // The 34pt circle sits 10pt from the top and right (its tap area is 44pt)
                        ExploreBookmarkButton(recipeId: recipe.id)
                            .padding(5)
                    }
                    .padding(.bottom, 4)

                Text(recipe.title)
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textPrimary)
                    .lineLimit(1)

                Text(recipe.durationText)
                    .font(SaltFont.body)
                    .foregroundStyle(SaltColor.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dish Types Row

/// Category circles: peach with gray icons; selected = orange icon + label on a deeper peach
/// circle (like the active tab). Tap again to deselect.
struct DishTypesRow: View {
    let dishTypes: [DishType]
    @ObservedObject var viewModel: ExploreViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(dishTypes) { dishType in
                    DishTypeItem(dishType: dishType, viewModel: viewModel)
                }
            }
            .padding(.horizontal, SaltSpacing.screenMargin)
            .padding(.top, 4)
        }
    }
}

struct DishTypeItem: View {
    let dishType: DishType
    @ObservedObject var viewModel: ExploreViewModel

    var isSelected: Bool {
        viewModel.selectedDishType == dishType.name
    }

    var body: some View {
        Button {
            Task {
                await viewModel.toggleDishTypeFilter(dishType.name, displayName: dishType.displayName)
            }
        } label: {
            VStack(spacing: 8) {
                Image(dishType.icon)
                    .renderingMode(.template)
                    .foregroundStyle(isSelected ? SaltColor.iconAccent : SaltColor.textSecondary)
                    .frame(width: 64, height: 64)
                    .background(isSelected ? SaltColor.surfaceWarmStrong : SaltColor.surfaceWarm, in: Circle())

                Text(dishType.displayName)
                    .font(isSelected ? SaltFont.bodyStrong : SaltFont.body)
                    .foregroundStyle(isSelected ? SaltColor.textAccent : SaltColor.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Recipe Section (horizontal scroll with auto-loading)

struct RecipeSection: View {
    let section: CuisineSection
    @ObservedObject var viewModel: ExploreViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.cuisine)
                    .font(SaltFont.h2)
                    .foregroundStyle(SaltColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink {
                    ExploreSeeAllView(sectionName: section.cuisine, viewModel: viewModel)
                } label: {
                    Text("See all")
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textAccent)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("See all \(section.cuisine)")
            }
            .padding(.horizontal, SaltSpacing.screenMargin)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(section.recipes) { recipe in
                        RecipeCard(recipe: recipe)
                            .onAppear {
                                // Load more when the last card comes into view
                                if recipe.id == section.recipes.last?.id, section.hasMore, !section.isLoadingMore {
                                    Task { await viewModel.loadMoreRecipes(for: section.cuisine) }
                                }
                            }
                    }

                    if section.isLoadingMore {
                        ProgressView()
                            .frame(width: 60, height: 200)
                    }
                }
                .padding(.horizontal, SaltSpacing.screenMargin)
            }
            .padding(.top, -6)  // The cards' bookmarks sit in the section's rhythm
        }
    }
}

// MARK: - Recipe Card (horizontal scroll)

/// Explore carousel card: 153×200 photo (radius 25), name, time
struct RecipeCard: View {
    let recipe: Recipe

    var body: some View {
        NavigationLink(destination: RecipeDetailView(recipe: recipe.toRecipeDetail(), recipeId: recipe.id)) {
            VStack(alignment: .leading, spacing: 4) {
                RecipeCardImage(url: recipe.displayImageUrl)
                    .frame(width: 153, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: SaltRadius.recipeImage, style: .continuous))
                    // Clipping only hides the overflow of a filled image; without this its hidden
                    // part still takes taps meant for the card (and bookmark) next to it
                    .contentShape(RoundedRectangle(cornerRadius: SaltRadius.recipeImage, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        // The 34pt circle sits 10pt from the top and right (its tap area is 44pt)
                        ExploreBookmarkButton(recipeId: recipe.id)
                            .padding(5)
                    }
                    .padding(.bottom, 4)

                Text(recipe.title)
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textPrimary)
                    .lineLimit(1)

                Text(recipe.durationText)
                    .font(SaltFont.body)
                    .foregroundStyle(SaltColor.textSecondary)
            }
            .frame(width: 153, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - See All

/// "See all" next to a cuisine: back + Playfair title, count, the same 2-column grid
struct ExploreSeeAllView: View {
    let sectionName: String
    @ObservedObject var viewModel: ExploreViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var recipes: [Recipe] = []
    @State private var count: Int?
    @State private var page = 0
    @State private var hasMore = true
    @State private var isLoading = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
                Text(count.map { $0 == 1 ? "1 recipe" : "\($0) recipes" } ?? " ")
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textSecondary)
                    .padding(.horizontal, SaltSpacing.screenMargin)

                LazyVGrid(columns: ExploreLayout.gridColumns, spacing: 24) {
                    ForEach(recipes) { recipe in
                        GridRecipeCard(recipe: recipe)
                            .onAppear {
                                if recipe.id == recipes.last?.id { Task { await loadNextPage() } }
                            }
                    }
                    if recipes.isEmpty && isLoading {
                        ForEach(0..<6, id: \.self) { _ in SkeletonRecipeCard() }
                    }
                }
                .padding(.horizontal, SaltSpacing.screenMargin)

                if isLoading && !recipes.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, SaltSpacing.bottomTabPadding)
        }
        .background(SaltColor.surfaceScreen)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(SaltColor.iconDefault)
                        .frame(width: 44, height: 44)
                }
                .padding(.leading, -12)
                .accessibilityLabel("Back")
                Text(sectionName)
                    .font(SaltFont.h1)
                    .foregroundStyle(SaltColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, SaltSpacing.screenMargin)
            .padding(.vertical, 8)
            .background(SaltColor.surfaceScreen)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task {
            guard recipes.isEmpty else { return }
            async let total = viewModel.seeAllCount(for: sectionName)
            await loadNextPage()
            count = await total
        }
    }

    private func loadNextPage() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let newRecipes = try? await viewModel.seeAllPage(for: sectionName, page: page) else { return }
        let existing = Set(recipes.map(\.id))
        recipes.append(contentsOf: newRecipes.filter { !existing.contains($0.id) })
        page += 1
        hasMore = newRecipes.count >= 20
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ExploreRecipesView()
    }
}
