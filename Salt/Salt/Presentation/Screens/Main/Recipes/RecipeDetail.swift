//
//  RecipeDetail.swift
//  Salt
//


import SwiftUI

// MARK: - Recipe Detail Model

struct RecipeDetail {
    let title: String
    let duration: String
    let ingredientsCount: String
    let description: String
    let servings: String
    let prepTime: String
    let cookTime: String
    let ingredients: [String]
    let instructions: [String]
    let notes: String
    let images: [String]
    let sourceUrl: String?
    let sourceName: String?
    var nutrition: NutritionInfo? = nil  // Per serving
    var nutritionEstimated = false       // true when AI-estimated (user recipes) rather than from the source website
}

// MARK: - Recipe to RecipeDetail Conversion

extension Recipe {
    func toRecipeDetail() -> RecipeDetail {
        // Handle optional servings
        let servingsDisplayText: String
        if let text = servingsText, !text.isEmpty {
            servingsDisplayText = text
        } else if let count = servings {
            servingsDisplayText = "\(count) servings"
        } else {
            servingsDisplayText = "N/A"
        }

        // Format prep/cook time display
        let prepDisplay = prepTimeMinutes.map { "\($0)" } ?? "0"
        let cookDisplay = cookTimeMinutes.map { "\($0)" } ?? "0"

        // Notes field - empty for now (no notes data in database)
        let notesText = ""

        return RecipeDetail(
            title: title,
            duration: durationText,
            ingredientsCount: "\(ingredientCount) ingredients",
            description: description ?? "No description available",
            servings: servingsDisplayText,
            prepTime: prepDisplay,
            cookTime: cookDisplay,
            ingredients: ingredients,  // Already [String] from database
            instructions: instructions,  // Already [String] from database
            notes: notesText,
            images: [displayImageUrl].filter { !$0.isEmpty },
            sourceUrl: sourceUrl,
            sourceName: sourceName,
            nutrition: nutrition
        )
    }
}

// MARK: - Sharing

extension RecipeDetail {
    /// The recipe as plain text for the share sheet (Messages, WhatsApp, Notes, Mail, ...):
    /// title, servings and time, ingredients as shown in the app (amount first, in sections),
    /// numbered steps, and the original recipe's link.
    var shareText: String {
        var parts: [String] = [title]

        let servingsCount = IngredientScaler.baseServings(from: servings)
        let summary = [servingsCount.map { "Serves \($0)" }, duration.isEmpty ? nil : duration]
            .compactMap { $0 }
            .joined(separator: " · ")
        if !summary.isEmpty { parts.append(summary) }

        if !ingredients.isEmpty {
            var lines = ["Ingredients"]
            for section in IngredientScaler.sections(from: ingredients) {
                if let heading = section.heading { lines.append("\n\(heading)") }
                lines += section.lines.map { "• " + IngredientScaler.display($0) }
            }
            parts.append(lines.joined(separator: "\n"))
        }

        let steps = instructions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !steps.isEmpty {
            let numbered = steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
            parts.append((["Instructions"] + numbered).joined(separator: "\n"))
        }

        if let sourceUrl, !sourceUrl.isEmpty {
            parts.append("Original recipe: \(sourceUrl)")
        }
        parts.append("Shared from Salt")
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Recipe Detail View Mode

enum RecipeDetailMode {
    case regular           // Viewing recipe from DB
    case preview           // Preview after creating/importing (Edit + Save buttons)
}

// MARK: - Pending Save Data Storage (to avoid passing data through closures)

class PendingSaveDataStorage {
    static let shared = PendingSaveDataStorage()
    private init() {}

    var recipeDetail: RecipeDetail?
    var photos: [UIImage] = []

    func store(recipe: RecipeDetail, photos: [UIImage]) {
        // Deep copy recipe
        self.recipeDetail = RecipeDetail(
            title: recipe.title,
            duration: recipe.duration,
            ingredientsCount: recipe.ingredientsCount,
            description: recipe.description,
            servings: recipe.servings,
            prepTime: recipe.prepTime,
            cookTime: recipe.cookTime,
            ingredients: Array(recipe.ingredients),
            instructions: Array(recipe.instructions),
            notes: recipe.notes,
            images: Array(recipe.images),
            sourceUrl: recipe.sourceUrl,
            sourceName: recipe.sourceName
        )

        // Deep copy photos to avoid memory issues
        self.photos = photos.compactMap { image in
            guard let data = image.jpegData(compressionQuality: 0.8),
                  let copy = UIImage(data: data) else {
                return nil
            }
            return copy
        }
    }

    func retrieve() -> (recipe: RecipeDetail?, photos: [UIImage]) {
        let result = (recipeDetail, photos)
        recipeDetail = nil
        photos = []
        return result
    }

    func clear() {
        recipeDetail = nil
        photos = []
    }
}

// MARK: - Recipe Detail View

struct RecipeDetailView: View {
    @State private var recipe: RecipeDetail
    var recipeId: UUID? = nil
    var userRecipeId: UUID? = nil  // For user-created/imported recipes (enables delete)
    var mode: RecipeDetailMode = .regular

    // Callbacks for preview mode - no parameters, data is in PendingSaveDataStorage
    var onSave: (() async -> Bool)? = nil

    // Callbacks for saved state
    var onAddMoreRecipes: (() -> Void)? = nil
    var onGoToMyRecipes: (() -> Void)? = nil

    @State private var currentImageIndex = 0
    @State private var isSaving = false
    @State private var showSavedHeader = false
    @State private var hasBeenSaved = false  // Track if recipe was saved (persists after closing saved header)
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var isDeleting = false
    @State private var pendingPhotoImages: [UIImage] = []  // New photos added in edit mode (for display only)
    @State private var isCookingModeOn = false  // Keeps the screen awake while viewing the recipe
    @State private var isEstimatingNutrition = false  // AI estimate running for a saved recipe opened without nutrition
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var bookmarkManager = BookmarkManager.shared

    // Custom init to handle @State initialization
    init(
        recipe: RecipeDetail,
        recipeId: UUID? = nil,
        userRecipeId: UUID? = nil,
        mode: RecipeDetailMode = .regular,
        pendingPhotos: [UIImage] = [],
        onSave: (() async -> Bool)? = nil,
        onAddMoreRecipes: (() -> Void)? = nil,
        onGoToMyRecipes: (() -> Void)? = nil
    ) {
        self._recipe = State(initialValue: recipe)
        self.recipeId = recipeId
        self.userRecipeId = userRecipeId
        self.mode = mode
        self._pendingPhotoImages = State(initialValue: pendingPhotos)
        self.onSave = onSave
        self.onAddMoreRecipes = onAddMoreRecipes
        self.onGoToMyRecipes = onGoToMyRecipes
    }

    /// Reviewing a created/imported recipe that hasn't been saved yet
    private var isUnsavedPreview: Bool {
        mode == .preview && !hasBeenSaved
    }

    private var isBookmarked: Bool {
        guard let id = recipeId else { return false }
        return bookmarkManager.isBookmarked(id)
    }

    /// Message for the blurred Nutrition placeholder while there are no values yet, and whether
    /// it's in progress (spinner); nil hides the placeholder. Tells users nutrition is coming
    /// for their own recipes. "Estimated" is left to the real values' label.
    private var nutritionPlaceholder: (message: String, inProgress: Bool)? {
        guard recipe.nutrition == nil, RecipeService.canEstimateNutrition(from: recipe.ingredients) else { return nil }
        if isUnsavedPreview {
            return ("Save this recipe to see its nutrition in My Recipes.", false)
        }
        if mode == .preview {
            // Just saved from this screen; the estimate runs in the background
            return ("Getting nutrition… You'll find it in My Recipes.", true)
        }
        if isEstimatingNutrition {
            return ("Getting nutrition…", true)
        }
        return nil
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Image Carousel
                    ImageCarousel(
                        images: recipe.images,
                        pendingImages: pendingPhotoImages,
                        currentIndex: $currentImageIndex,
                        onBack: { dismiss() },
                        isBookmarked: isBookmarked,
                        onBookmarkTap: recipeId != nil ? {
                            Task {
                                await bookmarkManager.toggleBookmark(for: recipeId!)
                            }
                        } : nil,
                        showMenuButton: userRecipeId != nil,
                        onDelete: userRecipeId != nil ? {
                            showingDeleteAlert = true
                        } : nil,
                        onEdit: isUnsavedPreview ? { showingEditSheet = true } : nil,
                        // Discards the unsaved recipe and goes back to the form / link field
                        onCancel: isUnsavedPreview ? { dismiss() } : nil,
                        // The unsaved preview keeps its menu to Edit / Cancel
                        shareTitle: recipe.title,
                        shareText: isUnsavedPreview ? nil : recipe.shareText
                    )
                    .id("top")  // Anchor for scrolling to top

                    // Info Card - shows saved state or normal state
                    if showSavedHeader {
                        SavedRecipeInfoCard(
                            onClose: {
                                withAnimation {
                                    showSavedHeader = false
                                }
                            },
                            onAddMoreRecipes: onAddMoreRecipes,
                            onGoToMyRecipes: onGoToMyRecipes
                        )
                        .padding(.horizontal)
                        .offset(y: -60)
                    } else {
                        RecipeInfoCard(
                            title: recipe.title,
                            duration: recipe.duration,
                            ingredientsCount: recipe.ingredientsCount,
                            sourceUrl: recipe.sourceUrl
                        )
                        .padding(.horizontal)
                        .offset(y: -60)
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 20) {
                        // Description
                        DescriptionSection(text: recipe.description)

                        // Time Info
                        TimeInfoSection(
                            prepTime: recipe.prepTime,
                            cookTime: recipe.cookTime
                        )

                        // Cooking Mode (keep screen awake)
                        CookingModeToggle(isOn: $isCookingModeOn)

                        // Ingredients
                        IngredientsSection(ingredients: recipe.ingredients, servings: recipe.servings)

                        // Instructions
                        InstructionsSection(instructions: recipe.instructions)

                        // Notes & Tips section (shown for imported recipes OR when notes exist).
                        // The source link now lives in the info card at the top.
                        if recipe.sourceUrl != nil || !recipe.notes.isEmpty {
                            NotesSection(notes: recipe.notes)
                        }

                        // Nutrition (per serving), at the very bottom; hidden when there's no data
                        // and no estimate coming
                        if let nutrition = recipe.nutrition, NutritionSection.hasValues(nutrition) {
                            NutritionSection(nutrition: nutrition, isEstimated: recipe.nutritionEstimated)
                        } else if let placeholder = nutritionPlaceholder {
                            NutritionSection(
                                nutrition: NutritionSection.placeholderValues,
                                placeholderMessage: placeholder.message,
                                placeholderInProgress: placeholder.inProgress
                            )
                        }
                    }
                    .padding(.horizontal)
                    .offset(y: -40)
                }
                .padding(.bottom, 30)
            }
            .safeAreaInset(edge: .bottom) {
                // Pinned so Save is always visible while reviewing; users missed it at the end of the content
                if isUnsavedPreview {
                    previewButtons
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onChange(of: showSavedHeader) { _, saved in
                if saved {
                    // Scroll to top when recipe is saved
                    withAnimation {
                        scrollProxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // Hide the tab bar while reviewing a new recipe so the Save footer is the only bottom action
        .toolbar(isUnsavedPreview ? .hidden : .automatic, for: .tabBar)
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $showingEditSheet) {
            NavigationStack {
                CreateRecipeView(
                    initialRecipe: recipe,
                    isEditMode: true,
                    onUpdate: { updatedRecipe, newPhotos in
                        // Update recipe
                        recipe = updatedRecipe
                        // Store photos locally for display in carousel
                        pendingPhotoImages = newPhotos
                        showingEditSheet = false
                    }
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingEditSheet = false
                        }
                    }
                }
            }
        }
        .task {
            // User recipes without nutrition get an estimate when opened (older recipes, or one
            // just saved whose estimate is still running) and show it as soon as it arrives
            guard let userRecipeId, recipe.nutrition == nil,
                  RecipeService.canEstimateNutrition(from: recipe.ingredients) else { return }

            isEstimatingNutrition = true
            let nutrition = await RecipeService.shared.estimateNutrition(
                recipeId: userRecipeId,
                title: recipe.title,
                servings: recipe.servings == "N/A" ? nil : recipe.servings,
                ingredients: recipe.ingredients
            )
            withAnimation {
                if let nutrition {
                    recipe.nutrition = nutrition
                    recipe.nutritionEstimated = true
                }
                isEstimatingNutrition = false
            }
        }
        .onChange(of: isCookingModeOn) { _, isOn in
            UIApplication.shared.isIdleTimerDisabled = isOn
        }
        .onDisappear {
            // Clean up storage when view disappears (back button, etc.)
            PendingSaveDataStorage.shared.clear()
            // Restore normal auto-lock when leaving the recipe
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .alert("Delete Recipe", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteUserRecipe()
                }
            }
        } message: {
            Text("Are you sure you want to delete this recipe? This action cannot be undone.")
        }
    }

    // MARK: - Delete User Recipe

    private func deleteUserRecipe() async {
        guard let recipeId = userRecipeId else { return }

        isDeleting = true
        do {
            try await MyRecipesViewModel.shared.deleteRecipe(id: recipeId)
            await MainActor.run {
                dismiss()
            }
        } catch {
            print("Failed to delete recipe: \(error)")
        }
        isDeleting = false
    }

    // MARK: - Preview Footer (Save)

    /// Bottom bar shown while reviewing a created/imported recipe that hasn't been saved yet.
    /// Edit and Cancel live in the top-right menu so Save is the single primary action.
    private var previewButtons: some View {
        Group {
            Button(action: {
                // Store ALL data in shared storage BEFORE async call
                // This completely avoids passing any data through closures
                PendingSaveDataStorage.shared.store(recipe: recipe, photos: pendingPhotoImages)

                Task {
                    isSaving = true
                    if let save = onSave {
                        let success = await save()
                        if success {
                            withAnimation {
                                hasBeenSaved = true
                                showSavedHeader = true
                            }
                        }
                    }
                    isSaving = false
                }
            }) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    }
                    Text("Save Recipe")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color("Orange"))
                .cornerRadius(10)
            }
            .disabled(isSaving)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            Color(.systemBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 6, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Saved Recipe Info Card (replaces normal card after save)

struct SavedRecipeInfoCard: View {
    var onClose: (() -> Void)?
    var onAddMoreRecipes: (() -> Void)?
    var onGoToMyRecipes: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            // Close button
            HStack {
                Spacer()
                Button(action: {
                    onClose?()
                }) {
                    Image("closeIcon")
                        .resizable()
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.trailing, 8)
            .padding(.top, 4)

            // Success message
            HStack(spacing: 6) {
                Text("Saved to My Recipes")
                    .font(.custom("Playfair9pt-Bold", size: 22))
                    .foregroundColor(Color("OrangeRed"))
                Image("done")
                    .resizable()
                    .frame(width: 25, height: 25)
            }

            // Add More Recipes button
            Button(action: {
                onAddMoreRecipes?()
            }) {
                HStack(spacing: 6) {
                    Text("Add More Recipes")
                        .font(.custom("Playfair9pt-SemiBold", size: 18))
                        .foregroundColor(.primary)
                    ZStack {
                        Circle()
                            .fill(Color("Orange"))
                            .frame(width: 20, height: 20)
                        Image("addNewRecipeIcon")
                            .resizable()
                            .frame(width: 30, height: 30)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white)
                .cornerRadius(25)
            }

            // Go to My Recipes button
            Button(action: {
                onGoToMyRecipes?()
            }) {
                Text("Go to My Recipes")
                    .font(.custom("Playfair9pt-SemiBold", size: 18))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .cornerRadius(25)

            }
            .padding(.bottom, 8)
        }
        .frame(width: 322)
        .padding(.all, 24)
        .background(Color("PeachCream"))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 4)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Image Carousel

struct ImageCarousel: View {
    let images: [String]
    var pendingImages: [UIImage] = []  // New photos not yet uploaded
    @Binding var currentIndex: Int
    let onBack: () -> Void
    var isBookmarked: Bool = false
    var onBookmarkTap: (() -> Void)? = nil
    var showMenuButton: Bool = false
    var onDelete: (() -> Void)? = nil
    // Preview mode (unsaved recipe) menu actions
    var onEdit: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    // Recipe as text for the share sheet; nil hides Share
    var shareTitle: String = ""
    var shareText: String? = nil

    private var totalImageCount: Int {
        images.count + pendingImages.count
    }

    private var hasMenuActions: Bool {
        shareText != nil || (showMenuButton && onDelete != nil) || onEdit != nil || onCancel != nil
    }

    var body: some View {
        ZStack {
            // Placeholder when no images
            if totalImageCount == 0 {
                Rectangle()
                    .fill(Color("LightGrayishPink"))
                    .frame(height: 280)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 48))
                                .foregroundColor(Color("GraniteGray"))
                            Text("No photo")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundColor(Color("GraniteGray"))
                        }
                    )
            } else {
                // Images
                TabView(selection: $currentIndex) {
                    // URL-based images
                    ForEach(0..<images.count, id: \.self) { index in
                        CachedAsyncImage(url: URL(string: images[index])) { phase in
                            switch phase {
                            case .empty:
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .overlay(ProgressView())
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundColor(.gray)
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .tag(index)
                    }
                    // Pending UIImage photos (not yet uploaded)
                    ForEach(0..<pendingImages.count, id: \.self) { index in
                        Image(uiImage: pendingImages[index])
                            .resizable()
                            .scaledToFill()
                            .tag(images.count + index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 280)
            }

            // Top buttons (Back + Bookmark)
            VStack {
                HStack {
                    Button(action: onBack) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 40, height: 40)

                            Image("backIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                        }
                    }
                    .padding(.leading, 16)

                    Spacer()

                    // Menu button (all saved recipes: Share; user recipes: Delete; unsaved preview: Edit / Cancel)
                    if hasMenuActions {
                        Menu {
                            if let shareText {
                                ShareLink(
                                    item: shareText,
                                    subject: Text(shareTitle),
                                    preview: SharePreview(shareTitle)
                                ) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                            }
                            if let onEdit {
                                Button(action: onEdit) {
                                    Label("Edit", systemImage: "pencil")
                                }
                            }
                            if let onCancel {
                                Button(role: .destructive, action: onCancel) {
                                    Label("Cancel", systemImage: "xmark")
                                }
                            }
                            if showMenuButton, let onDelete {
                                Button(role: .destructive, action: onDelete) {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.5))
                                    .frame(width: 40, height: 40)

                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                        }
                        .padding(.trailing, 16)
                    }

                    // Bookmark button
//                    if let onBookmarkTap = onBookmarkTap {
//                        Button(action: onBookmarkTap) {
//                            ZStack {
//                                Circle()
//                                    .fill(Color.white.opacity(0.5))
//                                    .frame(width: 32, height: 32)
//
//                                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
//                                    .font(.system(size: 14))
//                                    .foregroundColor(isBookmarked ? Color("OrangeRed") : .black)
//                            }
//                        }
//                        .padding(.trailing, 16)
//                    }
                }
                .padding(.top, 50)

                Spacer()
            }
            
            // Next Button with gradient (right side)
            if totalImageCount > 1 {
                HStack {
                    Spacer()

                    ZStack(alignment: .trailing) {
                        // Gradient
                        LinearGradient(
                            stops: [
                                .init(color: Color("Nero"), location: -3),
                                .init(color: Color.clear, location: 1)
                            ],
                            startPoint: .trailing,
                            endPoint: .leading
                        )
                        .frame(width: 50, height: 280)

                        // Next Button
                        Button(action: {
                            withAnimation {
                                currentIndex = (currentIndex + 1) % totalImageCount
                            }
                        }) {
                            Image("nextIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                        }
                        .padding(.trailing, 16)
                    }
                }
            }
        }
        .frame(height: 280)
    }
}

// MARK: - Recipe Info Card

struct RecipeInfoCard: View {
    let title: String
    let duration: String
    let ingredientsCount: String
    var sourceUrl: String? = nil

    /// Link to the page the recipe was imported from, if any
    private var sourceLink: URL? {
        guard let sourceUrl, !sourceUrl.isEmpty else { return nil }
        return URL(string: sourceUrl)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.custom("Playfair9pt-SemiBold", size: 18))
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            HStack(spacing: 66) {
                HStack(spacing: 3) {
                    Image("timerIcon")
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 24, height: 24)
                        .foregroundColor(Color("SoftPink"))
                    
                    Text(duration)
                        .font(.custom("Playfair9pt-Regular", size: 16))
                }
                
                HStack(spacing: 3) {
                    Image("nutritionIcon")
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 24, height: 24)
                        .foregroundColor(Color("SoftPink"))
                    
                    Text(ingredientsCount)
                        .font(.custom("Playfair9pt-Regular", size: 16))
                }
            }

            // Original source for imported recipes; the arrow icon signals it opens a link
            if let sourceLink {
                Link(destination: sourceLink) {
                    HStack(spacing: 4) {
                        Text("Original Recipe")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(Color("OrangeRed"))
                }
            }
        }
        .padding(.vertical, 16)
        .frame(width: 322)
        .background(Color("Alabaster"))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 4)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Description Section

struct DescriptionSection: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Description")
                .font(.custom("Playfair9pt-SemiBold", size: 22))
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 16))
        }
    }
}

// MARK: - Time Info Section

// Servings live in the Ingredients section, where they can be adjusted
struct TimeInfoSection: View {
    let prepTime: String
    let cookTime: String

    var body: some View {
        HStack(spacing: 25) {
            TimeInfoItem(value: prepTime, label: "Prep time")
            TimeInfoItem(value: cookTime, label: "Cook time")
        }
    }
}

struct TimeInfoItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color("LightGrayishPink"))
                    .frame(width: 57, height: 57)

                VStack(spacing: 0) {
                    Text(value)
                        .font(.custom("Playfair9pt-Regular", size: 18))

                    Text("mins")
                        .font(.custom("Playfair9pt-Regular", size: 14))
                }
            }

            Text(label)
                .font(.custom("OpenSans-Regular", size: 14))
        }
    }
}

// MARK: - Cooking Mode Toggle

struct CookingModeToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cooking Mode")
                    .font(.custom("Playfair9pt-SemiBold", size: 18))

                Text("Keep screen awake")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("GraniteGray"))
            }
        }
        .tint(Color("Orange"))
    }
}

// MARK: - Ingredients Section

struct IngredientsSection: View {
    let ingredients: [String]
    let servings: String  // The recipe's servings text, e.g. "4 servings"; scaling starts from it

    @State private var selectedServings: Int?  // nil = the recipe's own servings

    private var baseServings: Int? { IngredientScaler.baseServings(from: servings) }
    private var sections: [IngredientScaler.Section] { IngredientScaler.sections(from: ingredients) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ingredients")
                .font(.custom("Playfair9pt-SemiBold", size: 22))

            // Hidden when the recipe doesn't say how many it serves; there's nothing to scale from
            if let base = baseServings {
                ServingsStepper(
                    servings: selectedServings ?? base,
                    original: base,
                    onChange: { selectedServings = $0 == base ? nil : $0 }
                )
            }

            // Imported recipes can group ingredients (Marinade, Crema, Pico de gallo).
            // Lines can repeat (e.g. "Salt" in two groups), so everything is identified by position.
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 5) {
                        if let heading = section.heading {
                            Text(heading)
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .padding(.bottom, 2)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(Array(section.lines.enumerated()), id: \.offset) { _, ingredient in
                            Text(scaled(ingredient))
                                .font(.custom("OpenSans-Regular", size: 16))
                        }
                    }
                }
            }
        }
        // The recipe was edited (preview mode); start again from its servings
        .onChange(of: servings) { _, _ in
            selectedServings = nil
        }
    }

    /// Amount first ("½ cup milk"), scaled to the selected servings
    private func scaled(_ ingredient: String) -> String {
        guard let base = baseServings, let selected = selectedServings else {
            return IngredientScaler.display(ingredient)
        }
        return IngredientScaler.display(ingredient, scaledBy: Double(selected) / Double(base))
    }
}

/// "−  4 servings  +" control for scaling the ingredient amounts
struct ServingsStepper: View {
    let servings: Int
    let original: Int
    let onChange: (Int) -> Void

    private let range = 1...99

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                stepButton(systemName: "minus", isEnabled: servings > range.lowerBound) {
                    onChange(servings - 1)
                }

                Text(servings == 1 ? "1 serving" : "\(servings) servings")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .monospacedDigit()
                    .frame(minWidth: 96)

                stepButton(systemName: "plus", isEnabled: servings < range.upperBound) {
                    onChange(servings + 1)
                }
            }
            // One adjustable control for VoiceOver (swipe up/down) instead of three elements
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Servings")
            .accessibilityValue("\(servings)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment where servings < range.upperBound: onChange(servings + 1)
                case .decrement where servings > range.lowerBound: onChange(servings - 1)
                default: break
                }
            }

            if servings != original {
                Button("Reset") {
                    onChange(original)
                }
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(Color("Orange"))
                .accessibilityLabel("Reset to \(original) servings")
            }
        }
    }

    private func stepButton(systemName: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color("LightGrayishPink")))
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Instructions Section

struct InstructionsSection: View {
    let instructions: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Instructions")
                .font(.custom("Playfair9pt-SemiBold", size: 22))
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1).")
                            .font(.custom("OpenSans-Regular", size: 16))
                        
                        Text(instruction)
                            .font(.custom("OpenSans-Regular", size: 16))
                    }
                }
            }
        }
    }
}

// MARK: - Notes Section

struct NotesSection: View {
    let notes: String

    private var hasNotes: Bool {
        !notes.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes & Tips")
                .font(.custom("Playfair9pt-SemiBold", size: 22))
                .frame(maxWidth: .infinity, alignment: .center)

            if hasNotes {
                Text(notes)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color("PeachCream"))
        .cornerRadius(25)
        .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 4)
    }
}

// MARK: - Nutrition Section

/// Per-serving nutrition card: calories highlighted, then the main nutrients as rows.
struct NutritionSection: View {
    let nutrition: NutritionInfo
    var isEstimated = false  // AI-estimated values get a label and a short disclaimer
    var placeholderMessage: String? = nil  // When set, the values are blurred sample data under this message
    var placeholderInProgress = false      // Spinner instead of the sparkles icon next to the message

    /// Sample values shown blurred while a recipe's real nutrition isn't available yet
    static let placeholderValues = NutritionInfo(
        type: nil,
        calories: "420 calories",
        carbohydrateContent: "38 g",
        proteinContent: "24 g",
        fatContent: "18 g",
        saturatedFatContent: nil,
        fiberContent: nil,
        sugarContent: "6 g",
        sodiumContent: nil,
        cholesterolContent: nil,
        servingSize: nil
    )

    private struct Row: Identifiable {
        let name: String
        let value: String
        var id: String { name }
    }

    /// Whether there's anything worth showing
    static func hasValues(_ nutrition: NutritionInfo) -> Bool {
        [nutrition.calories, nutrition.carbohydrateContent, nutrition.sugarContent,
         nutrition.proteinContent, nutrition.fatContent]
            .contains { formatAmount($0) != nil }
    }

    // Fiber and sodium are left out: too detailed for a recipe app, and hard to estimate reliably
    private var rows: [Row] {
        let candidates: [(String, String?)] = [
            ("Carbs", nutrition.carbohydrateContent),
            ("Protein", nutrition.proteinContent),
            ("Fat", nutrition.fatContent),
            ("Sugar", nutrition.sugarContent)
        ]
        return candidates.compactMap { name, raw in
            Self.formatAmount(raw).map { Row(name: name, value: $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nutrition")
                    .font(.custom("Playfair9pt-SemiBold", size: 22))
                if isEstimated {
                    Text("Estimated")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundColor(Color("Orange"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color("Orange").opacity(0.12)))
                }
                Spacer()
                Text("Per serving")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("GraniteGray"))
            }

            VStack(spacing: 0) {
                // Calories, highlighted
                if let calories = Self.formatNumber(nutrition.calories) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Calories")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                        Spacer()
                        Text(calories)
                            .font(.custom("OpenSans-SemiBold", size: 28))
                            .foregroundColor(Color("Orange"))
                        Text("cal")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundColor(Color("GraniteGray"))
                    }
                    .padding(.bottom, 12)
                    .accessibilityElement(children: .combine)

                    if !rows.isEmpty {
                        Divider()
                    }
                }

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Text(row.name)
                            .font(.custom("OpenSans-SemiBold", size: 16))
                        Spacer()
                        Text(row.value)
                            .font(.custom("OpenSans-Regular", size: 16))
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)

                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }
            // Sample values are blurred so they read as "something's coming", not as data
            .blur(radius: placeholderMessage == nil ? 0 : 6)
            .accessibilityHidden(placeholderMessage != nil)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(red: 1.0, green: 0.941, blue: 0.855)) // #FFF0DA
            .cornerRadius(25)
            .overlay {
                if let placeholderMessage {
                    placeholderOverlay(placeholderMessage)
                }
            }

            if isEstimated && placeholderMessage == nil {
                Text("Estimated with AI from the ingredients. Values are approximate.")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundColor(Color("GraniteGray"))
            }
        }
    }

    /// Message card centered over the blurred sample values
    private func placeholderOverlay(_ message: String) -> some View {
        HStack(spacing: 10) {
            if placeholderInProgress {
                ProgressView()
                    .tint(Color("Orange"))
            } else {
                Image(systemName: "sparkles")
                    .foregroundColor(Color("Orange"))
            }
            Text(message)
                .font(.custom("OpenSans-SemiBold", size: 15))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground).opacity(0.92))
        )
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }

    // MARK: Formatting

    /// The number in a stored value like "346.6 calories" or "1492.5 mg"
    private static func number(in raw: String?) -> Double? {
        guard let raw,
              let match = raw.range(of: #"\d+([.,]\d+)?"#, options: .regularExpression) else { return nil }
        return Double(raw[match].replacingOccurrences(of: ",", with: "."))
    }

    /// Whole number with thousands separators, e.g. "1,493"
    private static func formatNumber(_ raw: String?) -> String? {
        number(in: raw).map { Int($0.rounded()).formatted() }
    }

    /// Value with its unit, e.g. "23 g", "4.5 g", "1,493 mg". Small gram values keep one decimal.
    static func formatAmount(_ raw: String?) -> String? {
        guard let raw, let value = number(in: raw) else { return nil }
        let unit = raw.lowercased().contains("mg") ? "mg" : (raw.lowercased().contains("calorie") ? "cal" : "g")
        let shown = (unit == "g" && value < 10) ? value.formatted(.number.precision(.fractionLength(0...1)))
                                                : Int(value.rounded()).formatted()
        return "\(shown) \(unit)"
    }
}

// MARK: - Preview

#Preview {
    RecipeDetailView(
        recipe: RecipeDetail(
            title: "Homemade pancakes",
            duration: "25 mins",
            ingredientsCount: "5 ingredients",
            description: "Quick and fluffy pancakes, perfect for busy mornings.",
            servings: "4",
            prepTime: "5",
            cookTime: "10",
            ingredients: [
                "1 cup (125g) all-purpose flour",
                "1 tablespoon sugar",
                "1 teaspoon baking powder",
                "1 cup (240ml) milk",
                "1 large egg"
            ],
            instructions: [
                "In a bowl, mix the flour, sugar, and baking powder.",
                "Add the milk and egg. Stir until smooth.",
                "Heat a non-stick pan over medium heat. Lightly grease if needed.",
                "Pour 1/4 cup of batter into the pan for each pancake. Cook until bubbles form, about 2 minutes.",
                "Flip and cook for 1 more minute, until golden."
            ],
            notes: "Avoid overmixing the batter, a few lumps are okay for fluffier pancakes.",
            images: [
                "https://upload.wikimedia.org/wikipedia/commons/4/43/Pancake.jpg",
                "https://upload.wikimedia.org/wikipedia/commons/a/ae/Plateau_van_zeevruchten.jpg"
            ],
            sourceUrl: "https://www.allrecipes.com/recipe/123/pancakes",
            sourceName: "AllRecipes"
        )
    )
}

