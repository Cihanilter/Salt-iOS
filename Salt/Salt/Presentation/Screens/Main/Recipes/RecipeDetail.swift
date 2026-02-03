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
            images: [displayImageUrl].filter { !$0.isEmpty }
        )
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
            images: Array(recipe.images)
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
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var isDeleting = false
    @State private var pendingPhotoImages: [UIImage] = []  // New photos added in edit mode (for display only)
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

    private var isBookmarked: Bool {
        guard let id = recipeId else { return false }
        return bookmarkManager.isBookmarked(id)
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
                        } : nil
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
                            ingredientsCount: recipe.ingredientsCount
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
                            servings: recipe.servings,
                            prepTime: recipe.prepTime,
                            cookTime: recipe.cookTime
                        )

                        // Ingredients
                        IngredientsSection(ingredients: recipe.ingredients)

                        // Instructions
                        InstructionsSection(instructions: recipe.instructions)

                        // Notes & Tips - hidden for now (no notes data in database)
                        // NotesSection(notes: recipe.notes)

                        // Preview mode buttons
                        if mode == .preview && !showSavedHeader {
                            previewButtons
                                .padding(.top, 16)
                        }
                    }
                    .padding(.horizontal)
                    .offset(y: -40)
                }
                .padding(.bottom, 30)
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
        .onDisappear {
            // Clean up storage when view disappears (back button, etc.)
            PendingSaveDataStorage.shared.clear()
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

    // MARK: - Preview Buttons (Edit + Save)

    private var previewButtons: some View {
        HStack(spacing: 20) {
            // Edit button - opens sheet
            Button(action: {
                showingEditSheet = true
            }) {
                Text("Edit")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundColor(Color("OrangeRed"))
            }

            // Save button
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
                    Text("Save")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color("Orange"))
                .cornerRadius(10)
            }
            .disabled(isSaving)
        }
        .frame(maxWidth: .infinity)
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

    private var totalImageCount: Int {
        images.count + pendingImages.count
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

                    // Menu button (for user recipes - Delete)
                    if showMenuButton, let onDelete = onDelete {
                        Menu {
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
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

struct TimeInfoSection: View {
    let servings: String
    let prepTime: String
    let cookTime: String

    // Extract just the number from servings string
    private var servingsNumber: String {
        let text = servings.trimmingCharacters(in: .whitespaces)

        // Extract leading digits
        var numberPart = ""
        for char in text {
            if char.isNumber {
                numberPart.append(char)
            } else if !numberPart.isEmpty {
                break
            }
        }

        return numberPart.isEmpty ? "2" : numberPart
    }

    var body: some View {
        HStack(spacing: 25) {
            ServingsInfoItem(number: servingsNumber)
            TimeInfoItem(value: prepTime, label: "Prep time")
            TimeInfoItem(value: cookTime, label: "Cook time")
        }
    }
}

struct ServingsInfoItem: View {
    let number: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color("LightGrayishPink"))
                    .frame(width: 57, height: 57)

                Text(number)
                    .font(.custom("Playfair9pt-Regular", size: 18))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            Text("Servings")
                .font(.custom("OpenSans-Regular", size: 14))
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

// MARK: - Ingredients Section

struct IngredientsSection: View {
    let ingredients: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ingredients")
                .font(.custom("Playfair9pt-SemiBold", size: 22))
            
            VStack(alignment: .leading, spacing: 5) {
                ForEach(ingredients, id: \.self) { ingredient in
                    Text(ingredient)
                        .font(.custom("OpenSans-Regular", size: 16))
                }
            }
        }
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
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Notes & Tips")
                .font(.custom("Playfair9pt-SemiBold", size: 22))
            
            Text(notes)
                .font(.custom("OpenSans-Regular", size: 14))
        }
        .padding(.horizontal, 20)
        .frame(width: 366, height: 115)
        .background(Color("PeachCream"))
        .cornerRadius(25)
        .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 4)
        .frame(maxWidth: .infinity) 
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
            ]
        )
    )
}
