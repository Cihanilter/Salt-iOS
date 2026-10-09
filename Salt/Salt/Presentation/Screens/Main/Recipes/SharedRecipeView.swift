//
//  SharedRecipeView.swift
//  Salt
//
//  Recipe opened from a share link, with Save Recipe to add it to My Recipes
//

import SwiftUI

struct SharedRecipeView: View {
    let code: String
    var onAddMoreRecipes: () -> Void
    var onGoToMyRecipes: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sharedRecipe: SharedRecipe?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let sharedRecipe {
                    RecipeDetailView(
                        recipe: sharedRecipe.toRecipeDetail(),
                        mode: .preview,
                        onSave: {
                            // The recipe on screen (edits included) is in shared storage
                            let savedData = PendingSaveDataStorage.shared.retrieve()
                            guard let recipeDetail = savedData.recipe else { return false }
                            return await save(recipeDetail, photos: savedData.photos, shared: sharedRecipe)
                        },
                        onAddMoreRecipes: onAddMoreRecipes,
                        onGoToMyRecipes: onGoToMyRecipes
                    )
                } else if let errorMessage {
                    errorView(message: errorMessage)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: code) {
            await load()
        }
    }

    private func load() async {
        sharedRecipe = nil
        errorMessage = nil
        do {
            let recipe = try await SharedRecipeService.shared.fetchRecipe(code: code)
            sharedRecipe = recipe
            Analytics.log(.sharedRecipeOpened, ["recipe_type": recipe.originalRecipeId == nil ? "own" : "explore"])
        } catch {
            errorMessage = (error as? SharedRecipeError)?.errorDescription
                ?? "Couldn't load the recipe. Check your connection and try again."
        }
    }

    /// Explore recipes are bookmarked (listed under Saved) unless they were edited here,
    /// then they're saved as the user's own copy, like Customize. Other recipes are
    /// saved as the user's own recipe.
    private func save(_ detail: RecipeDetail, photos: [UIImage], shared: SharedRecipe) async -> Bool {
        let viewModel = MyRecipesViewModel.shared
        do {
            if let originalId = shared.originalRecipeId {
                if photos.isEmpty && isUnchanged(detail, from: shared) {
                    let bookmarkManager = BookmarkManager.shared
                    if !bookmarkManager.isBookmarked(originalId) {
                        let bookmarked = await bookmarkManager.toggleBookmark(for: originalId)
                        guard bookmarked else { return false }
                    }
                    await viewModel.refresh()
                } else {
                    let copy = try await viewModel.saveCustomizedCopy(of: originalId, from: detail, newPhotos: photos)
                    RecipeService.shared.requestNutritionEstimate(for: copy)
                }
            } else {
                _ = try await viewModel.saveSharedRecipe(from: detail, newPhotos: photos)
            }
            Analytics.log(.sharedRecipeSaved, ["recipe_type": shared.originalRecipeId == nil ? "own" : "explore"])
            return true
        } catch {
            print("❌ Failed to save shared recipe: \(error)")
            return false
        }
    }

    /// Whether the recipe wasn't edited before saving
    private func isUnchanged(_ detail: RecipeDetail, from shared: SharedRecipe) -> Bool {
        let original = shared.toRecipeDetail()
        return detail.title == original.title
            && detail.description == original.description
            && detail.servings == original.servings
            && detail.prepTime == original.prepTime
            && detail.cookTime == original.cookTime
            && detail.ingredients == original.ingredients
            && detail.instructions == original.instructions
            && detail.notes == original.notes
            && detail.images == original.images
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife")
                .font(.system(size: 44))
                .foregroundColor(Color("GraniteGray"))
            Text(message)
                .font(.custom("OpenSans-Regular", size: 16))
                .multilineTextAlignment(.center)
                .foregroundColor(Color("GraniteGray"))
            Button("Try Again") {
                Task { await load() }
            }
            .font(.custom("OpenSans-SemiBold", size: 16))
            .foregroundColor(Color("OrangeRed"))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close") { dismiss() }
            }
        }
    }
}
