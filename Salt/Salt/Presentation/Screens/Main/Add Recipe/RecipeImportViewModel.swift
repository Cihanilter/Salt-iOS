//
//  RecipeImportViewModel.swift
//  Salt
//

import Foundation
import SwiftUI
import UIKit
import Combine

@MainActor
class RecipeImportViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isLoading = false
    @Published var importedRecipe: ImportedRecipe?
    @Published var errorMessage: String?
    @Published var showingPreview = false
    @Published var savedSuccessfully = false

    // MARK: - Private Properties

    private let importService = RecipeImportService.shared

    // MARK: - Public Methods

    /// Import recipe from URL string
    func importRecipe(from urlString: String) async {
        let trimmedUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUrl.isEmpty else {
            errorMessage = "Please enter a recipe URL"
            return
        }

        // Add https:// if missing
        var finalUrl = trimmedUrl
        if !finalUrl.hasPrefix("http://") && !finalUrl.hasPrefix("https://") {
            finalUrl = "https://" + finalUrl
        }

        isLoading = true
        errorMessage = nil
        importedRecipe = nil

        do {
            let recipe = try await importService.importRecipe(from: finalUrl)
            importedRecipe = recipe
            showingPreview = true
            print("✅ Imported recipe: \(recipe.title)")
        } catch let error as RecipeImportError {
            errorMessage = error.errorDescription
            print("❌ Import error: \(error.errorDescription ?? "Unknown")")
        } catch {
            errorMessage = "Failed to import recipe: \(error.localizedDescription)"
            print("❌ Import error: \(error)")
        }

        isLoading = false
    }

    /// Save imported recipe to user's collection (original method)
    func saveRecipe() async -> Bool {
        guard let recipe = importedRecipe else { return false }

        do {
            _ = try await RecipeService.shared.saveImportedRecipe(recipe)
            print("✅ Saved recipe: \(recipe.title)")
            savedSuccessfully = true
            // Note: Don't clear import here - let the preview screen handle it
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to save recipe: \(error)")
            return false
        }
    }

    /// Save recipe from RecipeDetail (used when recipe was edited in preview)
    func saveRecipe(from recipeDetail: RecipeDetail, photos: [UIImage] = []) async -> Bool {
        do {
            // Upload any new photos
            var imageUrls = recipeDetail.images
            // Filter out any potentially corrupted photos
            let validPhotos = photos.filter { $0.size.width > 0 && $0.size.height > 0 }
            if !validPhotos.isEmpty && validPhotos.count < 50 {
                let recipeId = UUID()
                let newPhotoUrls = try await RecipeService.shared.uploadRecipeImages(validPhotos, recipeId: recipeId)
                imageUrls.append(contentsOf: newPhotoUrls)
            }

            // Create updated RecipeDetail with all images
            let finalRecipeDetail = RecipeDetail(
                title: recipeDetail.title,
                duration: recipeDetail.duration,
                ingredientsCount: recipeDetail.ingredientsCount,
                description: recipeDetail.description,
                servings: recipeDetail.servings,
                prepTime: recipeDetail.prepTime,
                cookTime: recipeDetail.cookTime,
                ingredients: recipeDetail.ingredients,
                instructions: recipeDetail.instructions,
                notes: recipeDetail.notes,
                images: imageUrls
            )

            _ = try await RecipeService.shared.saveRecipeDetail(finalRecipeDetail, sourceUrl: importedRecipe?.sourceUrl)
            print("✅ Saved edited recipe: \(recipeDetail.title)")
            savedSuccessfully = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to save recipe: \(error)")
            return false
        }
    }

    /// Clear current import
    func clearImport() {
        importedRecipe = nil
        errorMessage = nil
        showingPreview = false
    }
}
