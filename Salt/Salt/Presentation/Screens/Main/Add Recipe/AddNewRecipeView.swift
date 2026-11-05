
import SwiftUI
import PhotosUI
import RevenueCat
import RevenueCatUI

// MARK: - Add New Recipe View

struct AddNewRecipeView: View {
    @State private var selectedTab: AddRecipeTab = .import
    @State private var recipeLink = ""
    @ObservedObject private var shareImportRouter = ShareImportRouter.shared

    /// Set from another tab to open Create or Import; cleared once applied
    @Binding var requestedTab: AddRecipeTab?

    // Callback to switch to My Recipes tab
    var switchToMyRecipes: (() -> Void)?

    init(requestedTab: Binding<AddRecipeTab?> = .constant(nil), switchToMyRecipes: (() -> Void)? = nil) {
        _requestedTab = requestedTab
        self.switchToMyRecipes = switchToMyRecipes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Header
            Text("Add New Recipe")
                .font(.custom("Playfair9pt-SemiBold", size: 28))
                .padding(.horizontal)
                .padding(.top, 16)

            // Tab Switcher
            TabSwitcher(selectedTab: $selectedTab)
                .padding(.horizontal)

            // Content
            if selectedTab == .create {
                CreateRecipeView(switchToMyRecipes: switchToMyRecipes)
            } else {
                ImportRecipeView(recipeLink: $recipeLink, switchToMyRecipes: switchToMyRecipes)
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            if shareImportRouter.pendingImport != nil {
                selectedTab = .import
            }
        }
        .onChange(of: shareImportRouter.pendingImport) { _, sharedImport in
            // Shared link, photos or text arrived - show the Import tab so it can pick it up
            if sharedImport != nil {
                selectedTab = .import
            }
        }
        .onChange(of: requestedTab, initial: true) { _, tab in
            // e.g. Create manually on the Explore banner
            guard let tab else { return }
            selectedTab = tab
            requestedTab = nil
        }
    }
}

// MARK: - Tab Enum

enum AddRecipeTab {
    case create
    case `import`
}

// MARK: - Tab Switcher

struct TabSwitcher: View {
    @Binding var selectedTab: AddRecipeTab
    
    var body: some View {
        ZStack {
            // Background
            Color("LightGrayishPink")
            
            // White selector
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .frame(width: 156, height: 36)
                .offset(x: selectedTab == .create ? -82 : 82)
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
            
            // Buttons
            HStack(spacing: 0) {
                // Create Tab
                Button(action: { selectedTab = .create }) {
                    HStack(spacing: 4) {
                        Text("Create")
                            .font(.custom("Playfair9pt-Regular", size: 22))
                            .foregroundColor(Color.black)
                        
                        Image("createIcon")
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 20, height: 20)
                            .foregroundColor(Color("GraniteGray"))
                    }
                    .frame(width: 164, height: 44)
                }
                
                // Import Tab
                Button(action: { selectedTab = .import }) {
                    HStack(spacing: 4) {
                        Text("Import")
                            .font(.custom("Playfair9pt-Regular", size: 22))
                            .foregroundColor(Color.black)
                        
                        Image("importIcon")
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 22, height: 22)
                            .foregroundColor(Color("GraniteGray"))
                    }
                    .frame(width: 164, height: 44)
                }
            }
        }
        .frame(width: 328, height: 44)
        .cornerRadius(16)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Import Recipe View

struct ImportRecipeView: View {
    @Binding var recipeLink: String
    @StateObject private var viewModel = RecipeImportViewModel()
    @State private var navigateToPreview = false
    @State private var showingPaywall = false
    @State private var showingImportLimitAlert = false
    @FocusState private var isLinkFieldFocused: Bool
    @ObservedObject private var shareImportRouter = ShareImportRouter.shared
    /// Last link received from the Share Extension, so analytics can tell shared links from pasted ones
    @State private var sharedLink: String?
    @State private var showingPhotoOptions = false
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var capturedImage: UIImage?
    @State private var showingPasteText = false
    @State private var pastedText = ""
    /// Photo or text import being run; kept while the paywall is shown so the import can continue after upgrading
    @State private var pendingImport: PendingImport?

    /// A recipe can span a few pages or screenshots (e.g. ingredients on one, steps on the next)
    private static let maxImportPhotos = 5

    /// An import without a link, and how it started (for analytics)
    private enum PendingImport {
        case photos([UIImage], entry: String)
        case text(String, entry: String)
    }

    private var isImportingPhoto: Bool {
        guard viewModel.isLoading, case .photos = pendingImport else { return false }
        return true
    }

    private var isImportingText: Bool {
        guard viewModel.isLoading, case .text = pendingImport else { return false }
        return true
    }

    // Callback to switch to My Recipes tab
    var switchToMyRecipes: (() -> Void)?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text("Enter your recipe link here")
                    .font(.custom("Playfair9pt-Regular", size: 22))

                // Text Field
                ZStack(alignment: .leading) {
                    if recipeLink.isEmpty {
                        Text("e.g., https://example.com/recipe/pancake")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundColor(Color("DarkSilver"))
                            .padding(.horizontal, 16)
                    }

                    TextField("", text: $recipeLink)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(.black)
                        .tint(Color("OrangeRed"))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .focused($isLinkFieldFocused)
                        .padding(.horizontal, 16)
                }
                .frame(height: 35)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color("DarkSilver"), lineWidth: 1)
                )

                // Description
                Text("Paste a link from Instagram, YouTube or your favorite food blog. Salt will instantly transform it into a clean, ready-to-cook recipe.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("DarkSilver"))

                // Error message
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(.red)
                }

                // Import Button
                HStack {
                    Spacer()
                    Button(action: {
                        Task { await startImport() }
                    }) {
                        HStack(spacing: 8) {
                            if viewModel.isLoading && pendingImport == nil {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(viewModel.isLoading && pendingImport == nil ? "Importing..." : "Import the Recipe")
                                .font(.custom("OpenSans-SemiBold", size: 18))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color("Orange"))
                        .cornerRadius(10)
                    }
                    .disabled(recipeLink.isEmpty || viewModel.isLoading)
                    Spacer()
                }
                .padding(.top, 16)

                // Import from a photo of a cookbook page, recipe card or screenshot
                VStack(spacing: 8) {
                    Text("or")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color("DarkSilver"))

                    Button(action: {
                        isLinkFieldFocused = false
                        showingPhotoOptions = true
                    }) {
                        HStack(spacing: 8) {
                            if isImportingPhoto {
                                ProgressView()
                                    .tint(Color("Orange"))
                            } else {
                                Image(systemName: "camera")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Text(isImportingPhoto ? "Reading your photo..." : "Import from a Photo")
                                .font(.custom("OpenSans-SemiBold", size: 18))
                        }
                        .foregroundColor(Color("Orange"))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color("Orange"), lineWidth: 1.5)
                        )
                    }
                    .disabled(viewModel.isLoading)

                    Text("Snap a cookbook page or recipe card, or pick screenshots of an Instagram caption or a recipe site. Up to \(Self.maxImportPhotos) for one recipe.")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundColor(Color("DarkSilver"))
                        .multilineTextAlignment(.center)

                    // Import a recipe written out as text, e.g. copied from the Notes app
                    Button(action: {
                        isLinkFieldFocused = false
                        showingPasteText = true
                    }) {
                        HStack(spacing: 8) {
                            if isImportingText {
                                ProgressView()
                                    .tint(Color("Orange"))
                            } else {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Text(isImportingText ? "Reading your recipe..." : "Paste Recipe Text")
                                .font(.custom("OpenSans-SemiBold", size: 18))
                        }
                        .foregroundColor(Color("Orange"))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color("Orange"), lineWidth: 1.5)
                        )
                    }
                    .disabled(viewModel.isLoading)
                    .padding(.top, 8)

                    Text("Copy a recipe from Notes or anywhere else and paste it in, or share a note straight to Salt.")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundColor(Color("DarkSilver"))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                // Shortcut for social media: share straight to Salt via the Share Extension
                ShareImportDemoView()
                    .padding(.top, 12)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("Import from a Photo", isPresented: $showingPhotoOptions, titleVisibility: .visible) {
            if CameraView.isAvailable {
                Button("Take Photo") {
                    showingCamera = true
                }
            }
            Button("Choose from Library") {
                showingPhotoPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView(image: $capturedImage)
                .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: Self.maxImportPhotos,
            selectionBehavior: .ordered,
            matching: .images
        )
        .sheet(isPresented: $showingPasteText) {
            PasteRecipeTextView(text: $pastedText) {
                showingPasteText = false
                pendingImport = .text(pastedText, entry: "pasted")
                Task { await startPendingImport() }
            }
        }
        .onChange(of: capturedImage) { _, image in
            guard let image else { return }
            capturedImage = nil
            pendingImport = .photos([image], entry: "camera")
            Task { await startPendingImport() }
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                // Kept in the order they were picked, so pages are read in order
                var photos: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        photos.append(image)
                    }
                }
                selectedPhotoItems = []
                guard !photos.isEmpty else { return }
                pendingImport = .photos(photos, entry: "photo_library")
                await startPendingImport()
            }
        }
        .alert("You've used your free imports", isPresented: $showingImportLimitAlert) {
            Button("Start Free Trial") {
                showingPaywall = true
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("You used all \(RevenueCatConfig.freeImportLimit) free imports. Start a free trial of Premium for unlimited imports.")
        }
        .sheet(isPresented: $showingPaywall) {
            // Remote paywall: shows whatever is attached to the current offering in the RevenueCat dashboard
            PaywallView(displayCloseButton: true)
                .onAppear {
                    Analytics.log(.paywallShown, ["source": "import_limit"])
                }
                .onPurchaseCompleted { customerInfo in
                    Analytics.log(.subscriptionStarted, ["source": "import_limit"])
                    continueImportAfterUpgrade(customerInfo)
                }
                .onRestoreCompleted { customerInfo in
                    Analytics.log(.purchasesRestored, ["source": "import_limit"])
                    continueImportAfterUpgrade(customerInfo)
                }
        }
        .navigationDestination(isPresented: $navigateToPreview) {
            if let recipe = viewModel.importedRecipe {
                RecipeDetailView(
                    recipe: recipe.toRecipeDetail(),
                    mode: .preview,
                    previewNotice: recipe.isFromVideoAudio
                        ? "This recipe wasn't in the post's caption, so we put it together from what's said in the video. Some ingredients, amounts or steps may be missing. Please check it before saving; you can fix anything with Edit in the menu."
                        : recipe.origin == .photo
                            ? "We read this recipe from your photo. Please check the amounts and steps before saving; you can fix anything with Edit in the menu."
                            : nil,
                    onSave: {
                        // Get ALL data from shared storage - no closure parameters!
                        let savedData = PendingSaveDataStorage.shared.retrieve()
                        guard let recipeDetail = savedData.recipe else {
                            return false
                        }
                        return await viewModel.saveRecipe(from: recipeDetail, photos: savedData.photos)
                    },
                    savedRecipeId: { viewModel.savedRecipeId },
                    onAddMoreRecipes: {
                        // Clear and go back
                        recipeLink = ""
                        pastedText = ""
                        viewModel.clearImport()
                        PendingSaveDataStorage.shared.clear()
                        navigateToPreview = false
                    },
                    onGoToMyRecipes: {
                        recipeLink = ""
                        pastedText = ""
                        viewModel.clearImport()
                        PendingSaveDataStorage.shared.clear()
                        navigateToPreview = false
                        switchToMyRecipes?()
                    }
                )
            }
        }
        .onChange(of: viewModel.savedSuccessfully) { _, saved in
            if saved {
                // Clear the link or text after recipe is successfully saved
                recipeLink = ""
                pastedText = ""
            }
        }
        .onAppear {
            importSharedLinkIfNeeded()
        }
        .onChange(of: shareImportRouter.pendingImport) { _, _ in
            importSharedLinkIfNeeded()
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            // A link shared while another import was running is picked up afterwards
            if !isLoading {
                importSharedLinkIfNeeded()
            }
        }
    }

    private func startImport() async {
        // End editing first: a pasted link leaves the field focused, and a focused field can
        // put its text back after the link is cleared on save
        isLinkFieldFocused = false

        let entry = recipeLink == sharedLink ? "share_extension" : "pasted"

        // A whole recipe pasted into the link field is imported as text
        if RecipeImportService.firstWebUrl(in: recipeLink) == nil, recipeLink.count > 100 {
            pendingImport = .text(recipeLink, entry: entry)
            await startPendingImport()
            return
        }

        // A link import replaces any photo or text import blocked by the paywall
        pendingImport = nil

        // Free users who've used all their imports are told so, then offered the paywall.
        // The link stays in the field so the import can continue after upgrading.
        guard await SubscriptionManager.shared.canImportRecipe() else {
            Analytics.log(.importLimitReached, ["entry": entry])
            showingImportLimitAlert = true
            return
        }

        await viewModel.importRecipe(from: recipeLink, entry: entry)
        if viewModel.importedRecipe != nil {
            navigateToPreview = true
        }
    }

    /// Imports `pendingImport` (photos or text), with the same free import limit as links
    private func startPendingImport() async {
        guard let pendingImport else { return }

        // The photos or text are kept so the import can continue after upgrading
        guard await SubscriptionManager.shared.canImportRecipe() else {
            switch pendingImport {
            case .photos(_, let entry), .text(_, let entry):
                Analytics.log(.importLimitReached, ["entry": entry])
            }
            showingImportLimitAlert = true
            return
        }

        switch pendingImport {
        case .photos(let photos, let entry):
            await viewModel.importRecipe(fromPhotos: photos, entry: entry)
        case .text(let text, let entry):
            await viewModel.importRecipe(fromText: text, entry: entry)
        }
        self.pendingImport = nil
        if viewModel.importedRecipe != nil {
            navigateToPreview = true
        }
    }

    /// Closes the paywall and resumes the blocked import once the user has Premium.
    private func continueImportAfterUpgrade(_ customerInfo: CustomerInfo) {
        let subscriptionManager = SubscriptionManager.shared
        subscriptionManager.update(with: customerInfo)
        // A restore with no active subscription leaves the paywall open
        guard subscriptionManager.isPremium else { return }

        showingPaywall = false
        if pendingImport == nil {
            Task { await startImport() }
        } else {
            Task { await startPendingImport() }
        }
    }

    /// Runs the same import flow as pasting a link, choosing photos or pasting text,
    /// for what was shared via the Share Extension.
    private func importSharedLinkIfNeeded() {
        guard !viewModel.isLoading, let sharedImport = shareImportRouter.consume() else { return }

        // Leave any preview currently shown so the new recipe replaces it
        navigateToPreview = false
        viewModel.clearImport()
        PendingSaveDataStorage.shared.clear()

        switch sharedImport {
        case .link(let sharedUrl):
            recipeLink = sharedUrl
            sharedLink = sharedUrl
            Task { await startImport() }
        case .photos(let photos):
            pendingImport = .photos(photos, entry: "share_extension")
            Task { await startPendingImport() }
        case .text(let text):
            pendingImport = .text(text, entry: "share_extension")
            Task { await startPendingImport() }
        }
    }
}

// MARK: - Paste Recipe Text

/// A recipe pasted in as text, e.g. copied from the Notes app
private struct PasteRecipeTextView: View {
    @Binding var text: String
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste the whole recipe, with its ingredients and steps.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("DarkSilver"))

                TextEditor(text: $text)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .tint(Color("OrangeRed"))
                    .focused($isFocused)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color("DarkSilver"), lineWidth: 1)
                    )
            }
            .padding()
            .navigationTitle("Paste Recipe Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: onImport)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}

// MARK: - Imported Recipe Preview

struct ImportedRecipePreviewView: View {
    let recipe: ImportedRecipe
    @ObservedObject var viewModel: RecipeImportViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Image
                    if let imageUrl = recipe.imageUrl, let url = URL(string: imageUrl) {
                        CachedAsyncImage(url: url) { phase in
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
                        .frame(height: 200)
                        .clipped()
                        .cornerRadius(12)
                    }

                    // Title
                    Text(recipe.title)
                        .font(.custom("Playfair9pt-SemiBold", size: 24))

                    // Source
                    if let source = recipe.sourceName {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text("From \(source)")
                        }
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color("GraniteGray"))
                    }

                    // Time info
                    HStack(spacing: 20) {
                        if let prepTime = recipe.prepTimeMinutes {
                            VStack {
                                Text("\(prepTime)")
                                    .font(.custom("Playfair9pt-SemiBold", size: 18))
                                Text("Prep")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundColor(Color("GraniteGray"))
                            }
                        }
                        if let cookTime = recipe.cookTimeMinutes {
                            VStack {
                                Text("\(cookTime)")
                                    .font(.custom("Playfair9pt-SemiBold", size: 18))
                                Text("Cook")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundColor(Color("GraniteGray"))
                            }
                        }
                        VStack {
                            Text(recipe.servings)
                                .font(.custom("Playfair9pt-SemiBold", size: 18))
                            Text("Servings")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundColor(Color("GraniteGray"))
                        }
                    }
                    .padding(.vertical, 10)

                    // Description
                    if let description = recipe.description {
                        Text(description)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundColor(Color("GraniteGray"))
                    }

                    // Ingredients
                    if !recipe.ingredients.isEmpty {
                        Text("Ingredients")
                            .font(.custom("Playfair9pt-SemiBold", size: 20))
                            .padding(.top, 10)

                        ForEach(recipe.ingredients, id: \.self) { ingredient in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(Color("Orange"))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                Text(ingredient)
                                    .font(.custom("OpenSans-Regular", size: 14))
                            }
                        }
                    }

                    // Instructions
                    if !recipe.instructions.isEmpty {
                        Text("Instructions")
                            .font(.custom("Playfair9pt-SemiBold", size: 20))
                            .padding(.top, 10)

                        ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, instruction in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundColor(Color("Orange"))
                                    .frame(width: 24, alignment: .leading)
                                Text(instruction)
                                    .font(.custom("OpenSans-Regular", size: 14))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.clearImport()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await viewModel.saveRecipe() {
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Create Recipe View

struct CreateRecipeView: View {
    @StateObject private var viewModel = CreateRecipeViewModel()
    @FocusState private var focusedField: CreateRecipeField?
    @State private var showingCamera = false
    @State private var showingPhotoOptions = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var capturedImage: UIImage?
    @State private var navigateToPreview = false
    @Environment(\.dismiss) private var dismiss

    // Callback to switch to My Recipes tab
    var switchToMyRecipes: (() -> Void)?

    // Edit mode support
    var initialRecipe: RecipeDetail? = nil
    var isEditMode: Bool = false
    var onUpdate: ((RecipeDetail, [UIImage]) -> Void)? = nil  // Returns updated recipe and new photos

    // Editing a recipe that's already saved (own recipe, or a copy of an Explore recipe):
    // the button saves right away and the sheet stays open until it succeeds
    var onSaveChanges: ((RecipeDetail, [UIImage]) async throws -> Void)? = nil
    var saveChangesTitle = "Save Changes"
    var editNotice: String? = nil  // Shown above the form, e.g. that a copy is saved
    @State private var isSavingChanges = false

    enum CreateRecipeField: Hashable {
        case title, description, prep, cook, servings, notes
        case ingredientAmount(UUID), ingredientUnit(UUID), ingredientName(UUID)
        case step(UUID)
    }

    private static let maxPhotos = 6

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if let editNotice {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(Color("OrangeRed"))
                        Text(editNotice)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundColor(.primary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color("PeachCream"))
                    .cornerRadius(10)
                }

                // Title
                CreateRecipeTextField(
                    title: "Title",
                    placeholder: "Give your recipe a name",
                    text: $viewModel.title,
                    isRequired: true
                )
                .focused($focusedField, equals: .title)

                // Description
                CreateRecipeTextEditor(
                    title: "Description",
                    placeholder: "Describe your recipe in a few words (e.g., quick, family-favorite, or festive)",
                    text: $viewModel.description,
                    isOptional: true
                )
                .focused($focusedField, equals: .description)

                ingredientsSection

                instructionsSection

                // Time & Servings Row
                HStack {
                    // Servings
                    HStack(spacing: 10) {
                        Button(action: {
                            if let current = Int(viewModel.servings), current > 1 {
                                viewModel.servings = "\(current - 1)"
                            }
                        }) {
                            Image("minusIcon")
                                .resizable()
                                .frame(width: 33, height: 33)
                        }
                        
                        VStack(spacing: 0) {
                            Text(viewModel.servings.isEmpty ? "2" : viewModel.servings)
                                .font(.custom("Playfair9pt-Regular", size: 20))
                            Text("servings")
                                .font(.custom("Playfair9pt-Regular", size: 18))
                        }
                        
                        Button(action: {
                            if let current = Int(viewModel.servings) {
                                viewModel.servings = "\(current + 1)"
                            } else {
                                viewModel.servings = "3"
                            }
                        }) {
                            Image("plusIcon")
                                .resizable()
                                .frame(width: 33, height: 33)
                        }
                    }
                    Spacer()
                    
                    // Prep & Cook
                    HStack(spacing: 20) {
                    // Prep Time
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Prep")
                                .font(.custom("Playfair9pt-Regular", size: 20))
                            Image("timerIcon")
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 24, height: 24)
                                .foregroundColor(Color("GraniteGray"))
                        }
                        
                        TextField("mins", text: $viewModel.prepTime)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .focused($focusedField, equals: .prep)
                            .frame(width: 72, height: 35)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color("DarkSilver"), lineWidth: 1)
                            )
                    }
                    
                    // Cook Time
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Cook")
                                .font(.custom("Playfair9pt-Regular", size: 20))
                            Image("timerIcon")
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 24, height: 24)
                                .foregroundColor(Color("GraniteGray"))
                        }
                        
                        TextField("mins", text: $viewModel.cookTime)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .focused($focusedField, equals: .cook)
                            .frame(width: 72, height: 35)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color("DarkSilver"), lineWidth: 1)
                            )
                    }
                    }
                }
              

                // Notes & Tips
                CreateRecipeTextEditor(
                    title: "Notes & Tips",
                    placeholder: "Add any tips, tricks, or substitutions",
                    text: $viewModel.notes,
                    isOptional: true,
                    minLines: 3
                )
                .focused($focusedField, equals: .notes)

                photoSection

                // Error Message
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(.red)
                }

                // Preview & Save Button (or Update Preview in edit mode)
                HStack {
                    Spacer()
                    Button(action: {
                        if let onSaveChanges {
                            let updatedRecipe = viewModel.toRecipeDetail()
                            let photos = copiedPhotos()
                            Task {
                                isSavingChanges = true
                                viewModel.errorMessage = nil
                                do {
                                    try await onSaveChanges(updatedRecipe, photos)
                                } catch {
                                    viewModel.errorMessage = error.localizedDescription
                                }
                                isSavingChanges = false
                            }
                        } else if isEditMode {
                            // In edit mode, pass the updated recipe and any new photos back
                            onUpdate?(viewModel.toRecipeDetail(), copiedPhotos())
                        } else {
                            navigateToPreview = true
                        }
                    }) {
                        HStack(spacing: 8) {
                            if isSavingChanges {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            }
                            Text(onSaveChanges != nil ? saveChangesTitle : (isEditMode ? "Update Preview" : "Preview & Save"))
                                .font(.custom("OpenSans-SemiBold", size: 18))
                                .foregroundColor(.white)
                        }
                        .frame(width: isEditMode ? 180 : 164, height: 45)
                        .background(Color("Orange"))
                        .cornerRadius(10)
                    }
                    .disabled(!viewModel.isValid || isSavingChanges)
                    Spacer()
                }
                .padding(.top, 10)
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .onTapGesture {
            focusedField = nil
        }
        .onAppear {
            // Initialize from recipe if in edit mode
            if let recipe = initialRecipe {
                viewModel.initializeFrom(recipe)
            }
        }
        .navigationDestination(isPresented: $navigateToPreview) {
            RecipeDetailView(
                recipe: viewModel.toRecipeDetail(),
                mode: .preview,
                pendingPhotos: viewModel.photoImages,
                onSave: {
                    // Get ALL data from shared storage - no closure parameters!
                    let savedData = PendingSaveDataStorage.shared.retrieve()
                    guard let recipeDetail = savedData.recipe else {
                        return false
                    }
                    return await viewModel.saveRecipe(from: recipeDetail, photos: savedData.photos)
                },
                savedRecipeId: { viewModel.savedRecipeId },
                onAddMoreRecipes: {
                    // Pop to root - reset state and dismiss
                    viewModel.reset()
                    PendingSaveDataStorage.shared.clear()
                    navigateToPreview = false
                },
                onGoToMyRecipes: {
                    PendingSaveDataStorage.shared.clear()
                    navigateToPreview = false
                    switchToMyRecipes?()
                }
            )
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView(image: $capturedImage)
                .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: max(1, Self.maxPhotos - viewModel.photoImages.count),
            matching: .images
        )
        .confirmationDialog("Add Photo", isPresented: $showingPhotoOptions, titleVisibility: .visible) {
            Button("Take Photo") {
                showingCamera = true
            }
            Button("Choose from Library") {
                showingPhotoPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: viewModel.ingredientRows) { _, _ in
            // Return in a name field, or a pasted list, adds rows; move the cursor to the last one
            if let id = viewModel.splitMultilineIngredients() {
                focusedField = .ingredientName(id)
            }
        }
        .onChange(of: viewModel.instructionSteps) { _, _ in
            if let id = viewModel.splitMultilineSteps() {
                focusedField = .step(id)
            }
        }
        .onChange(of: capturedImage) { _, newImage in
            if let image = newImage {
                viewModel.photoImages.append(image)
                capturedImage = nil
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        viewModel.photoImages.append(image)
                    }
                }
                selectedPhotoItems = []
            }
        }
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CreateRecipeSectionHeader(title: "Ingredients", isRequired: true, addTitle: "Add") {
                focusedField = .ingredientAmount(viewModel.addIngredient())
            }

            ForEach($viewModel.ingredientRows) { $row in
                HStack(spacing: 8) {
                    CreateRecipeInputField(placeholder: "2", text: $row.amount)
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .ingredientAmount(row.id))
                        .onSubmit { focusedField = .ingredientUnit(row.id) }
                        .frame(width: 56)
                        .accessibilityLabel("Amount")

                    CreateRecipeInputField(placeholder: "cups", text: $row.unit)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .ingredientUnit(row.id))
                        .onSubmit { focusedField = .ingredientName(row.id) }
                        .frame(width: 76)
                        .accessibilityLabel("Unit")

                    // Multiline so Return (or pasting a list) can start the next ingredient
                    CreateRecipeInputField(placeholder: "Ingredient", text: $row.name, axis: .vertical)
                        .focused($focusedField, equals: .ingredientName(row.id))
                        .accessibilityLabel("Ingredient")

                    if viewModel.ingredientRows.count > 1 {
                        CreateRecipeDeleteButton(label: "Remove ingredient") {
                            withAnimation { viewModel.removeIngredient(row.id) }
                        }
                    }
                }
            }

            Text("Tip: Enter amount, unit, and ingredient name separately")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundColor(Color("GraniteGray"))
        }
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CreateRecipeSectionHeader(title: "Instructions", isRequired: true, addTitle: "Add Step") {
                focusedField = .step(viewModel.addStep())
            }

            ForEach(Array($viewModel.instructionSteps.enumerated()), id: \.element.id) { index, $step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color("OrangeRed")))
                        .padding(.top, 10)
                        .accessibilityHidden(true)

                    CreateRecipeInputField(
                        placeholder: "Step \(index + 1): Describe what to do",
                        text: $step.text,
                        axis: .vertical,
                        minLines: 2
                    )
                    .focused($focusedField, equals: .step(step.id))
                    .accessibilityLabel("Step \(index + 1)")

                    if viewModel.instructionSteps.count > 1 {
                        CreateRecipeDeleteButton(label: "Remove step \(index + 1)") {
                            withAnimation { viewModel.removeStep(step.id) }
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
    }

    // MARK: - Photos

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CreateRecipeSectionTitle(title: "Photo", isOptional: true)

            if viewModel.photoImages.isEmpty {
                Button {
                    showingPhotoOptions = true
                } label: {
                    VStack(spacing: 10) {
                        PhotoUploadIcon()
                        Text("Tap to upload photo")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundColor(Color("GraniteGray"))
                        Text("Up to \(Self.maxPhotos) photos")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundColor(Color("DarkSilver"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)
                    .background(PhotoUploadBackground())
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(viewModel.photoImages.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 110, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        withAnimation { viewModel.removePhoto(at: index) }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(.white, Color.black.opacity(0.55))
                                    }
                                    .padding(6)
                                    .accessibilityLabel("Remove photo \(index + 1)")
                                }
                                .overlay(alignment: .bottomLeading) {
                                    // The first photo is the recipe's main image
                                    if index == 0 {
                                        Text("Cover")
                                            .font(.custom("OpenSans-SemiBold", size: 11))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(Color.black.opacity(0.55)))
                                            .padding(6)
                                    }
                                }
                        }

                        if viewModel.photoImages.count < Self.maxPhotos {
                            Button {
                                showingPhotoOptions = true
                            } label: {
                                VStack(spacing: 6) {
                                    PhotoUploadIcon(size: 40)
                                    Text("Add")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundColor(Color("GraniteGray"))
                                }
                                .frame(width: 110, height: 110)
                                .background(PhotoUploadBackground())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add photo")
                        }
                    }
                    .padding(.vertical, 2)
                }

                Text("\(viewModel.photoImages.count) of \(Self.maxPhotos) photos")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundColor(Color("GraniteGray"))
            }
        }
    }

    /// Deep copy of the new photos BEFORE passing them to a callback, to avoid memory issues
    private func copiedPhotos() -> [UIImage] {
        viewModel.photoImages.compactMap { image in
            guard let data = image.jpegData(compressionQuality: 0.8),
                  let copy = UIImage(data: data) else {
                return nil
            }
            return copy
        }
    }
}

// MARK: - Create Recipe Section Title

/// Section title with a red asterisk for required fields or "(Optional)"
struct CreateRecipeSectionTitle: View {
    let title: String
    var isRequired = false
    var isOptional = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.custom("Playfair9pt-Regular", size: 24))
            if isRequired {
                Text("*")
                    .font(.custom("OpenSans-SemiBold", size: 18))
                    .foregroundColor(Color("OrangeRed"))
                    .accessibilityLabel("required")
            }
            if isOptional {
                Text("(Optional)")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundColor(Color("GraniteGray"))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Create Recipe Section Header

/// Section title with an orange "+ Add" button on the right
struct CreateRecipeSectionHeader: View {
    let title: String
    var isRequired = false
    let addTitle: String
    let onAdd: () -> Void

    var body: some View {
        HStack {
            CreateRecipeSectionTitle(title: title, isRequired: isRequired)
            Spacer()
            Button(action: onAdd) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text(addTitle)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color("OrangeRed")))
            }
        }
    }
}

// MARK: - Create Recipe Input Field

/// Bordered text field used for ingredient parts and steps
struct CreateRecipeInputField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var minLines = 1

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(placeholder).foregroundColor(Color("DarkSilver")),
            axis: axis
        )
        .font(.custom("OpenSans-Regular", size: 14))
        .foregroundColor(.primary)
        .lineLimit(axis == .vertical ? minLines...8 : 1...1)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 40)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color("DarkSilver"), lineWidth: 1)
        )
    }
}

// MARK: - Create Recipe Delete Button

struct CreateRecipeDeleteButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 15))
                .foregroundColor(Color("GraniteGray"))
                .frame(width: 24, height: 40)
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Photo Upload

/// Camera icon in a white circle, as on the photo upload card
struct PhotoUploadIcon: View {
    var size: CGFloat = 52

    var body: some View {
        Image(systemName: "camera")
            .font(.system(size: size * 0.38, weight: .medium))
            .foregroundColor(Color("OrangeRed"))
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white))
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

/// Soft peach card with a light border
struct PhotoUploadBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color("PeachCream").opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color("DarkSilver").opacity(0.5), lineWidth: 1)
            )
    }
}

// MARK: - Create Recipe Text Field

struct CreateRecipeTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isRequired = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CreateRecipeSectionTitle(title: title, isRequired: isRequired)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color("DarkSilver"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }

                TextField("", text: $text, axis: .vertical)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(.primary)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color("DarkSilver"), lineWidth: 1)
            )
        }
    }
}

// MARK: - Create Recipe Text Editor

struct CreateRecipeTextEditor: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isOptional = false
    var minLines = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CreateRecipeSectionTitle(title: title, isOptional: isOptional)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color("DarkSilver"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }

                TextField("", text: $text, axis: .vertical)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(.primary)
                    .lineLimit(minLines...10)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color("DarkSilver"), lineWidth: 1)
            )
        }
    }
}

// MARK: - Create Recipe Preview View

struct CreateRecipePreviewView: View {
    @ObservedObject var viewModel: CreateRecipeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    Text(viewModel.title)
                        .font(.custom("Playfair9pt-SemiBold", size: 24))

                    // Time info
                    if viewModel.prepTimeMinutes != nil || viewModel.cookTimeMinutes != nil {
                        HStack(spacing: 20) {
                            if let prep = viewModel.prepTimeMinutes {
                                VStack {
                                    Text("\(prep)")
                                        .font(.custom("Playfair9pt-SemiBold", size: 18))
                                    Text("Prep")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundColor(Color("GraniteGray"))
                                }
                            }
                            if let cook = viewModel.cookTimeMinutes {
                                VStack {
                                    Text("\(cook)")
                                        .font(.custom("Playfair9pt-SemiBold", size: 18))
                                    Text("Cook")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundColor(Color("GraniteGray"))
                                }
                            }
                            if let servings = viewModel.servingsInt {
                                VStack {
                                    Text("\(servings)")
                                        .font(.custom("Playfair9pt-SemiBold", size: 18))
                                    Text("Servings")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundColor(Color("GraniteGray"))
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }

                    // Description
                    if !viewModel.description.isEmpty {
                        Text(viewModel.description)
                            .font(.custom("Playfair9pt-Regular", size: 24))
                            .foregroundColor(Color("GraniteGray"))
                    }

                    // Ingredients
                    if !viewModel.ingredientsList.isEmpty {
                        Text("Ingredients")
                            .font(.custom("Playfair9pt-SemiBold", size: 20))
                            .padding(.top, 10)

                        ForEach(viewModel.ingredientsList, id: \.self) { ingredient in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(Color("Orange"))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                Text(ingredient)
                                    .font(.custom("OpenSans-Regular", size: 14))
                            }
                        }
                    }

                    // Instructions
                    if !viewModel.instructionsList.isEmpty {
                        Text("Instructions")
                            .font(.custom("Playfair9pt-SemiBold", size: 20))
                            .padding(.top, 10)

                        ForEach(Array(viewModel.instructionsList.enumerated()), id: \.offset) { index, instruction in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundColor(Color("Orange"))
                                    .frame(width: 24, alignment: .leading)
                                Text(instruction)
                                    .font(.custom("OpenSans-Regular", size: 14))
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Notes
                    if !viewModel.notes.isEmpty {
                        VStack(spacing: 10) {
                            Text("Notes & Tips")
                                .font(.custom("Playfair9pt-SemiBold", size: 20))

                            Text(viewModel.notes)
                                .font(.custom("OpenSans-Regular", size: 14))
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color("PeachCream"))
                        .cornerRadius(15)
                    }
                }
                .padding()
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Edit") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await viewModel.saveRecipe() {
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.isSaving)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AddNewRecipeView()
}

#Preview("Create Recipe") {
    NavigationStack {
        CreateRecipeView()
    }
}
