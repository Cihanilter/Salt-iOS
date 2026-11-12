//
//  MyRecipesView.swift
//  Salt
//
//  My Recipes (Figma "My Recipes — Final"): All / Imports / Saved, the collections row on
//  every tab (hidden only while searching), and the same recipe card everywhere.
//

import SwiftUI

// MARK: - Tabs

enum MyRecipesTab: String, CaseIterable, Identifiable {
    case all = "All"
    case imports = "Imports"   // The user's own recipes: imported and created by hand
    case saved = "Saved"       // Recipes bookmarked from the app's recipe database

    var id: String { rawValue }

    /// Search bar placeholder for this tab
    var searchPlaceholder: String {
        switch self {
        case .all: String(localized: "Search my recipes")
        case .imports: String(localized: "Search imported recipes")
        case .saved: String(localized: "Search saved recipes")
        }
    }
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
    @State private var selectedTab: MyRecipesTab = .all
    /// Recipe long-pressed for Add to Collection
    @State private var collectionTarget: CollectionRecipeRef?
    @State private var showingShareTutorial = false

    // Callback to switch to Add Recipe tab
    var switchToAddRecipe: (() -> Void)?
    /// "Browse Explore" on an empty Saved tab
    var switchToExplore: (() -> Void)?
    /// "Paste a link instead" after the share walkthrough
    var openLinkImport: (() -> Void)?

    private var isSearching: Bool {
        !viewModel.searchText.isEmpty
    }

    /// New user: nothing saved at all. Search is hidden until there's something to search.
    private var hasNoRecipes: Bool {
        viewModel.items(for: .all, searchFiltered: false).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if viewModel.isLoading && !viewModel.hasContent {
                        loadingGrid
                            .padding(.top, SaltSpacing.section)
                    } else {
                        content
                    }
                }
                .padding(.bottom, SaltSpacing.bottomTabPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SaltColor.surfaceScreen)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                async let recipes: Void = viewModel.loadRecipes()
                async let collections: Void = CollectionsManager.shared.load()
                _ = await (recipes, collections)
            }
            .refreshable {
                async let recipes: Void = viewModel.refresh()
                async let collections: Void = CollectionsManager.shared.load()
                _ = await (recipes, collections)
            }
            .sheet(item: $collectionTarget) { ref in
                AddToCollectionSheet(ref: ref, source: "my_recipes_long_press")
            }
            .fullScreenCover(isPresented: $showingShareTutorial) {
                // "Show me how" replays the share walkthrough
                ShareTutorialView(context: .explore, sources: [OnboardingStorage.preferredSocialSource]) { outcome in
                    showingShareTutorial = false
                    if outcome == .pasteLink { openLinkImport?() }
                }
            }
        }
    }

    // MARK: - Header

    /// Title, tabs and search; 16 apart
    private var header: some View {
        VStack(alignment: .leading, spacing: SaltSpacing.header) {
            Text("My Recipes")
                .font(SaltFont.h1)
                .foregroundStyle(SaltColor.textPrimary)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)

            SaltPageTabs(tabs: MyRecipesTab.allCases, selection: $selectedTab) { $0.rawValue }

            if !hasNoRecipes || isSearching {
                searchBar
            }
        }
        .padding(.horizontal, SaltSpacing.screenMargin)
    }

    private var searchBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(SaltColor.textSecondary)

                TextField("", text: $viewModel.searchText, prompt: Text(selectedTab.searchPlaceholder).foregroundStyle(SaltColor.textSecondary))
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textPrimary)
                    .tint(SaltColor.actionPrimary)
                    .focused($isSearchFocused)
                    .submitLabel(.search)

                if isSearching {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(SaltColor.textDisabled)
                    }
                    .accessibilityLabel("Clear search")
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(SaltColor.surfaceScreen, in: RoundedRectangle(cornerRadius: SaltRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SaltRadius.input, style: .continuous)
                    .stroke(isSearchFocused || isSearching ? SaltColor.textPrimary : SaltColor.borderDefault, lineWidth: 1)
            )

            if isSearchFocused {
                Button("Cancel", action: clearSearch)
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textAccent)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
        .animation(.easeInOut(duration: 0.15), value: isSearching)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        let items = viewModel.items(for: selectedTab, searchFiltered: true)

        // Collections on every tab, always visible; hidden only while searching
        if !isSearching {
            CollectionsRow()
                .padding(.top, SaltSpacing.section)
        }

        if items.isEmpty {
            emptyState
                .padding(.top, isSearching ? 56 : 48)
                .padding(.horizontal, SaltSpacing.screenMargin)
        } else {
            // While searching, the count replaces the "Recipes" title
            Text(isSearching ? (items.count == 1 ? "1 result" : "\(items.count) results") : "Recipes")
                .font(SaltFont.h2)
                .foregroundStyle(SaltColor.textPrimary)
                .padding(.horizontal, SaltSpacing.screenMargin)
                .padding(.top, SaltSpacing.section)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: MyRecipeCard.gridColumns, spacing: 24) {
                ForEach(items) { item in
                    MyRecipeCard(item: item)
                        .contextMenu {
                            Button {
                                collectionTarget = CollectionRecipeRef(item)
                            } label: {
                                Label("Add to Collection", systemImage: "text.badge.plus")
                            }
                        }
                }
            }
            .padding(.horizontal, SaltSpacing.screenMargin)
            .padding(.top, SaltSpacing.titleToContent)
        }
    }

    private var loadingGrid: some View {
        LazyVGrid(columns: MyRecipeCard.gridColumns, spacing: 24) {
            ForEach(0..<4, id: \.self) { _ in
                SkeletonRecipeCard()
            }
        }
        .padding(.horizontal, SaltSpacing.screenMargin)
    }

    // MARK: - Empty States

    @ViewBuilder private var emptyState: some View {
        if isSearching {
            // No button: the fix is changing the search
            SaltEmptyState(
                systemImage: "magnifyingglass",
                title: String(localized: "No matches for \u{201C}\(viewModel.searchText)\u{201D}"),
                message: String(localized: "Try another name or an ingredient.")
            )
        } else if hasNoRecipes && selectedTab != .saved {
            SaltEmptyState(
                systemImage: "book",
                title: String(localized: "Your recipes live here"),
                message: String(localized: "Save recipes from Instagram, TikTok or any website, snap a photo of a cookbook, or write your own."),
                buttonTitle: String(localized: "Add your first recipe"),
                action: { switchToAddRecipe?() }
            )
        } else {
            switch selectedTab {
            case .all, .imports:
                // Has recipes but never imported: the best place to learn the share sheet
                SaltEmptyState(
                    systemImage: "square.and.arrow.up",
                    title: String(localized: "No imports yet"),
                    message: String(localized: "Found a recipe on Instagram, TikTok or a website? Tap Share and choose Salt. It lands here."),
                    buttonTitle: String(localized: "Show me how"),
                    action: { showingShareTutorial = true }
                )
            case .saved:
                SaltEmptyState(
                    systemImage: "book",
                    title: String(localized: "Nothing saved yet"),
                    message: String(localized: "Recipes you save from Explore will show up here."),
                    buttonTitle: String(localized: "Browse Explore"),
                    action: { switchToExplore?() }
                )
            }
        }
    }

    // MARK: - Search

    private func clearSearch() {
        viewModel.searchText = ""
        isSearchFocused = false
    }
}

// MARK: - My Recipe Card

/// Grid card used on every tab: photo, name, time. No bookmark here (everything is already
/// yours); edited copies show "· Edited"; recipes others added to a shared collection carry
/// that person's small avatar.
struct MyRecipeCard: View {
    let item: MyRecipeItem
    /// Set in a shared collection, to show who added someone else's recipe
    var addedBy: CollectionMember?

    /// Card width on 402pt-wide screens, where two columns with 30pt spacing fill the screen
    /// inside 18pt margins. Narrower phones (e.g. 393pt) get slightly narrower cards.
    static let width: CGFloat = 168

    /// Two columns of cards that fit the screen
    static let gridColumns = [
        GridItem(.flexible(maximum: width), spacing: 30, alignment: .top),
        GridItem(.flexible(maximum: width), alignment: .top)
    ]

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 4) {
                photo
                    .padding(.bottom, 4)

                Text(title)
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Text(duration)
                    if isEdited {
                        Text("·")
                        Text("Edited")
                    }
                    if let addedBy {
                        Text("·")
                        SaltAvatar(name: addedBy.displayName, size: 18)
                            .accessibilityLabel("Added by \(addedBy.displayName)")
                    }
                }
                .font(SaltFont.body)
                .foregroundStyle(SaltColor.textSecondary)
                .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var destination: some View {
        switch item {
        case .own(let recipe) where !recipe.isByCurrentUser:
            // Someone else's recipe in a shared collection: viewed and saved as a copy
            CollectionRecipeCopyView(recipe: recipe)
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

    private var isEdited: Bool {
        if case .own(let recipe) = item { return recipe.isCustomizedCopy }
        return false
    }

    private var imageUrl: String {
        switch item {
        case .own(let recipe): recipe.displayImageUrl
        case .saved(let recipe): recipe.displayImageUrl
        }
    }

    // MARK: Photo

    /// Column-wide (168 at most) × 140 frame; the image fills it and is cropped from the center.
    private var photo: some View {
        SaltColor.surfaceControl
            .frame(maxWidth: Self.width)
            .frame(height: 140)
            .overlay {
                if imageUrl.isEmpty {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 22))
                        .foregroundStyle(SaltColor.textDisabled)
                } else {
                    RecipeCardImage(url: imageUrl)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: SaltRadius.recipeImage, style: .continuous))
            // Clipping doesn't limit taps; keep the hidden overflow from taking the next card's taps
            .contentShape(RoundedRectangle(cornerRadius: SaltRadius.recipeImage, style: .continuous))
    }
}

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
