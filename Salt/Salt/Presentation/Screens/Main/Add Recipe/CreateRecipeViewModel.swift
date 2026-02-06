//
//  CreateRecipeViewModel.swift
//  Salt
//
//  ViewModel for creating new recipes
//

import Foundation
import SwiftUI
import PhotosUI
import Combine

@MainActor
class CreateRecipeViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var title = ""
    @Published var description = ""
    @Published var ingredientsText = ""
    @Published var instructionsText = ""
    @Published var prepTime = ""
    @Published var cookTime = ""
    @Published var servings = ""
    @Published var notes = ""

    @Published var selectedPhotos: [PhotosPickerItem] = []
    @Published var photoImages: [UIImage] = []

    // Original image URLs (for edit mode - preserves existing images)
    @Published var originalImageUrls: [String] = []

    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var showingPreview = false
    @Published var savedSuccessfully = false

    // MARK: - Private Properties

    private let recipeService = RecipeService.shared

    // MARK: - Computed Properties

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !ingredientsText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var ingredientsList: [String] {
        ingredientsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var instructionsList: [String] {
        instructionsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var prepTimeMinutes: Int? {
        Int(prepTime)
    }

    var cookTimeMinutes: Int? {
        Int(cookTime)
    }

    var servingsInt: Int? {
        Int(servings)
    }

    var totalTimeMinutes: Int? {
        let prep = prepTimeMinutes ?? 0
        let cook = cookTimeMinutes ?? 0
        return prep + cook > 0 ? prep + cook : nil
    }

    // MARK: - Photo Handling

    func loadPhotos() async {
        var images: [UIImage] = []

        for item in selectedPhotos {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }

        await MainActor.run {
            photoImages = images
        }
    }

    func removePhoto(at index: Int) {
        if index < photoImages.count {
            photoImages.remove(at: index)
        }
        if index < selectedPhotos.count {
            selectedPhotos.remove(at: index)
        }
    }

    // MARK: - Preview Recipe

    func buildPreviewRecipe() -> UserRecipe {
        guard let userIdString = AuthManager.shared.currentUser?.id,
              let userId = UUID(uuidString: userIdString) else {
            return UserRecipe.empty(userId: UUID())
        }

        return UserRecipe(
            id: UUID(),
            userId: userId,
            createdAt: nil,
            updatedAt: nil,
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.isEmpty ? nil : description.trimmingCharacters(in: .whitespaces),
            imageUrl: nil,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            totalTimeMinutes: totalTimeMinutes,
            servings: servingsInt,
            servingsText: servings.isEmpty ? nil : "\(servings) servings",
            ingredients: ingredientsList,
            instructions: instructionsList,
            cuisines: nil,
            dishTypes: nil,
            notes: notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces),
            sourceUrl: nil,
            sourceName: nil,
            photos: nil
        )
    }

    // MARK: - Save Recipe

    func saveRecipe() async -> Bool {
        guard isValid else {
            errorMessage = "Please fill in the title and at least one ingredient"
            return false
        }

        isSaving = true
        errorMessage = nil

        defer {
            isSaving = false
        }

        do {
            var recipe = buildPreviewRecipe()

            // Upload photos if any
            if !photoImages.isEmpty {
                let photoUrls = try await recipeService.uploadRecipeImages(photoImages, recipeId: recipe.id)
                recipe = UserRecipe(
                    id: recipe.id,
                    userId: recipe.userId,
                    createdAt: recipe.createdAt,
                    updatedAt: recipe.updatedAt,
                    title: recipe.title,
                    description: recipe.description,
                    imageUrl: photoUrls.first,
                    prepTimeMinutes: recipe.prepTimeMinutes,
                    cookTimeMinutes: recipe.cookTimeMinutes,
                    totalTimeMinutes: recipe.totalTimeMinutes,
                    servings: recipe.servings,
                    servingsText: recipe.servingsText,
                    ingredients: recipe.ingredients,
                    instructions: recipe.instructions,
                    cuisines: recipe.cuisines,
                    dishTypes: recipe.dishTypes,
                    notes: recipe.notes,
                    sourceUrl: recipe.sourceUrl,
                    sourceName: recipe.sourceName,
                    photos: photoUrls
                )
            }

            _ = try await recipeService.createRecipe(recipe)
            savedSuccessfully = true
            clearForm()
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to save recipe: \(error)")
            return false
        }
    }

    /// Save recipe from RecipeDetail (used when recipe was edited in preview)
    func saveRecipe(from recipeDetail: RecipeDetail, photos: [UIImage] = []) async -> Bool {
        isSaving = true
        errorMessage = nil

        defer {
            isSaving = false
        }

        do {
            // Upload any new photos (only use passed photos, not ViewModel's photos which may be stale)
            var imageUrls = recipeDetail.images
            // Filter out any potentially corrupted photos
            let validPhotos = photos.filter { $0.size.width > 0 && $0.size.height > 0 }
            if !validPhotos.isEmpty && validPhotos.count < 50 {
                let recipeId = UUID()
                let newPhotoUrls = try await recipeService.uploadRecipeImages(validPhotos, recipeId: recipeId)
                imageUrls.append(contentsOf: newPhotoUrls)
            }

            // Create updated RecipeDetail with uploaded images
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
                sourceUrl: recipeDetail.sourceUrl,
                sourceName: recipeDetail.sourceName
            )

            _ = try await RecipeService.shared.saveRecipeDetail(finalRecipeDetail)
            savedSuccessfully = true
            clearForm()
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to save recipe: \(error)")
            return false
        }
    }

    // MARK: - Convert to RecipeDetail for Preview

    func toRecipeDetail() -> RecipeDetail {
        // Calculate total time
        let totalTime = totalTimeMinutes ?? 0
        let durationText = totalTime > 0 ? "\(totalTime) mins" : "N/A"

        // Preserve original image URLs (for edit mode)
        // New photos from camera will be uploaded when saved
        let imageUrls = originalImageUrls

        return RecipeDetail(
            title: title.trimmingCharacters(in: .whitespaces),
            duration: durationText,
            ingredientsCount: "\(ingredientsList.count) ingredients",
            description: description.isEmpty ? "No description" : description.trimmingCharacters(in: .whitespaces),
            servings: servings.isEmpty ? "2" : servings,
            prepTime: prepTime.isEmpty ? "0" : prepTime,
            cookTime: cookTime.isEmpty ? "0" : cookTime,
            ingredients: ingredientsList,
            instructions: instructionsList,
            notes: notes.trimmingCharacters(in: .whitespaces),
            images: imageUrls,
            sourceUrl: nil,
            sourceName: nil
        )
    }

    // MARK: - Initialize from RecipeDetail (for edit mode)

    func initializeFrom(_ recipe: RecipeDetail) {
        title = recipe.title
        description = recipe.description == "No description" ? "" : recipe.description
        ingredientsText = recipe.ingredients.joined(separator: "\n")
        instructionsText = recipe.instructions.joined(separator: "\n")
        servings = recipe.servings
        prepTime = recipe.prepTime == "0" ? "" : recipe.prepTime
        cookTime = recipe.cookTime == "0" ? "" : recipe.cookTime
        notes = recipe.notes == "Enjoy this delicious recipe!" ? "" : recipe.notes
        // Preserve original image URLs for edit mode
        originalImageUrls = recipe.images
    }

    // MARK: - Reset Form (for "Add More Recipes")

    func reset() {
        title = ""
        description = ""
        ingredientsText = ""
        instructionsText = ""
        prepTime = ""
        cookTime = ""
        servings = ""
        notes = ""
        selectedPhotos = []
        photoImages = []
        originalImageUrls = []
        errorMessage = nil
        showingPreview = false
        savedSuccessfully = false
    }

    // MARK: - Clear Form

    func clearForm() {
        reset()
    }
}
