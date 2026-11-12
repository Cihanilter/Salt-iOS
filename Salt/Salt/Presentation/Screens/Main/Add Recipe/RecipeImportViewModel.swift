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
    /// The last import's error, so the sheets can pick the right next step
    @Published var lastError: RecipeImportError?
    @Published var showingPreview = false
    @Published var savedSuccessfully = false
    /// The last saved recipe, for the "Add to a collection?" prompt
    private(set) var savedRecipeId: UUID?
    /// The last saved recipe, opened on the recipe page after an import
    private(set) var savedRecipe: UserRecipe?

    // MARK: - Private Properties

    private let importService = RecipeImportService.shared
    /// How the current import started ("pasted" or "share_extension"), sent with its analytics events
    private var importEntry = "pasted"

    // MARK: - Public Methods

    /// Import recipe from URL string. `entry` says how the link got here, for analytics.
    func importRecipe(from urlString: String, entry: String = "pasted") async {
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
        lastError = nil
        importedRecipe = nil
        // Reset so the view sees this import's save as a change and clears the link again
        savedSuccessfully = false

        importEntry = entry
        let source = Analytics.importSource(for: finalUrl)
        Analytics.log(.importStarted, ["source": source, "entry": entry])
        let startedAt = Date()

        do {
            let recipe = try await importService.importRecipe(from: finalUrl)
            // Cancelled on the loading screen while the recipe was on its way
            guard !Task.isCancelled else {
                isLoading = false
                return
            }
            importedRecipe = recipe
            showingPreview = true
            print("✅ Imported recipe: \(recipe.title)")
        } catch where Task.isCancelled {
            // Cancelled on the loading screen: no error to show
            print("⏹️ Import cancelled")
        } catch {
            print("❌ Import error: \(error)")
            let importError = RecipeImportError.from(error)
            errorMessage = importError.errorDescription
            lastError = importError
            Analytics.log(.importFailed, [
                "source": source,
                "entry": entry,
                "error": importError.code,
                "url": finalUrl,
                "duration_seconds": Int(Date().timeIntervalSince(startedAt))
            ])
        }

        isLoading = false
    }

    /// Import a recipe from photos or screenshots (a cookbook page, a recipe card, an Instagram
    /// caption or a recipe site). `entry` says how they got here ("photo" or "share_extension").
    func importRecipe(fromPhotos photos: [UIImage], entry: String = "photo") async {
        guard !photos.isEmpty else { return }
        await importWithoutLink(origin: .photo, entry: entry, extra: ["photo_count": photos.count]) {
            try await self.importService.importRecipe(fromPhotos: photos)
        }
    }

    /// Import a recipe from text pasted in or shared from the Notes app.
    /// `entry` says how it got here ("pasted" or "share_extension").
    func importRecipe(fromText text: String, entry: String = "pasted") async {
        await importWithoutLink(origin: .note, entry: entry, extra: ["text_length": text.count]) {
            try await self.importService.importRecipe(fromText: text)
        }
    }

    /// Shared flow for photo and note imports, with the same state and analytics as link imports
    private func importWithoutLink(
        origin: ImportOrigin,
        entry: String,
        extra: [String: Any],
        load: () async throws -> ImportedRecipe
    ) async {
        isLoading = true
        errorMessage = nil
        lastError = nil
        importedRecipe = nil
        savedSuccessfully = false

        importEntry = entry
        let source = origin.rawValue
        let startedProperties: [String: Any] = ["source": source, "entry": entry]
        Analytics.log(.importStarted, startedProperties.merging(extra) { $1 })
        let startedAt = Date()

        do {
            let recipe = try await load()
            // Cancelled on the loading screen while the recipe was on its way
            guard !Task.isCancelled else {
                isLoading = false
                return
            }
            importedRecipe = recipe
            showingPreview = true
            print("✅ Imported recipe from \(source): \(recipe.title)")
        } catch where Task.isCancelled {
            // Cancelled on the loading screen: no error to show
            print("⏹️ \(source) import cancelled")
        } catch {
            print("❌ \(source) import error: \(error)")
            let importError = RecipeImportError.from(error)
            errorMessage = importError.errorDescription
            lastError = importError
            Analytics.log(.importFailed, [
                "source": source,
                "entry": entry,
                "error": importError.code,
                "duration_seconds": Int(Date().timeIntervalSince(startedAt))
            ])
        }

        isLoading = false
    }

    /// The imported recipe's link; nil for photo and note imports
    private var linkSourceUrl: String? {
        importedRecipe?.origin.hasLink == true ? importedRecipe?.sourceUrl : nil
    }

    /// Analytics source of the current import
    private var importedSource: String {
        guard let importedRecipe, !importedRecipe.origin.hasLink else {
            return Analytics.importSource(for: importedRecipe?.sourceUrl)
        }
        return importedRecipe.origin.rawValue
    }

    /// Save imported recipe to user's collection (original method)
    func saveRecipe() async -> Bool {
        guard let recipe = importedRecipe else { return false }

        do {
            savedRecipeId = try await RecipeService.shared.saveImportedRecipe(recipe).id
            print("✅ Saved recipe: \(recipe.title)")
            Analytics.log(.recipeImported, [
                "source": importedSource,
                "entry": importEntry
            ])
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
                images: imageUrls,
                sourceUrl: recipeDetail.sourceUrl ?? linkSourceUrl,
                sourceName: recipeDetail.sourceName ?? importedRecipe?.sourceName
            )

            let saved = try await RecipeService.shared.saveRecipeDetail(
                finalRecipeDetail,
                sourceUrl: linkSourceUrl,
                source: importedRecipe?.origin.recipeSource
            )
            savedRecipe = saved
            savedRecipeId = saved.id
            print("✅ Saved edited recipe: \(recipeDetail.title)")
            Analytics.log(.recipeImported, [
                "source": importedSource,
                "entry": importEntry,
                "photos_added": validPhotos.count
            ])
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
        lastError = nil
        showingPreview = false
    }
}
