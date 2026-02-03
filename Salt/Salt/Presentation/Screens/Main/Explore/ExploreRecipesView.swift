
import SwiftUI

// MARK: - Search State

enum SearchState {
    case idle           // Normal explore view
    case focused        // Search bar focused, showing popular/suggestions
    case searching      // Loading results
    case results        // Showing search results
}

// MARK: - Models

struct DishType: Identifiable {
    let id = UUID()
    let name: String
    let displayName: String
    let icon: String
}

// MARK: - Main View

struct ExploreRecipesView: View {
    @StateObject private var viewModel = ExploreViewModel()
    @State private var searchText = ""
    @State private var searchState: SearchState = .idle
    @FocusState private var isSearchFocused: Bool

    // Trigger to scroll to top and reset (from tab bar tap)
    var scrollToTopTrigger: UUID = UUID()
    @State private var contentID = UUID()

    // Popular searches (fixed list)
    let popularSearches = ["Chicken", "Pasta", "Salad", "Dessert", "Soup", "Breakfast", "Pizza", "Cookies"]

    // Categories from database (matches 'categories' array field)
    let dishTypes = [
        DishType(name: "Desserts", displayName: "Desserts", icon: "dessertIcon"),
        DishType(name: "Side Dish", displayName: "Side Dish", icon: "pastaIcon"),
        DishType(name: "Main Dishes", displayName: "Main Dish", icon: "mainDishIcon"),
        DishType(name: "Appetizers and Snacks", displayName: "Snacks", icon: "tapasIcon"),
        DishType(name: "Soups, Stews and Chili Recipes", displayName: "Soups", icon: "soupIcon"),
        DishType(name: "Salad", displayName: "Salad", icon: "vegetarianIcon"),
        DishType(name: "Breakfast and Brunch", displayName: "Breakfast", icon: "bakeryIcon"),
        DishType(name: "Bread", displayName: "Bread", icon: "bakeryIcon"),
        DishType(name: "Drink Recipes", displayName: "Drinks", icon: "drinksIcon"),
        DishType(name: "Seafood", displayName: "Seafood", icon: "seafoodIcon"),
        DishType(name: "Cookies", displayName: "Cookies", icon: "cookiesIcon"),
        DishType(name: "Cakes", displayName: "Cakes", icon: "cakeIcon"),
        DishType(name: "Pasta", displayName: "Pasta", icon: "pastaIcon"),
        DishType(name: "Vegetarian", displayName: "Vegetarian", icon: "vegetarianIcon"),
        DishType(name: "Sandwich Recipes", displayName: "Sandwich", icon: "sandwichIcon"),
        DishType(name: "Smoothie Recipes", displayName: "Smoothies", icon: "vegetarianIcon")
    ]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header (fixed) - with explicit background to maintain safe area
                VStack(spacing: 0) {
                    HStack {
                        Text("Explore Recipes")
                            .font(.custom("Playfair9pt-Medium", size: 28))
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 16)

                    // Search Bar (fixed)
                    SearchBarView(
                        text: $searchText,
                        isSearchFocused: $isSearchFocused,
                        searchState: $searchState,
                        onSearch: performSearch,
                        onCancel: cancelSearch
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                }
                .background(Color(.systemBackground))
                .zIndex(1) // Keep header above content

                // Dish Types Row (fixed, shown only in idle state)
                if searchState == .idle {
                    DishTypesRow(dishTypes: dishTypes, viewModel: viewModel)
                        .padding(.top, 8)
                        .background(Color(.systemBackground))
                }

                // Content area - all views use opacity for stable layout
                ZStack(alignment: .top) {
                    // Background
                    Color(.systemBackground)

                    // Base explore content
                    exploreContent
                        .opacity(searchState == .idle && viewModel.selectedDishType == nil ? 1 : 0)
                        .allowsHitTesting(searchState == .idle && viewModel.selectedDishType == nil)

                    // Filtered by category content
                    categoryResultsContent
                        .opacity(searchState == .idle && viewModel.selectedDishType != nil ? 1 : 0)
                        .allowsHitTesting(searchState == .idle && viewModel.selectedDishType != nil)

                    // Search overlay content
                    searchOverlayContent
                        .opacity(searchState == .focused ? 1 : 0)
                        .allowsHitTesting(searchState == .focused)

                    // Loading state
                    loadingContent
                        .opacity(searchState == .searching ? 1 : 0)
                        .allowsHitTesting(searchState == .searching)

                    // Search results
                    searchResultsContent
                        .opacity(searchState == .results ? 1 : 0)
                        .allowsHitTesting(searchState == .results)
                }
            }

            // Loading overlay for initial load only (not for category filtering)
            if viewModel.isLoading && searchState == .idle && viewModel.selectedDishType == nil {
                loadingOverlay
            }
        }
        .background(Color(.systemBackground))
        .onChange(of: isSearchFocused) { _, focused in
            if focused && (searchState == .idle || searchState == .results) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    searchState = .focused
                }
                // Fetch suggestions if there's already text
                if !searchText.isEmpty {
                    Task {
                        await viewModel.fetchAutocompleteSuggestions(searchText)
                    }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            // Fetch autocomplete suggestions while typing
            if searchState == .focused {
                if newValue.isEmpty {
                    viewModel.autocompleteSuggestions = []
                } else {
                    Task {
                        await viewModel.fetchAutocompleteSuggestions(newValue)
                    }
                }
            }
        }
        .onChange(of: scrollToTopTrigger) { _, _ in
            // Tab was tapped while already on Explore - scroll to top and reset
            resetToInitialState()
        }
    }

    // MARK: - Reset to Initial State

    private func resetToInitialState() {
        withAnimation(.easeInOut(duration: 0.3)) {
            // Cancel search
            searchText = ""
            isSearchFocused = false
            searchState = .idle

            // Clear filters
            viewModel.clearFilter()
            viewModel.clearSearchResults()

            // Change content ID to force scroll view to reset to top
            contentID = UUID()
        }
    }

    // MARK: - Explore Content (idle state)

    private var exploreContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                // Cuisine sections
                ForEach(viewModel.cuisineSections) { section in
                    RecipeSection(
                        title: section.cuisine,
                        recipes: section.recipes,
                        section: section,
                        viewModel: viewModel
                    )
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .id(contentID)  // Reset scroll position when ID changes
    }

    // MARK: - Search Overlay Content (focused state)

    private var searchOverlayContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if searchText.isEmpty {
                    // Popular Searches
                    popularSearchesSection
                } else {
                    // Autocomplete Suggestions
                    autocompleteSuggestionsSection
                }
            }
            .padding(.top, 20)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Popular Searches Section

    private var popularSearchesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Popular Searches")
                .font(.custom("Playfair9pt-SemiBold", size: 20))
                .padding(.horizontal, 18)

            VStack(spacing: 0) {
                ForEach(popularSearches, id: \.self) { search in
                    Button(action: {
                        searchText = search
                        performSearch()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(Color("GraniteGray"))
                                .frame(width: 24)

                            Text(search)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundColor(.primary)

                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }

                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
    }

    // MARK: - Autocomplete Suggestions Section

    private var autocompleteSuggestionsSection: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.autocompleteSuggestions, id: \.self) { suggestion in
                Button(action: {
                    searchText = suggestion
                    performSearch()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Color("GraniteGray"))
                            .frame(width: 24)

                        // Highlight matching text
                        highlightedText(suggestion, highlight: searchText)

                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }

                Divider()
                    .padding(.leading, 52)
            }

            // Show "Search for X" option
            Button(action: performSearch) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color("OrangeRed"))
                        .frame(width: 24)

                    Text("Search for \"\(searchText)\"")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundColor(Color("OrangeRed"))

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: - Highlighted Text Helper

    private func highlightedText(_ text: String, highlight: String) -> Text {
        let lowercasedText = text.lowercased()
        let lowercasedHighlight = highlight.lowercased()

        guard let range = lowercasedText.range(of: lowercasedHighlight) else {
            return Text(text)
                .font(.custom("OpenSans-Regular", size: 16))
        }

        let startIndex = text.distance(from: text.startIndex, to: range.lowerBound)
        let endIndex = startIndex + highlight.count

        let prefix = String(text.prefix(startIndex))
        let match = String(text.dropFirst(startIndex).prefix(highlight.count))
        let suffix = String(text.dropFirst(endIndex))

        return Text(prefix).font(.custom("OpenSans-Regular", size: 16)) +
               Text(match).font(.custom("OpenSans-Bold", size: 16)) +
               Text(suffix).font(.custom("OpenSans-Regular", size: 16))
    }

    // MARK: - Loading Content

    private var loadingContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Text("Search Results")
                    .font(.custom("Playfair9pt-SemiBold", size: 24))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 20)

                // Skeleton grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 30, alignment: .top),
                    GridItem(.flexible(), alignment: .top)
                    ], spacing: 30) {
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonRecipeCard()
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 30)
        }
    }

    // MARK: - Search Results Content

    private var searchResultsContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Search Results")
                        .font(.custom("Playfair9pt-SemiBold", size: 24))

                    Spacer()

                    Text("\(viewModel.totalResultsCount) recipes")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color("GraniteGray"))
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)

                if viewModel.searchResults.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No recipes found")
                            .font(.custom("Playfair9pt-Medium", size: 20))
                            .foregroundColor(.gray)
                        Text("Try a different search term")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundColor(Color("GraniteGray"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    // 2-column grid with infinite scroll
                    LazyVGrid(columns: [
                                       GridItem(.flexible(), spacing: 30, alignment: .top),
                                       GridItem(.flexible(), alignment: .top)
                                   ], spacing: 30) {
                        ForEach(viewModel.searchResults) { recipe in
                            GridRecipeCard(recipe: recipe)
                                .onAppear {
                                    // Load more when reaching the last few items
                                    if recipe.id == viewModel.searchResults.last?.id {
                                        if viewModel.searchHasMore && !viewModel.isLoadingMore {
                                            Task {
                                                await viewModel.loadMoreSearchResults()
                                            }
                                        }
                                    }
                                }
                        }
                    }
//                    .padding(.horizontal)
                    .padding(.horizontal, 18)

                    // Loading indicator at bottom
                    if viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(Color("OrangeRed"))
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    }
                }
            }
            .padding(.bottom, 30)
        }
    }

    // MARK: - Category Results Content (filtered by dish type)

    private var categoryResultsContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Results count - use opacity to prevent layout shift
                Text("\(viewModel.totalResultsCount) recipes")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("GraniteGray"))
                    .padding(.horizontal, 18)
                    .opacity(viewModel.isLoading || viewModel.searchResults.isEmpty ? 0 : 1)

                if viewModel.isLoading {
                    // Skeleton loading state
                    LazyVGrid(columns: [
                                        GridItem(.flexible(), spacing: 30, alignment: .top),
                                        GridItem(.flexible(), alignment: .top)
                                    ], spacing: 30) {                         ForEach(0..<6, id: \.self) { _ in
                            SkeletonRecipeCard()
                        }
                    }
                  .padding(.horizontal, 18)
                } else if viewModel.searchResults.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No recipes found")
                            .font(.custom("Playfair9pt-Medium", size: 20))
                            .foregroundColor(.gray)
                        Text("Try selecting a different category")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundColor(Color("GraniteGray"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    // 2-column grid with infinite scroll
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 30, alignment: .top),
                        GridItem(.flexible(), alignment: .top)
                    ], spacing: 30) {
                        ForEach(viewModel.searchResults) { recipe in
                            GridRecipeCard(recipe: recipe)
                                .onAppear {
                                    // Load more when reaching the last few items
                                    if recipe.id == viewModel.searchResults.last?.id {
                                        if viewModel.categoryHasMore && !viewModel.isLoadingMore {
                                            Task {
                                                await viewModel.loadMoreCategoryResults()
                                            }
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 18)

                    // Loading indicator at bottom
                    if viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(Color("OrangeRed"))
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    }
                }
            }
            .padding(.bottom, 30)
        }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Color("OrangeRed"))

                Text("Loading...")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 15)
            )
        }
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchText.isEmpty else { return }

        isSearchFocused = false
        searchState = .searching

        Task {
            await viewModel.searchRecipes(searchText)
            await MainActor.run {
                searchState = .results
            }
        }
    }

    private func cancelSearch() {
        searchText = ""
        isSearchFocused = false
        searchState = .idle
        viewModel.clearSearchResults()
    }
}

// MARK: - Search Bar View

struct SearchBarView: View {
    @Binding var text: String
    var isSearchFocused: FocusState<Bool>.Binding
    @Binding var searchState: SearchState
    let onSearch: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image("search_icon")
                .resizable()
                .renderingMode(.template)
                .frame(width: 17.58, height: 17.58)
                .foregroundColor(Color("GraniteGray"))
            
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Search recipes...")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color("DarkSilver"))
                }
                
                TextField("", text: $text)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .focused(isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit(onSearch)
            }
            
            Button(action: {
                onCancel() 
            }) {
                Image("closeIcon")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 24, height: 24)
                    .foregroundColor(Color("GraniteGray"))
            }
        }
        .padding(.horizontal, 19)
        .frame(height: 44)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color("DarkSilver"), lineWidth: 1)
        )
    }
}

// MARK: - Skeleton Recipe Card

struct SkeletonRecipeCard: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image skeleton
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray5))
                .frame(height: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color.white.opacity(0.4), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: isAnimating ? 200 : -200)
                )
                .clipped()

            // Title skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(height: 16)

            // Subtitle skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 80, height: 14)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Grid Recipe Card (for search results)

struct GridRecipeCard: View {
    let recipe: Recipe
    @ObservedObject private var bookmarkManager = BookmarkManager.shared

    private var isBookmarked: Bool {
        bookmarkManager.isBookmarked(recipe.id)
    }

    var body: some View {
        NavigationLink(destination: RecipeDetailView(recipe: recipe.toRecipeDetail(), recipeId: recipe.id)) {
            VStack(alignment: .leading, spacing: 8) {
                // Image with bookmark
                ZStack(alignment: .topTrailing) {
                    CachedAsyncImage(url: URL(string: recipe.displayImageUrl)) { phase in
                        switch phase {
                        case .empty:
                            imagePlaceholder
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            imagePlaceholder
                        @unknown default:
                            imagePlaceholder
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 140, maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [Color("Nero").opacity(0.5), Color("DimGray").opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 36)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 10,
                                topTrailingRadius: 10
                            )
                        )
                    }

                    // Bookmark button
                    Button(action: {
                        Task {
                            await bookmarkManager.toggleBookmark(for: recipe.id)
                        }
                    }) {
                        Image(isBookmarked ? "selectedBookmarkIcon" : "bookmarkIcon")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .padding(8)
                    }
                }

                // Title and Duration
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.title)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(recipe.durationText)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color("GraniteGray"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color("LightGrayishPink"))
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundColor(Color("GraniteGray"))
            )
    }
}

// MARK: - Dish Types Row

struct DishTypesRow: View {
    let dishTypes: [DishType]
    @ObservedObject var viewModel: ExploreViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(dishTypes) { dishType in
                    DishTypeItem(dishType: dishType, viewModel: viewModel)
                }
            }
            .padding(.horizontal, 18)
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
        Button(action: {
            Task {
                await viewModel.toggleDishTypeFilter(dishType.name, displayName: dishType.displayName)
            }
        }) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color("PeachCream")) 
                        .frame(width: 57, height: 57)

                    Image(dishType.icon)
                }
                .overlay(
                    Group {
                        if isSelected {
                            Circle()
                                .stroke(Color("OrangeRed"), lineWidth: 3)
                        }
                    }
                )
                .padding(2)

                Text(dishType.displayName)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(isSelected ? Color("OrangeRed") : Color("DarkSilver"))
            }
        }
    }
}

// MARK: - Recipe Section (horizontal scroll with auto-loading)

struct RecipeSection: View {
    let title: String
    let recipes: [Recipe]
    var section: CuisineSection? = nil
    var viewModel: ExploreViewModel? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.custom("Playfair9pt-SemiBold", size: 24))
                .padding(.horizontal)
                .padding(.top, 30)

            GeometryReader { outerGeometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(recipes) { recipe in
                            RecipeCard(recipe: recipe)
                        }

                        // Load more trigger - uses GeometryReader to detect visibility
                        if let section = section, section.hasMore, !section.isLoadingMore {
                            GeometryReader { geometry in
                                Color.clear
                                    .onChange(of: geometry.frame(in: .global).minX) { _, minX in
                                        // Trigger when the trigger view enters the visible area
                                        let screenWidth = outerGeometry.size.width
                                        if minX < screenWidth + 100 {
                                            Task {
                                                await viewModel?.loadMoreRecipes(for: section.cuisine)
                                            }
                                        }
                                    }
                            }
                            .frame(width: 1, height: 200)
                        }

                        // Loading indicator
                        if let section = section, section.isLoadingMore {
                            VStack {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .tint(Color("OrangeRed"))
                                Spacer()
                            }
                            .frame(width: 60, height: 200)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .frame(height: 280)
        }
    }
}

// MARK: - Recipe Card (horizontal scroll)

struct RecipeCard: View {
    let recipe: Recipe
    @ObservedObject private var bookmarkManager = BookmarkManager.shared

    private var isBookmarked: Bool {
        bookmarkManager.isBookmarked(recipe.id)
    }

    var body: some View {
        NavigationLink(destination: RecipeDetailView(recipe: recipe.toRecipeDetail(), recipeId: recipe.id)) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    CachedAsyncImage(url: URL(string: recipe.displayImageUrl)) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color(.systemGray5))
                                .overlay(ProgressView())
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color(.systemGray5))
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(.gray)
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 134, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 25))
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [Color("Nero").opacity(0.5), Color("DimGray").opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: 134, height: 42)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 25,
                                topTrailingRadius: 25
                            )
                        )
                    }

                    Button(action: {
                        Task {
                            await bookmarkManager.toggleBookmark(for: recipe.id)
                        }
                    }) {
                        Image(isBookmarked ? "selectedBookmarkIcon" : "bookmarkIcon")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .padding(10)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.title)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .lineLimit(2)
                        .foregroundColor(.primary)

                    Text(recipe.durationText)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color("DarkSilver"))
                }
                .frame(width: 134, height: 65, alignment: .topLeading)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ExploreRecipesView()
}
