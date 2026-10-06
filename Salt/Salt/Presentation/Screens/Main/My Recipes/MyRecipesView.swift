//
//  MyRecipesView.swift
//  Salt
//
//  Screen displaying user's saved and created recipes
//

import SwiftUI

// MARK: - Tabs

enum MyRecipesTab: String, CaseIterable, Identifiable {
    case all = "All"
    case imports = "Imports"   // The user's own recipes: imported and created by hand
    case saved = "Saved"       // Recipes bookmarked from the app's recipe database

    var id: String { rawValue }
}

/// A card in the My Recipes grid: either one of the user's own recipes or a bookmarked one.
enum MyRecipeItem: Identifiable {
    case own(UserRecipe)
    case saved(Recipe)

    var id: String {
        switch self {
        case .own(let recipe): "own-\(recipe.id)"
        case .saved(let recipe): "saved-\(recipe.id)"
        }
    }
}

struct MyRecipesView: View {
    @ObservedObject private var viewModel = MyRecipesViewModel.shared
    @FocusState private var isSearchFocused: Bool
    @State private var selectedTab: MyRecipesTab = .imports

    // Callback to switch to Add Recipe tab
    var switchToAddRecipe: (() -> Void)?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 16) {
                    Text("My Recipes")
                        .font(.custom("Playfair9pt-Medium", size: 28))
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 6)

                    // All / Imports / Saved
                    MyRecipesTabPicker(selection: $selectedTab)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8) // 16pt stack spacing + 8 = 24pt to the search bar

                    // Search Bar
                    HStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Image("search_icon")
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 17.58, height: 17.58)
                                .foregroundColor(Color("GraniteGray"))

                            ZStack(alignment: .leading) {
                                if viewModel.searchText.isEmpty {
                                    Text("Search in My Recipes...")
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundColor(Color("DarkSilver"))
                                }

                                TextField("", text: $viewModel.searchText)
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .focused($isSearchFocused)
                            }

                            // Clear button only appears once the user has typed something
                            if !viewModel.searchText.isEmpty {
                                Button(action: clearSearch) {
                                    Image("closeIcon")
                                        .resizable()
                                        .renderingMode(.template)
                                        .frame(width: 24, height: 24)
                                        .foregroundColor(Color("GraniteGray"))
                                }
                                .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.15), value: viewModel.searchText.isEmpty)
                        .padding(.horizontal, 19)
                        .frame(height: 44)
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color("DarkSilver"), lineWidth: 1)
                        )

                        // Leave search, even with nothing typed (the clear button only shows with text)
                        if isSearchFocused {
                            Button("Cancel", action: clearSearch)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundColor(Color("OrangeRed"))
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
                    .padding(.horizontal, 18)
                }
                
                // Content
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if items(for: selectedTab).isEmpty {
                    emptyStateView
                } else {
                    recipesContent
                }
            }
            .background(Color(.systemBackground))
            .task {
                await viewModel.loadRecipes()
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }
    
    // MARK: - Search

    private func clearSearch() {
        viewModel.searchText = ""
        isSearchFocused = false
    }

    // MARK: - Tab Items

    /// Recipes shown for a tab, filtered by the search text.
    private func items(for tab: MyRecipesTab) -> [MyRecipeItem] {
        let own = viewModel.filteredUserRecipes.map(MyRecipeItem.own)
        let saved = viewModel.filteredBookmarkedRecipes.map(MyRecipeItem.saved)

        switch tab {
        case .all: return own + saved
        case .imports: return own
        case .saved: return saved
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: selectedTab == .saved ? "bookmark" : "book.closed")
                .font(.system(size: 60))
                .foregroundColor(Color("DarkSilver"))

            Text(emptyStateTitle)
                .font(.custom("Playfair9pt-SemiBold", size: 22))
                .multilineTextAlignment(.center)

            Text(emptyStateMessage)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(Color("GraniteGray"))
                .multilineTextAlignment(.center)

            // Offer to add a recipe, except when searching or on Saved (saving happens from Explore)
            if viewModel.searchText.isEmpty && selectedTab != .saved {
                Button(action: { switchToAddRecipe?() }) {
                    Text("Add Your First Recipe")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color("Orange"))
                        .cornerRadius(10)
                }
                .padding(.top, 10)
            }

            Spacer()
        }
        .padding()
    }

    private var emptyStateTitle: String {
        if !viewModel.searchText.isEmpty { return "No matching recipes" }
        return selectedTab == .saved ? "No saved recipes yet" : "No recipes yet"
    }

    private var emptyStateMessage: String {
        if !viewModel.searchText.isEmpty {
            return "Nothing in \(selectedTab.rawValue) matches \"\(viewModel.searchText)\""
        }
        switch selectedTab {
        case .all: return "Import or create recipes, or save\nrecipes from Explore to see them here"
        case .imports: return "Import a recipe from a link or social media,\nor create your own"
        case .saved: return "Tap the bookmark on any recipe\nin Explore to save it here"
        }
    }

    // MARK: - Recipes Content

    private var recipesContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [
                GridItem(.fixed(MyRecipeCard.width), spacing: 30, alignment: .top),
                GridItem(.fixed(MyRecipeCard.width), alignment: .top)
            ], spacing: 30) {
                ForEach(items(for: selectedTab)) { item in
                    MyRecipeCard(item: item)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Tab Picker

/// Segmented All / Imports / Saved control, styled like the Create / Import switcher.
struct MyRecipesTabPicker: View {
    @Binding var selection: MyRecipesTab
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MyRecipesTab.allCases) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = tab
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.custom("Playfair9pt-Regular", size: 22))
                        .lineLimit(1)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .matchedGeometryEffect(id: "selectedTab", in: selectionNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(width: 348, height: 44)
        .background(Color(red: 1.0, green: 0.941, blue: 0.855)) // #FFF0DA
        .cornerRadius(16)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - My Recipe Card

/// Grid card used on every tab. Photos are cropped into the same fixed-height frame so square
/// imported photos and portrait photos from the app's database line up evenly.
struct MyRecipeCard: View {
    let item: MyRecipeItem
    @ObservedObject private var bookmarkManager = BookmarkManager.shared

    /// Card width; two columns of 168 with 30pt spacing fill the screen inside 18pt margins
    static let width: CGFloat = 168

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 8) {
                photo
                    .overlay(alignment: .topTrailing) {
                        if case .saved(let recipe) = item {
                            bookmarkButton(for: recipe)
                        }
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(duration)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color("GraniteGray"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var destination: some View {
        switch item {
        case .own(let recipe):
            RecipeDetailView(recipe: recipe.toRecipeDetail(), userRecipeId: recipe.id)
        case .saved(let recipe):
            RecipeDetailView(recipe: recipe.toRecipeDetail(), recipeId: recipe.id)
        }
    }

    private var title: String {
        switch item {
        case .own(let recipe): recipe.title
        case .saved(let recipe): recipe.title
        }
    }

    private var duration: String {
        switch item {
        case .own(let recipe): recipe.durationText
        case .saved(let recipe): recipe.durationText
        }
    }

    private var imageUrl: URL? {
        let urlString: String
        switch item {
        case .own(let recipe): urlString = recipe.displayImageUrl
        case .saved(let recipe): urlString = recipe.displayImageUrl
        }
        return urlString.isEmpty ? nil : URL(string: urlString)
    }

    // MARK: Photo

    /// Fixed 168 × 140 frame; the image fills it and is cropped from the center.
    private var photo: some View {
        Color("LightGrayishPink")
            .frame(width: Self.width, height: 140)
            .overlay {
                if let imageUrl {
                    CachedAsyncImage(url: imageUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty:
                            ProgressView()
                        default:
                            photoPlaceholderIcon
                        }
                    }
                } else {
                    photoPlaceholderIcon
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 25))
    }

    private var photoPlaceholderIcon: some View {
        Image(systemName: "photo")
            .font(.system(size: 24))
            .foregroundColor(Color("GraniteGray"))
    }

    private func bookmarkButton(for recipe: Recipe) -> some View {
        let isBookmarked = bookmarkManager.isBookmarked(recipe.id)
        return Button(action: {
            Task {
                await bookmarkManager.toggleBookmark(for: recipe.id)
            }
        }) {
            Image(isBookmarked ? "selectedBookmarkIcon" : "bookmarkIcon")
                .resizable()
                .frame(width: 24, height: 24)
                .padding(8)
                .background(Circle().fill(Color.black.opacity(0.25)))
                .padding(8)
        }
        .accessibilityLabel(isBookmarked ? "Remove from saved" : "Save recipe")
    }
}

//// MARK: - User Recipe Card (Horizontal)
//
//struct UserRecipeCard: View {
//    let recipe: UserRecipe
//    
//    var body: some View {
//        NavigationLink(destination: RecipeDetailView(recipe: recipe.toRecipeDetail())) {
//            VStack(alignment: .leading, spacing: 8) {
//                // Image
//                if let imageUrl = recipe.displayImageUrl.nilIfEmpty,
//                   let url = URL(string: imageUrl) {
//                    CachedAsyncImage(url: url) { phase in
//                        switch phase {
//                        case .empty:
//                            recipeImagePlaceholder
//                        case .success(let image):
//                            image
//                                .resizable()
//                                .scaledToFill()
//                        case .failure:
//                            recipeImagePlaceholder
//                        @unknown default:
//                            recipeImagePlaceholder
//                        }
//                    }
//                    .frame(width: 150, height: 100)
//                    .clipped()
//                    .cornerRadius(10)
//                } else {
//                    recipeImagePlaceholder
//                        .frame(width: 150, height: 100)
//                        .cornerRadius(10)
//                }
//                
//                // Title
//                Text(recipe.title)
//                    .font(.custom("Playfair9pt-Regular", size: 14))
//                    .foregroundColor(.primary)
//                    .lineLimit(2)
//                    .frame(width: 150, alignment: .leading)
//                
//                // Duration
//                Text(recipe.durationText)
//                    .font(.custom("OpenSans-Regular", size: 12))
//                    .foregroundColor(Color("GraniteGray"))
//            }
//        }
//    }
//    
//    private var recipeImagePlaceholder: some View {
//        Rectangle()
//            .fill(Color("LightGrayishPink"))
//            .overlay(
//                Image(systemName: "photo")
//                    .font(.system(size: 24))
//                    .foregroundColor(Color("GraniteGray"))
//            )
//    }
//}

//// MARK: - User Recipe Grid Card
//
//struct UserRecipeGridCard: View {
//    let recipe: UserRecipe
//    
//    var body: some View {
//        NavigationLink(destination: RecipeDetailView(recipe: recipe.toRecipeDetail())) {
//            VStack(alignment: .leading, spacing: 8) {
//                // Image
//                if let imageUrl = recipe.displayImageUrl.nilIfEmpty,
//                   let url = URL(string: imageUrl) {
//                    CachedAsyncImage(url: url) { phase in
//                        switch phase {
//                        case .empty:
//                            gridImagePlaceholder
//                        case .success(let image):
//                            image
//                                .resizable()
//                                .scaledToFill()
//                        case .failure:
//                            gridImagePlaceholder
//                        @unknown default:
//                            gridImagePlaceholder
//                        }
//                    }
//                    .frame(height: 120)
//                    .clipped()
//                    .cornerRadius(10)
//                } else {
//                    gridImagePlaceholder
//                        .frame(height: 120)
//                        .cornerRadius(10)
//                }
//                
//                // Title
//                Text(recipe.title)
//                    .font(.custom("Playfair9pt-Regular", size: 14))
//                    .foregroundColor(.primary)
//                    .lineLimit(2)
//                
//                // Info
//                HStack(spacing: 8) {
//                    Image(systemName: "clock")
//                        .font(.system(size: 10))
//                    Text(recipe.durationText)
//                        .font(.custom("OpenSans-Regular", size: 11))
//                    
//                    Spacer()
//                    
//                    // Created badge
//                    Text("Created")
//                        .font(.custom("OpenSans-Regular", size: 10))
//                        .foregroundColor(.white)
//                        .padding(.horizontal, 6)
//                        .padding(.vertical, 2)
//                        .background(Color("Orange"))
//                        .cornerRadius(4)
//                }
//                .foregroundColor(Color("GraniteGray"))
//            }
//        }
//    }
//    
//    private var gridImagePlaceholder: some View {
//        Rectangle()
//            .fill(Color("LightGrayishPink"))
//            .overlay(
//                Image(systemName: "photo")
//                    .font(.system(size: 24))
//                    .foregroundColor(Color("GraniteGray"))
//            )
//    }
//}
//
//// MARK: - Saved Recipe Grid Card
//
//struct SavedRecipeGridCard: View {
//    let recipe: Recipe
//    
//    var body: some View {
//        NavigationLink(destination: RecipeDetailView(recipe: recipe.toRecipeDetail(), recipeId: recipe.id)) {
//            VStack(alignment: .leading, spacing: 8) {
//                // Image
//                CachedAsyncImage(url: URL(string: recipe.displayImageUrl)) { phase in
//                    switch phase {
//                    case .empty:
//                        gridImagePlaceholder
//                    case .success(let image):
//                        image
//                            .resizable()
//                            .scaledToFill()
//                    case .failure:
//                        gridImagePlaceholder
//                    @unknown default:
//                        gridImagePlaceholder
//                    }
//                }
//                .frame(height: 120)
//                .clipped()
//                .cornerRadius(10)
//                
//                // Title
//                Text(recipe.title)
//                    .font(.custom("Playfair9pt-Regular", size: 14))
//                    .foregroundColor(.primary)
//                    .lineLimit(2)
//                
//                // Info
//                HStack(spacing: 8) {
//                    Image(systemName: "clock")
//                        .font(.system(size: 10))
//                    Text(recipe.durationText)
//                        .font(.custom("OpenSans-Regular", size: 11))
//                    
//                    Spacer()
//                    
//                    // Saved badge
//                    Image(systemName: "bookmark.fill")
//                        .font(.system(size: 10))
//                        .foregroundColor(Color("Orange"))
//                }
//                .foregroundColor(Color("GraniteGray"))
//            }
//        }
//    }
//    
//    private var gridImagePlaceholder: some View {
//        Rectangle()
//            .fill(Color("LightGrayishPink"))
//            .overlay(
//                Image(systemName: "photo")
//                    .font(.system(size: 24))
//                    .foregroundColor(Color("GraniteGray"))
//            )
//    }
//}

// MARK: - String Extension

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Preview

#Preview {
    MyRecipesView()
}
