//
//  MyRecipesView.swift
//  Salt
//
//  Screen displaying user's saved and created recipes
//

import SwiftUI

struct MyRecipesView: View {
    @ObservedObject private var viewModel = MyRecipesViewModel.shared
    @FocusState private var isSearchFocused: Bool

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
                    
                    // Search Bar
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
                            
                        Button(action: {
                            viewModel.searchText = ""
                            isSearchFocused = false
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
                   
                    .padding(.horizontal, 18)
                    
                    // Add New Recipe Button
                    Button(action: { switchToAddRecipe?() }) {
                        HStack(spacing: 8) {
                            Text("Add New Recipe")
                                .font(.custom("Playfair9pt-SemiBold", size: 16))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Image("addNewRecipeIcon")
                                .resizable()
                                .frame(width: 32, height: 32)
                                
                        }
                        .padding(.leading, 19)
                        .padding(.trailing, 12)
                        .frame(height: 46)
                        .background(Color(.systemBackground))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color("DarkSilver"), lineWidth: 1)
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                }
                
                // Content
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if !viewModel.hasContent {
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
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(Color("DarkSilver"))
            
            Text("No recipes yet")
                .font(.custom("Playfair9pt-SemiBold", size: 22))
            
            Text("Create your own recipes or save\nrecipes from Explore to see them here")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(Color("GraniteGray"))
                .multilineTextAlignment(.center)
            
            Button(action: { switchToAddRecipe?() }) {
                Text("Create Your First Recipe")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color("Orange"))
                    .cornerRadius(10)
            }
            .padding(.top, 10)
            
            Spacer()
        }
        .padding()
    }
    

    // MARK: - Recipes Content

    private var recipesContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // User Created Recipes Grid with gradient overlay
                if !viewModel.filteredUserRecipes.isEmpty {
                    ZStack(alignment: .bottom) {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 30, alignment: .top),
                            GridItem(.flexible(), alignment: .top)
                        ], spacing: 30) {
                            ForEach(viewModel.displayedUserRecipes) { recipe in
                                RecipeGridCard(recipe: recipe)
                            }
                        }
                        
                        // Gradient overlay (only when collapsed and has more recipes)
                        if viewModel.hasMoreUserRecipes && !viewModel.showAllRecipes {
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.1), location: 0),
                                    .init(color: Color.white, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 161)
                            .frame(maxWidth: .infinity)
                            .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 18)
                    
                    // View more button
                    if viewModel.hasMoreUserRecipes && !viewModel.showAllRecipes {
                        Button(action: {
                            withAnimation {
                                viewModel.showAllRecipes = true
                            }
                        }) {
                            Text("View more")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundColor(.primary)
                                .underline()
                        }
                    }
                }
                
                // Saved Recipes Section
                if !viewModel.filteredBookmarkedRecipes.isEmpty {
                    VStack(alignment: .leading, spacing: 30) {
                        Text("Saved Recipes")
                            .font(.custom("Playfair9pt-SemiBold", size: 24))
                            .padding(.horizontal, 18)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 20) {
                                ForEach(viewModel.filteredBookmarkedRecipes) { recipe in
                                    SavedRecipeCard(recipe: recipe)
                                }
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                }
            }
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Recipe Grid Card

struct RecipeGridCard: View {
    let recipe: UserRecipe

    var body: some View {
        NavigationLink(destination: RecipeDetailView(recipe: recipe.toRecipeDetail(), userRecipeId: recipe.id)) {
            VStack(alignment: .leading, spacing: 8) {
                // Image
                if let imageUrl = recipe.displayImageUrl.nilIfEmpty,
                   let url = URL(string: imageUrl) {
                    CachedAsyncImage(url: url) { phase in
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
                } else {
                    imagePlaceholder
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 140, maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
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

// MARK: - Saved Recipe Card

struct SavedRecipeCard: View {
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
                            stops: [
                                .init(color: Color("Nero"), location: -4),
                                .init(color: Color("DimGray").opacity(0), location: 1)
                            ],
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
