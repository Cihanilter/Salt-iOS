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

/// One ingredient in the step-by-step form, saved as a single line ("2 cups flour")
struct IngredientRow: Identifiable, Equatable {
    let id = UUID()
    var amount = ""
    var unit = ""
    var name = ""

    init(amount: String = "", unit: String = "", name: String = "") {
        self.amount = amount
        self.unit = unit
        self.name = name
    }

    /// Splits a saved line back into amount, unit and name for editing
    init(line: String) {
        let parts = IngredientScaler.parts(of: line)
        self.init(amount: parts.amount, unit: parts.unit, name: parts.name)
    }

    var line: String {
        [amount, unit, name]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// One numbered step in the step-by-step form
struct InstructionStep: Identifiable, Equatable {
    let id = UUID()
    var text = ""
}

@MainActor
class CreateRecipeViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var title = ""
    @Published var description = ""
    @Published var ingredientRows: [IngredientRow] = [IngredientRow()]
    @Published var instructionSteps: [InstructionStep] = [InstructionStep()]
    @Published var prepTime = ""
    @Published var cookTime = ""
    @Published var servings = ""
    @Published var notes = ""

    @Published var selectedPhotos: [PhotosPickerItem] = []
    @Published var photoImages: [UIImage] = []

    // Original image URLs (for edit mode - preserves existing images)
    @Published var originalImageUrls: [String] = []

    // Edit mode: kept so editing doesn't drop the source link, and servings text like
    // "Makes 12 cookies" survives when the servings count isn't changed
    private var originalSource: (url: String?, name: String?) = (nil, nil)
    private var originalServings: (number: String, text: String)?

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
        !ingredientsList.isEmpty &&
        !instructionsList.isEmpty
    }

    var ingredientsList: [String] {
        ingredientRows.map(\.line).filter { !$0.isEmpty }
    }

    var instructionsList: [String] {
        instructionSteps
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Ingredient & Step Rows

    /// Adds an empty ingredient row and returns its id so the view can focus it
    @discardableResult
    func addIngredient(after id: IngredientRow.ID? = nil) -> IngredientRow.ID {
        let row = IngredientRow()
        if let id, let index = ingredientRows.firstIndex(where: { $0.id == id }) {
            ingredientRows.insert(row, at: index + 1)
        } else {
            ingredientRows.append(row)
        }
        return row.id
    }

    /// The form always keeps one row to type into
    func removeIngredient(_ id: IngredientRow.ID) {
        ingredientRows.removeAll { $0.id == id }
        if ingredientRows.isEmpty { ingredientRows = [IngredientRow()] }
    }

    @discardableResult
    func addStep(after id: InstructionStep.ID? = nil) -> InstructionStep.ID {
        let step = InstructionStep()
        if let id, let index = instructionSteps.firstIndex(where: { $0.id == id }) {
            instructionSteps.insert(step, at: index + 1)
        } else {
            instructionSteps.append(step)
        }
        return step.id
    }

    func removeStep(_ id: InstructionStep.ID) {
        instructionSteps.removeAll { $0.id == id }
        if instructionSteps.isEmpty { instructionSteps = [InstructionStep()] }
    }

    /// A name with line breaks (a pasted list, or Return pressed) becomes one row per line.
    /// Returns the last new row so the view can move the cursor there.
    func splitMultilineIngredients() -> IngredientRow.ID? {
        guard let index = ingredientRows.firstIndex(where: { $0.name.contains(where: \.isNewline) }) else { return nil }

        let lines = ingredientRows[index].name.components(separatedBy: .newlines)
        let first = lines[0].trimmingCharacters(in: .whitespaces)
        let pasted = lines.dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // A whole pasted line in an empty row is split into its amount, unit and name
        if ingredientRows[index].amount.isEmpty && ingredientRows[index].unit.isEmpty {
            let parts = IngredientScaler.parts(of: first)
            ingredientRows[index].amount = parts.amount
            ingredientRows[index].unit = parts.unit
            ingredientRows[index].name = parts.name
        } else {
            ingredientRows[index].name = first
        }

        // Return on its own adds an empty row; pasted lines add one row each
        let newRows = pasted.isEmpty ? [IngredientRow()] : pasted.map(IngredientRow.init(line:))
        ingredientRows.insert(contentsOf: newRows, at: index + 1)
        return newRows.last?.id
    }

    /// Same for steps: Return starts the next step, a pasted list becomes one step per line
    func splitMultilineSteps() -> InstructionStep.ID? {
        guard let index = instructionSteps.firstIndex(where: { $0.text.contains(where: \.isNewline) }) else { return nil }

        let lines = instructionSteps[index].text.components(separatedBy: .newlines)
        let pasted = lines.dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        instructionSteps[index].text = lines[0].trimmingCharacters(in: .whitespaces)
        let newSteps = pasted.isEmpty ? [InstructionStep()] : pasted.map { InstructionStep(text: $0) }
        instructionSteps.insert(contentsOf: newSteps, at: index + 1)
        return newSteps.last?.id
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
            errorMessage = "Please fill in the title, at least one ingredient and one step"
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
            Analytics.log(.recipeCreated, ["photos": recipe.photos?.count ?? 0])
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
            Analytics.log(.recipeCreated, ["photos": imageUrls.count])
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

        let servingsText: String
        if let originalServings, servings == originalServings.number {
            servingsText = originalServings.text
        } else {
            servingsText = servings.isEmpty ? "2" : servings
        }

        return RecipeDetail(
            title: title.trimmingCharacters(in: .whitespaces),
            duration: durationText,
            ingredientsCount: "\(ingredientsList.count) ingredients",
            description: description.isEmpty ? "No description" : description.trimmingCharacters(in: .whitespaces),
            servings: servingsText,
            prepTime: prepTime.isEmpty ? "0" : prepTime,
            cookTime: cookTime.isEmpty ? "0" : cookTime,
            ingredients: ingredientsList,
            instructions: instructionsList,
            notes: notes.trimmingCharacters(in: .whitespaces),
            images: imageUrls,
            sourceUrl: originalSource.url,
            sourceName: originalSource.name
        )
    }

    // MARK: - Initialize from RecipeDetail (for edit mode)

    func initializeFrom(_ recipe: RecipeDetail) {
        title = recipe.title
        let descriptionPlaceholders = ["No description", "No description available"]
        description = descriptionPlaceholders.contains(recipe.description) ? "" : recipe.description
        let rows = recipe.ingredients.map(IngredientRow.init(line:))
        ingredientRows = rows.isEmpty ? [IngredientRow()] : rows
        let steps = recipe.instructions.map { InstructionStep(text: $0) }
        instructionSteps = steps.isEmpty ? [InstructionStep()] : steps

        // The servings stepper works with a plain number ("4 servings" -> "4")
        let servingsNumber = recipe.servings
            .split(whereSeparator: { $0.wholeNumberValue == nil })
            .lazy
            .compactMap { Int($0) }
            .first
            .map(String.init) ?? ""
        servings = servingsNumber
        originalServings = recipe.servings == "N/A" ? nil : (servingsNumber, recipe.servings)
        originalSource = (recipe.sourceUrl, recipe.sourceName)
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
        ingredientRows = [IngredientRow()]
        instructionSteps = [InstructionStep()]
        prepTime = ""
        cookTime = ""
        servings = ""
        notes = ""
        selectedPhotos = []
        photoImages = []
        originalImageUrls = []
        originalSource = (nil, nil)
        originalServings = nil
        errorMessage = nil
        showingPreview = false
        savedSuccessfully = false
    }

    // MARK: - Clear Form

    func clearForm() {
        reset()
    }
}
