//
//  RecipeDetail.swift
//  Salt
//
//  The recipe page (Figma "Recipe detail — Final"): hero photo with glass top bar
//  (back, Cooking mode, bookmark for Explore recipes, … menu), the beige title card,
//  then Description, Ingredients, Instructions, Notes & tips and Nutrition.
//

import SwiftUI
import PhotosUI
import RevenueCat
import RevenueCatUI

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
            description: description ?? "",
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
    /// What the edit sheet is for
    private enum EditSheet: Identifiable {
        case preview    // Unsaved recipe: only updates this screen, saved later with Save Recipe
        case ownRecipe  // User's own recipe: saves the changes
        case customize  // Explore/saved recipe: saves a copy, the original isn't changed

        var id: Self { self }
    }

    @State private var recipe: RecipeDetail
    // State so the screen can switch to the user's copy after Customize
    @State private var recipeId: UUID?
    @State private var userRecipeId: UUID?  // For user-created/imported recipes (enables edit/delete)
    var mode: RecipeDetailMode = .regular
    /// Shown above the content, e.g. for a recipe pieced together from a video's audio
    var previewNotice: String? = nil
    /// After the user's first saved recipe: offers to put it in a collection (SaveToCollectionPrompt)
    var offersCollectionPrompt = false
    /// Create flow preview: "Edit recipe" and back return to the form (everything kept)
    var editReturnsToForm = false

    // Callbacks for preview mode - no parameters, data is in PendingSaveDataStorage
    var onSave: (() async -> Bool)? = nil
    /// The recipe once `onSave` succeeds; when set, offers to add it to a collection
    var savedRecipeId: (() -> UUID?)? = nil

    // Callbacks for saved state (shared recipe links): show the "Saved to My Recipes" card
    var onAddMoreRecipes: (() -> Void)? = nil
    var onGoToMyRecipes: (() -> Void)? = nil

    @State private var currentImageIndex = 0
    @State private var isSaving = false
    @State private var showSavedHeader = false
    @State private var hasBeenSaved = false  // Track if recipe was saved (persists after closing saved header)
    @State private var editSheet: EditSheet?
    @State private var showingDeleteAlert = false
    @State private var pendingPhotoImages: [UIImage] = []  // New photos added in edit mode (for display only)
    @State private var coverPhotoItem: PhotosPickerItem?
    @State private var isCookingModeOn = false  // Keeps the screen awake while viewing the recipe
    /// The labeled pill is shown for the first 3 times Cooking mode is turned on, then only the icon
    @AppStorage("cookingMode.timesTurnedOn") private var cookingModeUses = 0
    @State private var cookingModeShowsLabel = true
    @State private var didShowCookingToast = false
    @State private var showingCookingPremium = false
    @State private var isEstimatingNutrition = false  // AI estimate running for a saved recipe opened without nutrition
    @State private var isCreatingShareLink = false
    @State private var shareLink: ShareLinkItem?
    @State private var shareErrorMessage: String?
    @State private var collectionTarget: CollectionRecipeRef?
    /// Just-saved recipe for the "Add to a collection?" prompt
    @State private var collectionPromptRef: CollectionRecipeRef?
    @State private var didOfferCollectionPrompt = false
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var bookmarkManager = BookmarkManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    /// Where the paywall was opened from, for analytics and what to do after upgrading
    @State private var paywallSource: PaywallSource?
    /// Default units are set in Profile; the … menu changes them too
    @AppStorage("preferredUnitSystem") private var preferredUnits: UnitSystem?

    private enum PaywallSource: String, Identifiable {
        case nutritionLock = "nutrition_lock"
        case cookingMode = "cooking_mode"
        var id: String { rawValue }
    }

    // Custom init to handle @State initialization
    init(
        recipe: RecipeDetail,
        recipeId: UUID? = nil,
        userRecipeId: UUID? = nil,
        mode: RecipeDetailMode = .regular,
        previewNotice: String? = nil,
        offersCollectionPrompt: Bool = false,
        editReturnsToForm: Bool = false,
        pendingPhotos: [UIImage] = [],
        onSave: (() async -> Bool)? = nil,
        savedRecipeId: (() -> UUID?)? = nil,
        onAddMoreRecipes: (() -> Void)? = nil,
        onGoToMyRecipes: (() -> Void)? = nil
    ) {
        self._recipe = State(initialValue: recipe)
        self._recipeId = State(initialValue: recipeId)
        self._userRecipeId = State(initialValue: userRecipeId)
        self.mode = mode
        self.previewNotice = previewNotice
        self.offersCollectionPrompt = offersCollectionPrompt
        self.editReturnsToForm = editReturnsToForm
        self._pendingPhotoImages = State(initialValue: pendingPhotos)
        self.onSave = onSave
        self.savedRecipeId = savedRecipeId
        self.onAddMoreRecipes = onAddMoreRecipes
        self.onGoToMyRecipes = onGoToMyRecipes
    }

    /// Reviewing a created/imported recipe that hasn't been saved yet
    private var isUnsavedPreview: Bool {
        mode == .preview && !hasBeenSaved
    }

    /// The create flow's preview: back + "Preview" on top, Save / Edit sticky at the bottom
    private var isCreatePreview: Bool {
        isUnsavedPreview && editReturnsToForm
    }

    /// A saved recipe: opened from the database, or a preview that has just been saved
    private var isSavedRecipe: Bool {
        mode == .regular || (hasBeenSaved && userRecipeId != nil)
    }

    /// A recipe from Salt's own catalog (Explore), not yet customized
    private var isExploreRecipe: Bool {
        recipeId != nil && userRecipeId == nil && mode == .regular
    }

    private var isBookmarked: Bool {
        guard let id = recipeId else { return false }
        return bookmarkManager.isBookmarked(id)
    }

    /// Edit in the menu: unsaved previews and the user's own saved recipes
    private var editAction: (() -> Void)? {
        if isUnsavedPreview {
            return { editSheet = .preview }
        }
        if userRecipeId != nil && isSavedRecipe {
            return { editSheet = .ownRecipe }
        }
        return nil
    }

    /// Saved recipes (the user's own and Explore ones) can be shared with a link
    private var canShare: Bool {
        isSavedRecipe && (userRecipeId ?? recipeId) != nil
    }

    /// The recipe as a collection entry; nil for unsaved previews
    private var collectionRef: CollectionRecipeRef? {
        guard isSavedRecipe else { return nil }
        if let userRecipeId { return .own(userRecipeId) }
        if let recipeId { return .explore(recipeId) }
        return nil
    }

    /// Units as the recipe is written, when it has anything to convert
    private var recipeUnits: UnitSystem? {
        UnitConverter.system(of: recipe.ingredients)
    }

    /// Explore recipes are Salt's own catalog: no "Original Recipe" link and no credit line
    private var showsSource: Bool {
        !isExploreRecipe
    }

    /// "@handle · Instagram" or "site.com", only for imported recipes
    private var sourceCredit: String? {
        guard showsSource, let sourceUrl = recipe.sourceUrl, !sourceUrl.isEmpty else { return nil }
        if let platform = SocialPlatform(url: sourceUrl) {
            let handle = Self.handle(in: sourceUrl)
                ?? recipe.sourceName.flatMap { name in
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    // Only a real account name, not the platform or its domain
                    guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("."),
                          trimmed.lowercased() != platform.name.lowercased() else { return nil }
                    return trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
                }
            return handle.map { "\($0) · \(platform.name)" } ?? platform.name
        }
        guard let host = URL(string: sourceUrl)?.host else { return recipe.sourceName }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    /// The account in links like tiktok.com/@name/video/… or youtube.com/@name
    private static func handle(in url: String) -> String? {
        guard let components = URL(string: url)?.pathComponents,
              let handle = components.first(where: { $0.hasPrefix("@") && $0.count > 1 }) else { return nil }
        return handle
    }

    /// Nutrition is a Premium feature: free users see a locked card instead of the values
    private var isNutritionLocked: Bool {
        !subscriptionManager.hasPremiumAccess
    }

    /// Whether the recipe has (or can get) nutrition, i.e. whether the locked card is worth showing
    private var hasNutritionToUnlock: Bool {
        recipe.nutrition.map(NutritionSection.hasValues) == true
            || RecipeService.canEstimateNutrition(from: recipe.ingredients)
    }

    /// Message for the blurred Nutrition placeholder while there are no values yet, and whether
    /// it's in progress (spinner); nil hides the placeholder. Tells users nutrition is coming
    /// for their own recipes. "Estimated" is left to the real values' label.
    private var nutritionPlaceholder: (message: String, inProgress: Bool)? {
        guard recipe.nutrition == nil, RecipeService.canEstimateNutrition(from: recipe.ingredients) else { return nil }
        if isUnsavedPreview {
            return ("Save this recipe to see its nutrition.", false)
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
                VStack(alignment: .leading, spacing: 0) {
                    RecipeHero(
                        images: recipe.images,
                        pendingImages: pendingPhotoImages,
                        currentIndex: $currentImageIndex,
                        coverPhotoItem: isUnsavedPreview ? $coverPhotoItem : nil
                    )
                    .overlay(alignment: .top) { topBar }
                    .id("top")  // Anchor for scrolling to top

                    // Title card overlaps the hero photo
                    Group {
                        if showSavedHeader {
                            SavedRecipeInfoCard(
                                onClose: {
                                    withAnimation { showSavedHeader = false }
                                },
                                onAddMoreRecipes: onAddMoreRecipes,
                                onGoToMyRecipes: onGoToMyRecipes
                            )
                        } else {
                            RecipeInfoCard(
                                title: recipe.title,
                                duration: recipe.duration,
                                ingredientsCount: recipe.ingredientsCount,
                                sourceUrl: showsSource ? recipe.sourceUrl : nil,
                                sourceCredit: sourceCredit
                            )
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, -64)

                    // Content starts 32 below the card
                    VStack(alignment: .leading, spacing: SaltSpacing.section) {
                        if let previewNotice, mode == .regular || isUnsavedPreview {
                            PreviewNoticeBanner(text: previewNotice)
                        }

                        DescriptionSection(
                            text: recipe.description,
                            prepTime: recipe.prepTime,
                            cookTime: recipe.cookTime
                        )

                        IngredientsSection(
                            ingredients: recipe.ingredients,
                            servings: recipe.servings,
                            recipeTitle: recipe.title,
                            // Told from the steps: full sentences show the language better than ingredient names
                            languageSample: [recipe.title] + recipe.instructions
                        )

                        if !recipe.instructions.isEmpty {
                            InstructionsSection(instructions: recipe.instructions)
                        }

                        // Notes & tips: a plain section, only when the recipe has notes
                        if !recipe.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            NotesSection(notes: recipe.notes)
                        }

                        nutritionSection
                    }
                    .padding(.horizontal, SaltSpacing.screenMargin)
                    .padding(.top, SaltSpacing.section)
                }
                .padding(.bottom, isUnsavedPreview ? 24 : SaltSpacing.bottomTabPadding)
            }
            .background(SaltColor.surfaceScreen)
            .safeAreaInset(edge: .bottom) {
                // Pinned so Save is always reachable while reviewing
                if isUnsavedPreview {
                    previewButtons
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onChange(of: showSavedHeader) { _, saved in
                if saved {
                    withAnimation {
                        scrollProxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // No tab bar while reviewing a new recipe: the user is still inside the create flow
        .toolbar(isUnsavedPreview ? .hidden : .automatic, for: .tabBar)
        .ignoresSafeArea(edges: .top)
        .sheet(item: $editSheet) { sheet in
            NavigationStack {
                CreateRecipeView(
                    initialRecipe: recipe,
                    isEditMode: true,
                    onUpdate: sheet == .preview ? { updatedRecipe, newPhotos in
                        recipe = updatedRecipe
                        // Store photos locally for display in carousel
                        pendingPhotoImages = newPhotos
                        editSheet = nil
                    } : nil,
                    onSaveChanges: sheet == .preview ? nil : { updatedRecipe, newPhotos in
                        try await saveEdits(updatedRecipe, newPhotos: newPhotos, for: sheet)
                    },
                    saveChangesTitle: "Save changes",
                    editNotice: sheet == .customize
                        ? "Your changes are saved as your own copy in My Recipes. The original recipe isn't affected."
                        : nil,
                    onCancel: { editSheet = nil }
                )
                .navigationTitle(sheet == .customize ? "Customize" : "Edit Recipe")
                .navigationBarTitleDisplayMode(.inline)
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingCookingPremium, onDismiss: {
            if pendingCookingPaywall {
                pendingCookingPaywall = false
                paywallSource = .cookingMode
            }
        }) {
            PremiumFeatureSheet(
                title: String(localized: "Keep your screen on"),
                message: String(localized: "Your screen stays on while you cook,\nso you can follow every step hands-free."),
                onTryPremium: {
                    pendingCookingPaywall = true
                    showingCookingPremium = false
                },
                onNotNow: { showingCookingPremium = false }
            )
        }
        .sheet(item: $paywallSource) { source in
            // Remote paywall: shows whatever is attached to the current offering in the RevenueCat dashboard
            PaywallView(displayCloseButton: true)
                .onAppear {
                    Analytics.log(.paywallShown, ["source": source.rawValue])
                }
                .onPurchaseCompleted { customerInfo in
                    Analytics.log(.subscriptionStarted, ["source": source.rawValue])
                    continueAfterUpgrade(customerInfo, from: source)
                }
                .onRestoreCompleted { customerInfo in
                    Analytics.log(.purchasesRestored, ["source": source.rawValue])
                    continueAfterUpgrade(customerInfo, from: source)
                }
        }
        .sheet(item: $collectionTarget) { ref in
            AddToCollectionSheet(ref: ref, source: "recipe_menu")
        }
        .sheet(item: $collectionPromptRef) { ref in
            SaveToCollectionPrompt(ref: ref)
        }
        .sheet(item: $shareLink) { link in
            ActivityView(items: [link.url])
                .presentationDetents([.medium, .large])
        }
        .alert("Couldn't Share Recipe", isPresented: Binding(
            get: { shareErrorMessage != nil },
            set: { if !$0 { shareErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(shareErrorMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if isCreatingShareLink {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Creating link…")
                        .font(SaltFont.bodyStrong)
                        .foregroundStyle(SaltColor.textPrimary)
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(SaltColor.surfaceScreen, in: Capsule())
                .overlay(Capsule().stroke(SaltColor.borderSubtle, lineWidth: 1))
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            // User recipes without nutrition get an estimate when opened (older recipes, or one
            // just saved whose estimate is still running) and show it as soon as it arrives
            await estimateNutritionIfNeeded()
        }
        .task {
            guard offersCollectionPrompt, !didOfferCollectionPrompt, let userRecipeId else { return }
            didOfferCollectionPrompt = true
            // Lets the saved toast show for a moment first
            try? await Task.sleep(for: .seconds(1.5))
            collectionPromptRef = .own(userRecipeId)
        }
        .onAppear {
            Analytics.screen(mode == .preview ? "Recipe Preview" : "Recipe Detail")
            cookingModeShowsLabel = cookingModeUses < 3
        }
        .onChange(of: isCookingModeOn) { _, isOn in
            UIApplication.shared.isIdleTimerDisabled = isOn
        }
        .onChange(of: coverPhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    pendingPhotoImages.insert(image, at: 0)
                    currentImageIndex = 0
                }
                coverPhotoItem = nil
            }
        }
        .onDisappear {
            // Leaving the recipe turns Cooking mode off and restores normal auto-lock
            isCookingModeOn = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .alert("Delete this recipe?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteUserRecipe()
            }
        } message: {
            Text("It will be removed from My Recipes and all your collections.")
        }
    }

    @State private var pendingCookingPaywall = false

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                SaltGlassCircle {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(SaltColor.iconDefault)
                }
            }
            .accessibilityLabel("Back")

            Spacer()

            if isCreatePreview {
                Text("Preview")
                    .font(SaltFont.bodyStrong)
                    .foregroundStyle(SaltColor.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(SaltColor.surfaceScreen, in: Capsule())
                Spacer()
                // Keeps "Preview" centered
                Color.clear.frame(width: 40, height: 40)
            } else {
                if !isUnsavedPreview {
                    CookingModeButton(
                        isOn: isCookingModeOn,
                        isLocked: !subscriptionManager.hasPremiumAccess,
                        showsLabel: cookingModeShowsLabel || !subscriptionManager.hasPremiumAccess,
                        action: toggleCookingMode
                    )
                }

                if isExploreRecipe, let recipeId {
                    Button {
                        Task { await toggleBookmark(recipeId) }
                    } label: {
                        // Same bookmark as the Explore cards, in the top bar's 40pt slot
                        SaltBookmarkCircle(isBookmarked: isBookmarked)
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel(isBookmarked ? "Remove from Saved" : "Save recipe")
                }

                Menu {
                    menuContent
                } label: {
                    SaltGlassCircle {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SaltColor.iconDefault)
                    }
                }
                // Figma: dark menu icons; only Delete is colored (red, as destructive)
                .tint(SaltColor.textPrimary)
                .accessibilityLabel("More")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 54)
    }

    /// Native menu; order does the emphasis: Add to Collection, Share | Edit/Customize, Units | Delete
    @ViewBuilder private var menuContent: some View {
        if collectionRef != nil || canShare {
            Section {
                if let collectionRef {
                    Button {
                        collectionTarget = collectionRef
                    } label: {
                        Label("Add to Collection", systemImage: "text.badge.plus")
                    }
                }
                if canShare {
                    Button {
                        Task { await createShareLink() }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }

        Section {
            if let editAction {
                Button(action: editAction) {
                    Label("Edit", systemImage: "pencil")
                }
            } else if isExploreRecipe {
                // Makes the user's own editable copy (saved and marked "Edited")
                Button {
                    editSheet = .customize
                } label: {
                    Label("Customize", systemImage: "pencil")
                }
            }
            if let recipeUnits {
                Picker(selection: Binding(
                    get: { preferredUnits ?? recipeUnits },
                    set: { preferredUnits = $0 }
                )) {
                    Text("Imperial").tag(UnitSystem.imperial)
                    Text("Metric").tag(UnitSystem.metric)
                } label: {
                    Label("Units", systemImage: "list.bullet.rectangle")
                }
                .pickerStyle(.menu)
            }
        }

        if userRecipeId != nil && isSavedRecipe {
            Section {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } else if isUnsavedPreview {
            Section {
                // Discards the unsaved recipe
                Button(role: .destructive) {
                    dismiss()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            }
        }
    }

    // MARK: - Nutrition

    @ViewBuilder private var nutritionSection: some View {
        // Hidden when there's no data and no estimate coming
        if isNutritionLocked {
            if hasNutritionToUnlock {
                // Sample values only, so the real ones aren't on screen or read out.
                // Unlock opens the paywall directly; the card already explains it.
                NutritionSection(
                    nutrition: NutritionSection.placeholderValues,
                    onUnlock: { paywallSource = .nutritionLock }
                )
            }
        } else if let nutrition = recipe.nutrition, NutritionSection.hasValues(nutrition) {
            NutritionSection(nutrition: nutrition, isEstimated: recipe.nutritionEstimated)
        } else if let placeholder = nutritionPlaceholder {
            NutritionSection(
                nutrition: NutritionSection.placeholderValues,
                placeholderMessage: placeholder.message,
                placeholderInProgress: placeholder.inProgress
            )
        }
    }

    // MARK: - Cooking Mode

    /// Premium: keeps the screen awake. Free users get a short sheet about the feature.
    private func toggleCookingMode() {
        guard subscriptionManager.hasPremiumAccess else {
            showingCookingPremium = true
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) { isCookingModeOn.toggle() }
        guard isCookingModeOn else { return }
        cookingModeUses += 1
        Analytics.log(.cookingModeTurnedOn)
        // Confirmed once per recipe
        if !didShowCookingToast {
            didShowCookingToast = true
            SaltToastCenter.shared.show(
                String(localized: "Cooking mode is on"),
                detail: String(localized: "Your screen will stay awake on this recipe."),
                systemImage: "sun.max",
                duration: .seconds(3.5)
            )
        }
    }

    // MARK: - Bookmark

    /// Saves (or unsaves) an Explore recipe; saving shows the standard saved toast
    private func toggleBookmark(_ id: UUID) async {
        let wasBookmarked = bookmarkManager.isBookmarked(id)
        let isNowBookmarked = await bookmarkManager.toggleBookmark(for: id)
        if isNowBookmarked == wasBookmarked {
            SaltToastCenter.shared.show(String(localized: "Couldn't update. Please try again."), showsCheck: false)
        } else if isNowBookmarked {
            SaltToastCenter.shared.showSaved(.explore(id))
        } else {
            SaltToastCenter.shared.dismiss()
        }
    }

    // MARK: - Save Edits

    /// Saves the editor's changes: to the user's own recipe, or as a new copy of an Explore/saved
    /// recipe. Throws so the editor stays open and shows the error.
    private func saveEdits(_ edited: RecipeDetail, newPhotos: [UIImage], for sheet: EditSheet) async throws {
        let saved: UserRecipe
        switch sheet {
        case .ownRecipe:
            guard let userRecipeId else { return }
            saved = try await MyRecipesViewModel.shared.updateRecipe(id: userRecipeId, with: edited, newPhotos: newPhotos)
        case .customize:
            guard let recipeId else { return }
            saved = try await MyRecipesViewModel.shared.saveCustomizedCopy(of: recipeId, from: edited, newPhotos: newPhotos)
            // From now on this screen shows the user's copy (Edit/Delete instead of Customize)
            self.recipeId = nil
            userRecipeId = saved.id
        case .preview:
            return
        }

        recipe = saved.toRecipeDetail()
        pendingPhotoImages = []
        currentImageIndex = 0
        editSheet = nil

        if sheet == .customize {
            SaltToastCenter.shared.showSaved(.own(saved.id))
        }

        // Changed ingredients/servings cleared the old nutrition; the estimate keeps running
        // (and is saved) even if the user leaves this screen
        Task { await estimateNutritionIfNeeded() }
    }

    /// Closes the paywall once the user has Premium and continues with what they wanted
    private func continueAfterUpgrade(_ customerInfo: CustomerInfo, from source: PaywallSource) {
        subscriptionManager.update(with: customerInfo)
        // A restore with no active subscription leaves the paywall open
        guard subscriptionManager.hasPremiumAccess else { return }

        paywallSource = nil
        switch source {
        case .nutritionLock:
            Task { await estimateNutritionIfNeeded() }
        case .cookingMode:
            toggleCookingMode()
        }
    }

    /// Estimates nutrition for a user recipe that has none and shows it once it arrives
    private func estimateNutritionIfNeeded() async {
        guard subscriptionManager.hasPremiumAccess,
              let userRecipeId, recipe.nutrition == nil,
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

    // MARK: - Share

    /// Saves a snapshot of the recipe and opens the share sheet with its link
    private func createShareLink() async {
        guard !isCreatingShareLink, let sourceRecipeId = userRecipeId ?? recipeId else { return }

        withAnimation { isCreatingShareLink = true }
        do {
            let url = try await SharedRecipeService.shared.shareLink(
                for: recipe,
                sourceRecipeId: sourceRecipeId,
                // Explore recipes: recipients save the original instead of a copy
                originalRecipeId: userRecipeId == nil ? recipeId : nil
            )
            shareLink = ShareLinkItem(url: url)
            Analytics.log(.recipeShared, ["recipe_type": userRecipeId == nil ? "explore" : "own"])
        } catch {
            shareErrorMessage = error.localizedDescription
        }
        withAnimation { isCreatingShareLink = false }
    }

    // MARK: - Delete User Recipe

    /// Back to My Recipes with "Recipe deleted · Undo"; the recipe is deleted once the toast is gone
    private func deleteUserRecipe() {
        guard let recipeId = userRecipeId else { return }
        MyRecipesViewModel.shared.deleteRecipeWithUndo(id: recipeId)
        dismiss()
    }

    // MARK: - Preview Footer (Save)

    /// Sticky bottom while reviewing a recipe that hasn't been saved yet: Save recipe (main
    /// action) and Edit recipe (back to the form, nothing lost)
    private var previewButtons: some View {
        VStack(spacing: 4) {
            Button {
                // Store ALL data in shared storage BEFORE async call
                PendingSaveDataStorage.shared.store(recipe: recipe, photos: pendingPhotoImages)
                Task { await save() }
            } label: {
                SaltButtonLabel(title: "Save recipe", isLoading: isSaving)
            }
            .buttonStyle(.salt())
            .allowsHitTesting(!isSaving)

            Button("Edit recipe") {
                if editReturnsToForm {
                    dismiss()
                } else {
                    editSheet = .preview
                }
            }
            .buttonStyle(.salt(.text))
            .disabled(isSaving)
        }
        .padding(.horizontal, SaltSpacing.screenMargin)
        .padding(.top, 12)
        .background(
            SaltColor.surfaceScreen
                .overlay(alignment: .top) {
                    Rectangle().fill(SaltColor.borderSubtle).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func save() async {
        guard let onSave else { return }
        isSaving = true
        let success = await onSave()
        isSaving = false
        guard success else { return }

        withAnimation { hasBeenSaved = true }
        let savedId = savedRecipeId?()
        if onAddMoreRecipes != nil || onGoToMyRecipes != nil {
            // Shared recipe links keep their "Saved to My Recipes" card
            withAnimation { showSavedHeader = true }
        } else {
            userRecipeId = savedId
            SaltToastCenter.shared.showSaved(savedId.map { .own($0) })
        }
        // Once per account, so another account on the same phone still gets it
        let promptKey = "collectionPrompt.shown.\(AuthManager.shared.currentUser?.id ?? "")"
        if let savedId, !UserDefaults.standard.bool(forKey: promptKey) {
            UserDefaults.standard.set(true, forKey: promptKey)
            // Lets "Saved to My Recipes" show for a moment first
            try? await Task.sleep(for: .seconds(1.5))
            collectionPromptRef = .own(savedId)
        }
    }
}

// MARK: - Share Link Item

/// Share link ready to show in the share sheet
struct ShareLinkItem: Identifiable {
    let url: URL
    var id: URL { url }
}

// MARK: - Saved Recipe Info Card (shared recipe links, after saving)

struct SavedRecipeInfoCard: View {
    var onClose: (() -> Void)?
    var onAddMoreRecipes: (() -> Void)?
    var onGoToMyRecipes: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SaltColor.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
            }
            .padding(.bottom, -28)

            HStack(spacing: 8) {
                SaltSuccessBadge(size: 28)
                Text("Saved to My Recipes")
                    .font(SaltFont.h3)
                    .foregroundStyle(SaltColor.textPrimary)
            }

            VStack(spacing: 8) {
                if let onGoToMyRecipes {
                    Button("Go to My Recipes", action: onGoToMyRecipes)
                        .buttonStyle(.salt(.primary, size: .small, fullWidth: true))
                }
                if let onAddMoreRecipes {
                    Button("Add more recipes", action: onAddMoreRecipes)
                        .buttonStyle(.salt(.secondary, size: .small, fullWidth: true))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(SaltColor.surfaceRecipeCard, in: RoundedRectangle(cornerRadius: SaltRadius.titleCard, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

// MARK: - Hero

/// Hero photo(s). Without a photo: a soft cream cover, with "Add a cover photo" while previewing.
struct RecipeHero: View {
    let images: [String]
    var pendingImages: [UIImage] = []  // New photos not yet uploaded
    @Binding var currentIndex: Int
    /// Set while previewing an unsaved recipe: the empty cover opens the photo library
    var coverPhotoItem: Binding<PhotosPickerItem?>?

    static let height: CGFloat = 280

    private var totalImageCount: Int {
        images.count + pendingImages.count
    }

    var body: some View {
        ZStack {
            if totalImageCount == 0 {
                emptyCover
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(0..<images.count, id: \.self) { index in
                        CachedAsyncImage(url: URL(string: images[index])) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                SaltColor.surfaceControl
                            }
                        }
                        .tag(index)
                    }
                    ForEach(0..<pendingImages.count, id: \.self) { index in
                        Image(uiImage: pendingImages[index])
                            .resizable()
                            .scaledToFill()
                            .tag(images.count + index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: totalImageCount > 1 ? .automatic : .never))
            }
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    @ViewBuilder private var emptyCover: some View {
        let cover = SaltColor.surfaceWarmSubtle
        if let coverPhotoItem {
            PhotosPicker(selection: coverPhotoItem, matching: .images) {
                ZStack {
                    cover
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(SaltColor.textSecondary)
                        Text("Add a cover photo")
                            .font(SaltFont.bodyLarge)
                            .foregroundStyle(SaltColor.textSecondary)
                    }
                    // Clear of the top bar and the title card
                    .padding(.top, 36)
                    .padding(.bottom, 30)
                }
            }
            .buttonStyle(.plain)
        } else {
            ZStack {
                cover
                Image(systemName: "fork.knife")
                    .font(.system(size: 30))
                    .foregroundStyle(SaltColor.textDisabled)
                    .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Cooking Mode Button

/// Labeled pill ("☀︎ Cooking mode") for the first 3 uses, then only the icon in a glass circle.
/// On: deeper peach with an orange icon and label. Free: a small gray lock after the label.
struct CookingModeButton: View {
    let isOn: Bool
    let isLocked: Bool
    let showsLabel: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if showsLabel {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.max")
                            .font(.system(size: 16))
                            .foregroundStyle(SaltColor.iconAccent)
                        Text(isOn ? "Cooking mode on" : "Cooking mode")
                            .font(SaltFont.bodyLarge)
                            .foregroundStyle(isOn ? SaltColor.textAccent : SaltColor.textPrimary)
                        if isLocked {
                            Image(systemName: "lock")
                                .font(.system(size: 12))
                                .foregroundStyle(SaltColor.textSecondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(isOn ? SaltColor.surfaceWarmStrong : Color.white.opacity(0.92), in: Capsule())
                } else {
                    SaltGlassCircle(isActive: isOn) {
                        Image(systemName: "sun.max")
                            .font(.system(size: 17))
                            .foregroundStyle(isOn ? SaltColor.iconAccent : SaltColor.iconDefault)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cooking mode")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(isLocked ? "Premium feature. Keeps your screen awake." : "Keeps your screen awake")
        .help("Cooking mode")
    }
}

// MARK: - Recipe Info Card

/// Beige title card: Playfair title, pink time + ingredients icons, optional "Original Recipe ↗"
/// link and a gray source credit line under it ("@handle · Instagram" or "site.com").
struct RecipeInfoCard: View {
    let title: String
    let duration: String
    let ingredientsCount: String
    var sourceUrl: String? = nil
    var sourceCredit: String? = nil

    /// Link to the page the recipe was imported from, if any
    private var sourceLink: URL? {
        guard let sourceUrl, !sourceUrl.isEmpty else { return nil }
        return URL(string: sourceUrl)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(SaltFont.h3)
                .foregroundStyle(SaltColor.textPrimary)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)

            HStack {
                Spacer(minLength: 0)
                RecipeMetaItem(icon: "timerIcon", text: duration)
                Spacer(minLength: 16)
                RecipeMetaItem(icon: "nutritionIcon", text: ingredientsCount)
                Spacer(minLength: 0)
            }
            .padding(.top, 16)

            if let sourceLink {
                Link(destination: sourceLink) {
                    HStack(spacing: 6) {
                        Text("Original Recipe")
                            .font(SaltFont.openSans(17, semibold: true))
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 15))
                    }
                    .foregroundStyle(SaltColor.textAccent)
                    .frame(minHeight: 32)
                }
                .padding(.top, 12)

                if let sourceCredit {
                    Text(sourceCredit)
                        .font(SaltFont.caption)
                        .foregroundStyle(SaltColor.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(SaltColor.surfaceRecipeCard, in: RoundedRectangle(cornerRadius: SaltRadius.titleCard, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

/// Pink recipe meta icon + Playfair value (Label/Meta), e.g. "⏱ 25 min"
struct RecipeMetaItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(icon)
                .resizable()
                .renderingMode(.template)
                .frame(width: 24, height: 24)
                .foregroundStyle(SaltColor.iconMeta)
            Text(text)
                .font(SaltFont.labelMeta)
                .foregroundStyle(SaltColor.textPrimary)
                .lineLimit(1)
        }
    }
}

// MARK: - Preview Notice Banner

/// Heads-up shown above the content, e.g. when the recipe was taken from a video's audio
struct PreviewNoticeBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .foregroundStyle(SaltColor.textSecondary)
                .padding(.top, 1)

            Text(text)
                .font(SaltFont.body)
                .foregroundStyle(SaltColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SaltColor.surfaceWarmSubtle, in: RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Description Section

/// Description, then one time line under it: "⏱ Prep 10 min · Cook 15 min"
struct DescriptionSection: View {
    let text: String
    let prepTime: String
    let cookTime: String

    private var hasDescription: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "No description available"
    }

    /// "Prep 10 min · Cook 15 min"; nil when the recipe gives no times
    private var timeLine: String? {
        var parts: [String] = []
        if TimeValue.hasTime(prepTime) { parts.append(String(localized: "Prep \(TimeValue.minutes(prepTime)) min")) }
        if TimeValue.hasTime(cookTime) { parts.append(String(localized: "Cook \(TimeValue.minutes(cookTime)) min")) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    var body: some View {
        if hasDescription || timeLine != nil {
            VStack(alignment: .leading, spacing: 0) {
                if hasDescription {
                    Text("Description")
                        .font(SaltFont.h2)
                        .foregroundStyle(SaltColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(text)
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, SaltSpacing.titleToContent)
                }
                if let timeLine {
                    HStack(spacing: 8) {
                        Image("timerIcon")
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 20, height: 20)
                            .foregroundStyle(SaltColor.iconMeta)
                        Text(timeLine)
                            .font(SaltFont.labelMeta)
                            .foregroundStyle(SaltColor.textPrimary)
                    }
                    .padding(.top, hasDescription ? 16 : 0)
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Prep/cook values as stored ("10", "0" or empty when not given)
enum TimeValue {
    /// "0" or an empty value means the recipe doesn't give this time
    static func hasTime(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespaces)
        return !value.isEmpty && value != "0"
    }

    static func minutes(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " mins", with: "")
            .replacingOccurrences(of: " min", with: "")
    }
}

// MARK: - Ingredients Section

struct IngredientsSection: View {
    let ingredients: [String]
    let servings: String  // The recipe's servings text, e.g. "4 servings"; scaling starts from it
    var recipeTitle: String = ""  // Helps the AI pick substitutes that suit the dish
    /// Recipe text (title and steps) used to tell its language, for English plurals
    var languageSample: [String] = []

    /// The Swap an ingredient link opens the list (or the paywall for free users);
    /// tapping a swapped line opens just that one
    private enum ReplaceSheet: Identifiable {
        case paywall
        case pickIngredient
        case ingredient(IngredientPosition)

        var id: String {
            switch self {
            case .paywall: return "paywall"
            case .pickIngredient: return "pick"
            case .ingredient(let position): return "\(position.section)-\(position.line)"
            }
        }
    }

    @State private var selectedServings: Int?  // nil = the recipe's own servings
    /// Ingredients swapped while viewing the recipe; the recipe itself isn't changed
    @State private var swaps: [IngredientPosition: Substitute] = [:]
    @State private var replaceSheet: ReplaceSheet?
    /// Changed amounts flash orange for ~1s after the servings change
    @State private var flashesAmounts = false
    @State private var flashTask: Task<Void, Never>?
    /// Swapping ingredients is a Premium feature
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    /// Chosen in Profile or the … menu; nil = as each recipe is written
    @AppStorage("preferredUnitSystem") private var preferredUnits: UnitSystem?

    private var baseServings: Int? { IngredientScaler.baseServings(from: servings) }
    private var sections: [IngredientScaler.Section] { IngredientScaler.sections(from: ingredients) }
    /// English plurals ("2 cups") only for English recipes; e.g. Turkish keeps "500 gram"
    @State private var ingredientsAreEnglish = true

    /// Every line with its place in the list, grouped like the list
    private var positions: [(heading: String?, positions: [IngredientPosition])] {
        sections.enumerated().map { sectionIndex, section in
            (section.heading, section.lines.enumerated().map { lineIndex, line in
                IngredientPosition(section: sectionIndex, line: lineIndex, text: line)
            })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ingredients")
                .font(SaltFont.h2)
                .foregroundStyle(SaltColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .task(id: languageSample) {
                    ingredientsAreEnglish = IngredientScaler.isEnglish(languageSample.isEmpty ? ingredients : languageSample)
                }

            // Hidden when the recipe doesn't say how many it serves; there's nothing to scale from
            if let base = baseServings {
                ServingsStepper(
                    servings: selectedServings ?? base,
                    original: base,
                    onChange: { selectedServings = $0 == base ? nil : $0 }
                )
                .padding(.top, 4)
                .padding(.leading, -7)  // Aligns the visible circle (not its 44pt tap area) with the text
            }

            // Imported recipes can group ingredients (Marinade, Crema, Pico de gallo).
            // Lines can repeat (e.g. "Salt" in two groups), so everything is identified by position.
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(positions.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 12) {
                        if let heading = section.heading {
                            Text(heading)
                                .font(SaltFont.h3)
                                .foregroundStyle(SaltColor.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(section.positions) { position in
                            ingredientRow(position)
                        }
                    }
                }
            }
            .padding(.top, baseServings == nil ? SaltSpacing.titleToContent : 12)

            if !ingredients.isEmpty {
                // A quiet link, so it doesn't compete with the ingredients
                Button {
                    replaceSheet = subscriptionManager.hasPremiumAccess ? .pickIngredient : .paywall
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13))
                        Text("Swap an ingredient")
                            .font(SaltFont.bodyStrong)
                        if !subscriptionManager.hasPremiumAccess {
                            Image(systemName: "lock")
                                .font(.system(size: 11))
                                .foregroundStyle(SaltColor.textSecondary)
                        }
                    }
                    .foregroundStyle(SaltColor.textAccent)
                    .frame(minHeight: 44)
                }
                .padding(.top, 8)
                .accessibilityHint(subscriptionManager.hasPremiumAccess ? "" : "Premium feature")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The recipe was edited (preview mode); start again from its servings
        .onChange(of: servings) { _, _ in
            selectedServings = nil
        }
        .onChange(of: selectedServings) { _, _ in
            flashChangedAmounts()
        }
        // Swaps are tied to positions, which no longer match after an edit
        .onChange(of: ingredients) { _, _ in
            swaps = [:]
        }
        .sheet(item: $replaceSheet) { sheet in
            switch sheet {
            case .paywall:
                // Remote paywall: shows whatever is attached to the current offering in the RevenueCat dashboard
                PaywallView(displayCloseButton: true)
                    .onAppear {
                        Analytics.log(.paywallShown, ["source": "swap_lock"])
                    }
                    .onPurchaseCompleted { customerInfo in
                        Analytics.log(.subscriptionStarted, ["source": "swap_lock"])
                        openSwapsAfterUpgrade(customerInfo)
                    }
                    .onRestoreCompleted { customerInfo in
                        Analytics.log(.purchasesRestored, ["source": "swap_lock"])
                        openSwapsAfterUpgrade(customerInfo)
                    }
            case .pickIngredient:
                ReplaceIngredientSheet(
                    sections: positions,
                    swaps: swaps,
                    recipeTitle: recipeTitle,
                    ingredients: ingredients,
                    display: scaled,
                    onSelect: { position, substitute in
                        swaps[position] = substitute
                        replaceSheet = nil
                    }
                )
            case .ingredient(let position):
                NavigationStack {
                    IngredientSubstitutesView(
                        line: position.text,
                        recipeTitle: recipeTitle,
                        ingredients: ingredients,
                        current: swaps[position],
                        display: scaled,
                        onSelect: { substitute in
                            swaps[position] = substitute
                            replaceSheet = nil
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { replaceSheet = nil }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    /// Goes on to the ingredient list once the user has Premium; a restore with no active
    /// subscription leaves the paywall open
    private func openSwapsAfterUpgrade(_ customerInfo: CustomerInfo) {
        subscriptionManager.update(with: customerInfo)
        guard subscriptionManager.hasPremiumAccess else { return }
        replaceSheet = .pickIngredient
    }

    private func flashChangedAmounts() {
        flashTask?.cancel()
        flashesAmounts = true
        flashTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { flashesAmounts = false }
        }
    }

    /// The line as written, or the substitute in use with the original below it.
    /// Swapped lines can be tapped to pick another substitute or go back to the original.
    @ViewBuilder
    private func ingredientRow(_ position: IngredientPosition) -> some View {
        if let swap = swaps[position] {
            Button {
                replaceSheet = .ingredient(position)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SaltColor.iconAccent)
                            .accessibilityHidden(true)
                        Text(scaled(swap.line))
                            .font(SaltFont.bodyLarge)
                            .foregroundStyle(SaltColor.textPrimary)
                    }
                    Text("instead of \(scaled(position.text))")
                        .font(SaltFont.caption)
                        .foregroundStyle(SaltColor.textSecondary)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Change or undo the substitute")
        } else {
            amountHighlighted(scaled(position.text))
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The line with its amount (and unit) in orange while the flash is on
    private func amountHighlighted(_ line: String) -> Text {
        guard flashesAmounts,
              let range = Self.amountRange(in: line) else { return Text(line) }
        let amount = String(line[range])
        let rest = String(line[range.upperBound...])
        return Text(amount).foregroundColor(SaltColor.textAccent) + Text(rest)
    }

    private static let units: Set<String> = [
        "cup", "cups", "tbsp", "tsp", "tablespoon", "tablespoons", "teaspoon", "teaspoons",
        "g", "kg", "gram", "grams", "ml", "l", "liter", "liters", "litre", "litres",
        "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "fl", "pinch", "pinches",
        "clove", "cloves", "can", "cans", "stick", "sticks", "slice", "slices"
    ]

    /// The leading amount ("2 ¼ cups", "300 g") of an amount-first line
    private static func amountRange(in line: String) -> Range<String.Index>? {
        guard let number = line.range(of: #"^[\d½¼¾⅓⅔⅛⅜⅝⅞⅙⅚⅕/.,\-–\s]*[\d½¼¾⅓⅔⅛⅜⅝⅞⅙⅚⅕]"#, options: .regularExpression) else { return nil }
        var end = number.upperBound
        let remainder = line[end...]
        let word = remainder.drop(while: { $0 == " " }).prefix(while: { $0.isLetter || $0 == "." })
        if units.contains(word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
            end = line.index(remainder.startIndex, offsetBy: remainder.distance(from: remainder.startIndex, to: word.endIndex))
        }
        return line.startIndex..<end
    }

    /// Amount first ("½ cup milk"), scaled to the selected servings, in the selected units
    private func scaled(_ ingredient: String) -> String {
        var factor = 1.0
        if let base = baseServings, let selected = selectedServings {
            factor = Double(selected) / Double(base)
        }
        let line = IngredientScaler.display(ingredient, scaledBy: factor, inflectsEnglish: ingredientsAreEnglish)
        guard let preferredUnits else { return line }
        return UnitConverter.convert(line, to: preferredUnits)
    }
}

/// Pink stepper ("−  4 servings  +") and, once changed, "Scaled from 4 servings · Reset"
struct ServingsStepper: View {
    let servings: Int
    let original: Int
    let onChange: (Int) -> Void

    private let range = 1...99

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SaltStepper(
                label: servings == 1 ? String(localized: "1 serving") : String(localized: "\(servings) servings"),
                canDecrement: servings > range.lowerBound,
                canIncrement: servings < range.upperBound,
                onDecrement: { onChange(servings - 1) },
                onIncrement: { onChange(servings + 1) }
            )
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
                HStack(spacing: 6) {
                    Text(original == 1 ? "Scaled from 1 serving" : "Scaled from \(original) servings")
                        .font(SaltFont.body)
                        .foregroundStyle(SaltColor.textSecondary)
                    Text("·")
                        .font(SaltFont.body)
                        .foregroundStyle(SaltColor.textSecondary)
                    Button("Reset") {
                        onChange(original)
                    }
                    .font(SaltFont.bodyStrong)
                    .foregroundStyle(SaltColor.textAccent)
                    .frame(minHeight: 32)
                    .accessibilityLabel("Reset to \(original) servings")
                }
                .padding(.leading, 7)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: servings != original)
    }
}

// MARK: - Instructions Section

/// Numbered steps on pink circles (same as the Create form)
struct InstructionsSection: View {
    let instructions: [String]

    /// Oven temperatures follow the chosen units
    @AppStorage("preferredUnitSystem") private var preferredUnits: UnitSystem?

    var body: some View {
        VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
            Text("Instructions")
                .font(SaltFont.h2)
                .foregroundStyle(SaltColor.textPrimary)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 12) {
                        StepNumber(number: index + 1)

                        Text(preferredUnits.map { UnitConverter.convertTemperatures(in: instruction, to: $0) } ?? instruction)
                            .font(SaltFont.bodyLarge)
                            .foregroundStyle(SaltColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 3)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Step number on a 30pt pink circle
struct StepNumber: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(SaltFont.bodyLargeStrong)
            .foregroundStyle(SaltColor.textPrimary)
            .frame(width: 30, height: 30)
            .background(SaltColor.surfacePink, in: Circle())
    }
}

// MARK: - Notes Section

/// Notes & tips: a plain section (title + text), no card
struct NotesSection: View {
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
            Text("Notes & tips")
                .font(SaltFont.h2)
                .foregroundStyle(SaltColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(notes)
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Nutrition Section

/// Per-serving nutrition card on surface/warm: calories as the hero number (orange), then rows.
/// Free: blurred sample values under a white card with a small "Unlock with Premium" button.
struct NutritionSection: View {
    let nutrition: NutritionInfo
    var isEstimated = false  // AI-estimated values get a label and a short disclaimer
    var placeholderMessage: String? = nil  // When set, the values are blurred sample data under this message
    var placeholderInProgress = false      // Spinner instead of the sparkles icon next to the message
    var onUnlock: (() -> Void)? = nil      // When set, the values are locked for free users (blurred, with an upgrade button)

    private var isBlurred: Bool { placeholderMessage != nil || onUnlock != nil }

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
        VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
            HStack(alignment: .center, spacing: 10) {
                Text("Nutrition")
                    .font(SaltFont.h2)
                    .foregroundStyle(SaltColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if isEstimated && !isBlurred {
                    Text("Estimated")
                        .font(SaltFont.captionStrong)
                        .foregroundStyle(SaltColor.textAccent)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(SaltColor.surfaceWarmStrong, in: Capsule())
                }
                Spacer()
                Text("Per serving")
                    .font(SaltFont.body)
                    .foregroundStyle(SaltColor.textSecondary)
            }

            VStack(spacing: 0) {
                if let calories = Self.formatNumber(nutrition.calories) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Calories")
                            .font(SaltFont.bodyLarge)
                            .foregroundStyle(SaltColor.textPrimary)
                        Spacer()
                        Text(calories)
                            .font(SaltFont.numberLarge)
                            .foregroundStyle(SaltColor.textAccent)
                        Text("cal")
                            .font(SaltFont.body)
                            .foregroundStyle(SaltColor.textSecondary)
                    }
                    .padding(.vertical, 14)
                    .accessibilityElement(children: .combine)

                    if !rows.isEmpty {
                        divider
                    }
                }

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Text(row.name)
                            .font(SaltFont.bodyLarge)
                        Spacer()
                        Text(row.value)
                            .font(SaltFont.bodyLarge)
                    }
                    .foregroundStyle(SaltColor.textPrimary)
                    .padding(.vertical, 14)
                    .accessibilityElement(children: .combine)

                    if index < rows.count - 1 {
                        divider
                    }
                }
            }
            // Sample values are blurred so they read as "something's coming", not as data
            .blur(radius: isBlurred ? 6 : 0)
            .accessibilityHidden(isBlurred)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(SaltColor.surfaceWarm, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                if let onUnlock {
                    lockedOverlay(onUnlock: onUnlock)
                } else if let placeholderMessage {
                    placeholderOverlay(placeholderMessage)
                }
            }

            if isEstimated && !isBlurred {
                Text("Estimated with AI from the ingredients. Values are approximate.")
                    .font(SaltFont.caption)
                    .foregroundStyle(SaltColor.textSecondary)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(SaltColor.borderSubtle).frame(height: 1)
    }

    /// Message card centered over the blurred sample values
    private func placeholderOverlay(_ message: String) -> some View {
        HStack(spacing: 10) {
            if placeholderInProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "sparkles")
                    .foregroundStyle(SaltColor.textSecondary)
            }
            Text(message)
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(SaltColor.surfaceScreen, in: RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous))
        .padding(.horizontal, 28)
        .accessibilityElement(children: .combine)
    }

    /// Premium lock centered over the blurred sample values
    private func lockedOverlay(onUnlock: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "lock")
                .font(.system(size: 18))
                .foregroundStyle(SaltColor.textSecondary)
                .accessibilityHidden(true)

            Text("See calories, carbs, protein and more with Premium.")
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Unlock with Premium", action: onUnlock)
                .buttonStyle(.salt(.primary, size: .small))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(SaltColor.surfaceScreen, in: RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous))
        .padding(.horizontal, 28)
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
    NavigationStack {
        RecipeDetailView(
            recipe: RecipeDetail(
                title: "Fluffy Berry Pancakes",
                duration: "25 min",
                ingredientsCount: "7 ingredients",
                description: "Fluffy weekend pancakes with fresh berries, ready in under 30 minutes.",
                servings: "4",
                prepTime: "10",
                cookTime: "15",
                ingredients: [
                    "2 cups all-purpose flour",
                    "1 1/2 cups milk",
                    "2 eggs",
                    "1 cup mixed berries"
                ],
                instructions: [
                    "Whisk the flour, sugar and baking powder in a large bowl.",
                    "Whisk the milk and eggs, pour into the dry ingredients and stir until just combined.",
                    "Cook 1/4 cup of batter per pancake on a medium-hot pan until bubbles form, then flip."
                ],
                notes: "",
                images: ["https://upload.wikimedia.org/wikipedia/commons/4/43/Pancake.jpg"],
                sourceUrl: "https://www.instagram.com/reel/abc",
                sourceName: "dinnerin10"
            ),
            userRecipeId: UUID()
        )
    }
}
