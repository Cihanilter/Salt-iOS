
import SwiftUI
import PhotosUI
import RevenueCat
import RevenueCatUI

// MARK: - Add New Recipe View

struct AddNewRecipeView: View {
    /// Create (write a recipe from scratch) is pushed on top of the Import screen
    @State private var showingCreate = false
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
        ImportRecipeView(
            recipeLink: $recipeLink,
            requestedTab: $requestedTab,
            switchToMyRecipes: switchToMyRecipes,
            switchToCreate: { showingCreate = true }
        )
        .background(SaltColor.surfaceScreen)
        .navigationDestination(isPresented: $showingCreate) {
            CreateRecipeView(switchToMyRecipes: {
                showingCreate = false
                switchToMyRecipes?()
            })
        }
        .onAppear {
            if shareImportRouter.pendingImport != nil {
                showingCreate = false
            }
        }
        .onChange(of: shareImportRouter.pendingImport) { _, sharedImport in
            // Shared link, photos or text arrived - back to Import so it can pick it up
            if sharedImport != nil {
                showingCreate = false
            }
        }
        .onChange(of: requestedTab, initial: true) { _, tab in
            // e.g. Create manually on the Explore banner; Import and Link are handled by ImportRecipeView
            guard let tab else { return }
            showingCreate = tab == .create
            if tab == .create { requestedTab = nil }
        }
    }
}

// MARK: - Tab Enum

/// What to open on the Add Recipe tab when switching to it from elsewhere
enum AddRecipeTab {
    case create
    /// The Add Recipe page itself
    case `import`
    /// The Link sheet, e.g. "Import a recipe" on Explore's no-results state
    case link
}

// MARK: - Import Recipe View

/// The Add Recipe page: the ways to import, the import sheets and the import flow.
/// A successful import is saved straight away and opens on the recipe page with the saved toast.
struct ImportRecipeView: View {
    @Binding var recipeLink: String
    @Binding var requestedTab: AddRecipeTab?
    @StateObject private var viewModel = RecipeImportViewModel()
    @ObservedObject private var shareImportRouter = ShareImportRouter.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Last link received from the Share Extension, so analytics can tell shared links from pasted ones
    @State private var sharedLink: String?
    @State private var pastedText = ""

    // Sheets
    @State private var activeSheet: ImportSheet?
    /// Opened once the current sheet is gone; two sheets can't show at once
    @State private var afterDismiss: AfterDismiss?
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingPaywall = false
    @State private var showingShareTutorial = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var capturedImage: UIImage?

    // Import state
    /// The running import
    @State private var importTask: Task<Void, Never>?
    /// Full-screen loading screen, for photo and Share Extension imports (link and text
    /// imports load inside their sheet)
    @State private var showingImportProgress = false
    @State private var importProgressKind: ImportProgressKind = .link
    /// Photo or text import being run; kept while the paywall is shown so the import can continue after upgrading
    @State private var pendingImport: PendingImport?
    @State private var linkFailure: ImportFailure?
    @State private var photoFailure: ImportFailure?
    @State private var textFailure: ImportFailure?
    @State private var freeImportsLeft: Int?
    /// The recipe just imported, shown as a preview to save or edit
    @State private var openedRecipe: OpenedRecipe?

    // Page state
    @State private var clipboardHasLink = false
    /// Clipboard contents already imported from the "You copied a link" card
    @AppStorage("addRecipe.consumedPasteboardChange") private var consumedPasteboardChange = -1

    /// A recipe can span a few pages or screenshots (e.g. ingredients on one, steps on the next)
    private static let maxImportPhotos = 5

    /// One a day, from the date: no state to keep
    private static let subtitles: [LocalizedStringKey] = [
        "No ads, no long stories. Just the recipe.",
        "Turn any recipe into a clean, ready-to-cook one.",
        "From your feed to your kitchen.",
        "Saw it on Instagram? Save it here.",
        "All your recipes, finally in one place."
    ]

    private static var todaysSubtitle: LocalizedStringKey {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return subtitles[day % subtitles.count]
    }

    enum ImportSheet: String, Identifiable {
        case link, photo, text, importLimit
        var id: String { rawValue }
    }

    private enum AfterDismiss {
        case sheet(ImportSheet)
        case camera
        case library
        case paywall
    }

    /// An import without a link, and how it started (for analytics)
    private enum PendingImport {
        case photos([UIImage], entry: String)
        case text(String, entry: String)
    }

    private struct OpenedRecipe: Identifiable, Hashable {
        let id = UUID()
        let recipe: RecipeDetail
        let notice: String?

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private var isImportingLink: Bool {
        viewModel.isLoading && pendingImport == nil
    }

    private var isImportingText: Bool {
        guard viewModel.isLoading, case .text = pendingImport else { return false }
        return true
    }

    // Callback to switch to My Recipes tab
    var switchToMyRecipes: (() -> Void)?
    // Opens Create, for writing a recipe from scratch
    var switchToCreate: (() -> Void)?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if clipboardHasLink {
                    clipboardCard
                        .padding(.top, 24)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Import from")
                        .font(SaltFont.playfair(22))
                        .foregroundStyle(SaltColor.textPrimary)
                    Spacer()
                    if let freeImportsLeft {
                        Text("\(freeImportsLeft) of \(RevenueCatConfig.freeImportLimit) free imports left")
                            .font(SaltFont.body)
                            .foregroundStyle(SaltColor.textSecondary)
                    }
                }
                .padding(.top, SaltSpacing.section)

                sourcesCard
                    .padding(.top, SaltSpacing.titleToContent)

                AddRecipeSourceRow(
                    systemImage: "pencil",
                    title: "Write your own",
                    subtitle: "A family recipe or your own creation"
                ) { switchToCreate?() }
                .background(cardBorder)
                .padding(.top, 12)

                // Always shown: sharing is the fastest way in, and it's easy to forget how
                shareCard
                    .padding(.top, 12)
            }
            .padding(.horizontal, SaltSpacing.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, SaltSpacing.bottomTabPadding)
            .animation(.easeInOut(duration: 0.2), value: clipboardHasLink)
        }
        .background(SaltColor.surfaceScreen)
        .sheet(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
            sheetContent(sheet)
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
        .fullScreenCover(isPresented: $showingImportProgress) {
            ImportProgressView(kind: importProgressKind, onCancel: cancelImport)
        }
        .fullScreenCover(isPresented: $showingShareTutorial) {
            ShareTutorialView(context: .explore, sources: [OnboardingStorage.preferredSocialSource]) { outcome in
                showingShareTutorial = false
                if outcome == .pasteLink {
                    present(.link)
                }
            }
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
        .navigationDestination(item: $openedRecipe) { opened in
            // Not saved yet: Save recipe / Edit recipe stay at the bottom; saving shows the
            // "Saved to My Recipes" toast (and, the first time, the collection prompt)
            RecipeDetailView(
                recipe: opened.recipe,
                mode: .preview,
                previewNotice: opened.notice,
                onSave: {
                    // The recipe on screen (edits included) is in shared storage
                    let savedData = PendingSaveDataStorage.shared.retrieve()
                    guard let recipeDetail = savedData.recipe else { return false }
                    let saved = await viewModel.saveRecipe(from: recipeDetail, photos: savedData.photos)
                    if saved { viewModel.clearImport() }
                    return saved
                },
                savedRecipeId: { viewModel.savedRecipeId }
            )
        }
        .onChange(of: capturedImage) { _, image in
            guard let image else { return }
            capturedImage = nil
            pendingImport = .photos([image], entry: "camera")
            runImport { await startPendingImport() }
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            runImport {
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
        .onAppear {
            checkClipboard()
            importSharedLinkIfNeeded()
            applyRequestedTab()
            // An import only counts once it's saved, which happens on the preview
            Task { await refreshFreeImportsLeft() }
        }
        .task(id: subscriptionManager.isPremium) {
            await refreshFreeImportsLeft()
        }
        .onChange(of: requestedTab) { _, _ in applyRequestedTab() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { checkClipboard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            checkClipboard()
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

    // MARK: - Page

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add New Recipe")
                .font(SaltFont.h1)
                .foregroundStyle(SaltColor.textPrimary)
            Text(Self.todaysSubtitle)
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textSecondary)
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(SaltColor.borderSubtle, lineWidth: 1)
    }

    private var sourcesCard: some View {
        VStack(spacing: 0) {
            AddRecipeSourceRow(
                systemImage: "link",
                title: "Link",
                subtitle: "Paste a link from Instagram, TikTok, YouTube or any recipe site"
            ) { present(.link) }

            Rectangle().fill(SaltColor.borderSubtle).frame(height: 1)

            AddRecipeSourceRow(
                systemImage: "camera",
                title: "Photo",
                subtitle: "Cookbook page, screenshot or handwritten card"
            ) { present(.photo) }

            Rectangle().fill(SaltColor.borderSubtle).frame(height: 1)

            AddRecipeSourceRow(
                systemImage: "doc.text",
                title: "Notes & text",
                subtitle: "Paste from Notes, messages or email"
            ) { present(.text) }
        }
        .background(cardBorder)
        .disabled(viewModel.isLoading && !isImportingLink && !isImportingText)
    }

    /// Shown only when the clipboard has a link (checked without reading it, so no paste alert)
    private var clipboardCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "clipboard")
                .font(.system(size: 17))
                .foregroundStyle(SaltColor.iconAccent)
                .frame(width: 40, height: 40)
                .background(SaltColor.surfaceScreen, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("You copied a link")
                    .font(SaltFont.bodyLargeStrong)
                    .foregroundStyle(SaltColor.textPrimary)
                Text("Import it in one tap")
                    .font(SaltFont.body)
                    .foregroundStyle(SaltColor.textSecondary)
            }

            Spacer(minLength: 8)

            SystemPasteButton(style: .primary) { pasted in
                consumedPasteboardChange = UIPasteboard.general.changeCount
                clipboardHasLink = false
                recipeLink = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                linkFailure = nil
                present(.link)
                runImport { await startImport() }
            }
            .frame(width: 76, height: 38)
        }
        .padding(14)
        .background(SaltColor.surfaceWarm, in: RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous)
                .stroke(SaltColor.actionPrimary, lineWidth: 1)
        )
    }

    private var shareCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16))
                .foregroundStyle(SaltColor.iconAccent)
                .frame(width: 32, height: 32)
                .background(SaltColor.surfaceScreen, in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text("Fastest way: share to Salt")
                    .font(SaltFont.h3)
                    .foregroundStyle(SaltColor.textPrimary)
                Text("From Instagram, TikTok or any website, tap Share and choose Salt. Set it up once in 30 seconds.")
                    .font(SaltFont.body)
                    .foregroundStyle(SaltColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show me how") { showingShareTutorial = true }
                    .buttonStyle(.salt(.text, size: .small))
                    // Keeps the 44pt tap area without it adding to the card's height
                    .padding(.vertical, -6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SaltColor.surfaceWarm, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Sheets

    @ViewBuilder private func sheetContent(_ sheet: ImportSheet) -> some View {
        switch sheet {
        case .link:
            LinkImportSheet(
                link: $recipeLink,
                isImporting: isImportingLink,
                failure: linkFailure,
                freeImportsLeft: freeImportsLeft,
                onImport: { runImport { await startImport() } },
                onClearFailure: { linkFailure = nil },
                onUseScreenshot: { present(.photo) },
                onPasteAsText: { present(.text) }
            )
        case .photo:
            PhotoImportSheet(
                maxPhotos: Self.maxImportPhotos,
                failure: photoFailure,
                onTakePhoto: {
                    afterDismiss = .camera
                    activeSheet = nil
                },
                onChooseFromLibrary: {
                    afterDismiss = .library
                    activeSheet = nil
                }
            )
        case .text:
            TextImportSheet(
                text: $pastedText,
                isImporting: isImportingText,
                failure: textFailure,
                freeImportsLeft: freeImportsLeft,
                onImport: {
                    pendingImport = .text(pastedText, entry: "pasted")
                    runImport { await startPendingImport() }
                },
                onClearFailure: { textFailure = nil }
            )
        case .importLimit:
            PremiumFeatureSheet(
                title: String(localized: "You've used your \(RevenueCatConfig.freeImportLimit) free imports"),
                message: limitMessage,
                onTryPremium: {
                    afterDismiss = .paywall
                    activeSheet = nil
                },
                onNotNow: { activeSheet = nil }
            )
        }
    }

    private var limitMessage: String {
        switch pendingImport {
        case .photos: String(localized: "Go Premium for unlimited imports.\nYour photos are saved.")
        case .text: String(localized: "Go Premium for unlimited imports.\nYour text is saved.")
        case nil: String(localized: "Go Premium for unlimited imports.\nYour link is saved.")
        }
    }

    /// Shows a sheet, replacing the one on screen (it opens once the current one is gone)
    private func present(_ sheet: ImportSheet) {
        if sheet == .photo { photoFailure = nil }
        if activeSheet == nil {
            activeSheet = sheet
        } else if activeSheet != sheet {
            afterDismiss = .sheet(sheet)
            activeSheet = nil
        }
    }

    private func handleSheetDismiss() {
        let next = afterDismiss
        afterDismiss = nil
        switch next {
        case .sheet(let sheet): activeSheet = sheet
        case .camera: showingCamera = true
        case .library: showingPhotoPicker = true
        case .paywall: showingPaywall = true
        case nil: break
        }
    }

    // MARK: - Page state

    /// Whether the clipboard holds a link, without reading it (no iOS paste alert)
    private func checkClipboard() {
        let pasteboard = UIPasteboard.general
        let hasLink = pasteboard.hasURLs && pasteboard.changeCount != consumedPasteboardChange
        if hasLink != clipboardHasLink {
            clipboardHasLink = hasLink
        }
    }

    private func refreshFreeImportsLeft() async {
        freeImportsLeft = await subscriptionManager.freeImportsLeft()
    }

    private func applyRequestedTab() {
        guard requestedTab == .link || requestedTab == .import else { return }
        if requestedTab == .link { present(.link) }
        requestedTab = nil
    }

    // MARK: - Import

    private func startImport() async {
        let entry = recipeLink == sharedLink ? "share_extension" : "pasted"

        // A whole recipe pasted into the link field is imported as text
        if RecipeImportService.firstWebUrl(in: recipeLink) == nil, recipeLink.count > 100 {
            pastedText = recipeLink
            pendingImport = .text(recipeLink, entry: entry)
            present(.text)
            await startPendingImport()
            return
        }

        // A link import replaces any photo or text import blocked by the paywall
        pendingImport = nil
        linkFailure = nil

        // The link stays in the field so the import can continue after upgrading
        guard await SubscriptionManager.shared.canImportRecipe() else {
            Analytics.log(.importLimitReached, ["entry": entry])
            present(.importLimit)
            return
        }

        // Shared links load on the full-screen loading screen; pasted ones inside the Link sheet
        let usesLoadingScreen = activeSheet != .link
        if usesLoadingScreen {
            importProgressKind = .link
            showingImportProgress = true
        }
        await viewModel.importRecipe(from: recipeLink, entry: entry)
        await finishImport(usesLoadingScreen: usesLoadingScreen) {
            linkFailure = $0
            present(.link)
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
            present(.importLimit)
            return
        }

        // Pasted text loads inside the Text sheet; photos and shared text on the loading screen
        var usesLoadingScreen = true
        switch pendingImport {
        case .photos(let photos, _):
            importProgressKind = .photos(photos)
        case .text(_, let entry):
            importProgressKind = .note
            usesLoadingScreen = entry == "share_extension" || activeSheet != .text
        }
        textFailure = nil
        if usesLoadingScreen { showingImportProgress = true }

        switch pendingImport {
        case .photos(let photos, let entry):
            await viewModel.importRecipe(fromPhotos: photos, entry: entry)
        case .text(let text, let entry):
            await viewModel.importRecipe(fromText: text, entry: entry)
        }
        let finished = pendingImport
        if viewModel.importedRecipe != nil {
            self.pendingImport = nil
        }
        await finishImport(usesLoadingScreen: usesLoadingScreen) { failure in
            self.pendingImport = nil
            switch finished {
            case .photos:
                photoFailure = failure
                present(.photo)
            case .text(let text, _):
                pastedText = text
                textFailure = failure
                present(.text)
            }
        }
    }

    /// Opens a successful import as a preview (saved from there); a failure goes back to its
    /// sheet with the error. The import stays in the view model until it's saved.
    private func finishImport(usesLoadingScreen _: Bool, onFailure: (ImportFailure) -> Void) async {
        guard !Task.isCancelled else { return }

        var failure: ImportFailure?
        if let imported = viewModel.importedRecipe {
            pendingOpen = OpenedRecipe(recipe: imported.toRecipeDetail(), notice: notice(for: imported))
            recipeLink = ""
            pastedText = ""
        } else if let error = viewModel.lastError {
            failure = ImportFailure(error)
        }

        await refreshFreeImportsLeft()

        // A sheet can't open while the loading screen is still on top
        if showingImportProgress {
            showingImportProgress = false
            try? await Task.sleep(for: .seconds(0.5))
        }

        if let failure {
            onFailure(failure)
        } else if pendingOpen != nil {
            if activeSheet != nil {
                activeSheet = nil
                // Lets the sheet slide away before the recipe page is pushed
                try? await Task.sleep(for: .seconds(0.35))
            }
            openImportedRecipeIfReady()
        }
    }

    /// Imported; waiting for the sheet or loading screen to close
    @State private var pendingOpen: OpenedRecipe?

    private func openImportedRecipeIfReady() {
        guard let pendingOpen else { return }
        self.pendingOpen = nil
        PendingSaveDataStorage.shared.clear()
        openedRecipe = pendingOpen
    }

    /// Asks the user to check recipes that were pieced together from a video or read from a photo
    private func notice(for recipe: ImportedRecipe) -> String? {
        if recipe.isFromVideoAudio {
            return String(localized: "This recipe wasn't in the post's caption, so we put it together from what's said in the video. Some ingredients, amounts or steps may be missing. You can fix anything with Edit recipe below.")
        }
        if recipe.origin == .photo {
            return String(localized: "We read this recipe from your photo. Please check the amounts and steps; you can fix anything with Edit recipe below.")
        }
        return nil
    }

    /// Runs an import as a task the loading screen can cancel
    private func runImport(_ work: @escaping @MainActor () async -> Void) {
        importTask?.cancel()
        importTask = Task { await work() }
    }

    /// Cancel on the loading screen: stops the import and stays on Add Recipe
    private func cancelImport() {
        importTask?.cancel()
        importTask = nil
        pendingImport = nil
        showingImportProgress = false
    }

    /// Closes the paywall and resumes the blocked import once the user has Premium.
    private func continueImportAfterUpgrade(_ customerInfo: CustomerInfo) {
        let subscriptionManager = SubscriptionManager.shared
        subscriptionManager.update(with: customerInfo)
        // A restore with no active subscription leaves the paywall open
        guard subscriptionManager.isPremium else { return }

        showingPaywall = false
        if pendingImport == nil {
            runImport { await startImport() }
        } else {
            runImport { await startPendingImport() }
        }
    }

    /// Runs the same import flow as pasting a link, choosing photos or pasting text,
    /// for what was shared via the Share Extension.
    private func importSharedLinkIfNeeded() {
        guard !viewModel.isLoading, let sharedImport = shareImportRouter.consume() else { return }

        // Leave any recipe currently shown so the new one replaces it
        openedRecipe = nil
        activeSheet = nil
        viewModel.clearImport()
        PendingSaveDataStorage.shared.clear()

        switch sharedImport {
        case .link(let sharedUrl):
            recipeLink = sharedUrl
            sharedLink = sharedUrl
            runImport { await startImport() }
        case .photos(let photos):
            pendingImport = .photos(photos, entry: "share_extension")
            runImport { await startPendingImport() }
        case .text(let text):
            pendingImport = .text(text, entry: "share_extension")
            runImport { await startPendingImport() }
        }
    }
}

// MARK: - Source Row

/// One way to add a recipe: pink icon circle, title, one line on what it's for, chevron
private struct AddRecipeSourceRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(SaltColor.iconDefault)
                    .frame(width: 42, height: 42)
                    .background(SaltColor.surfacePink, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SaltFont.openSans(17))
                        .foregroundStyle(SaltColor.textPrimary)
                    Text(subtitle)
                        .font(SaltFont.body)
                        .foregroundStyle(SaltColor.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SaltColor.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Create Recipe View

/// Create and Edit form (Figma "Create form — Final"). Title is the only required field.
/// Create: "Preview & Save" opens the preview (same layout as the recipe page) first.
/// Edit: "Save changes" saves straight away.
struct CreateRecipeView: View {
    @StateObject private var viewModel = CreateRecipeViewModel()
    @FocusState private var focusedField: CreateRecipeField?
    @State private var showingCamera = false
    @State private var showingPhotoOptions = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var capturedImage: UIImage?
    @State private var navigateToPreview = false
    @State private var showsTitleError = false
    @State private var showingDiscardAlert = false
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
    var saveChangesTitle = "Save changes"
    var editNotice: String? = nil  // Shown above the form, e.g. that a copy is saved
    /// Back in a sheet (edit); nil when pushed (create), where back pops the form
    var onCancel: (() -> Void)? = nil
    @State private var isSavingChanges = false
    /// Shown as an alert: the form is long, so a message at its bottom would go unseen
    @State private var saveChangesError: String?

    enum CreateRecipeField: Hashable {
        case title, description, prep, cook, servings, notes
        case ingredientAmount(UUID), ingredientUnit(UUID), ingredientName(UUID)
        case step(UUID)
    }

    private static let maxPhotos = 6

    private var screenTitle: String {
        isEditMode ? String(localized: "Edit Recipe") : String(localized: "New Recipe")
    }

    private var mainActionTitle: String {
        if onSaveChanges != nil { return saveChangesTitle }
        return isEditMode ? String(localized: "Update preview") : String(localized: "Preview & Save")
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SaltSpacing.section) {
                    if let editNotice {
                        PreviewNoticeBanner(text: editNotice)
                    }

                    titleSection
                        .id(CreateRecipeField.title)

                    CreateRecipeMultilineField(
                        title: "Description",
                        isOptional: true,
                        placeholder: "Describe your recipe in a few words (e.g., quick, family favorite, festive)",
                        text: $viewModel.description,
                        isFocused: focusedField == .description
                    )
                    .focused($focusedField, equals: .description)

                    timeAndServingsSection

                    ingredientsSection

                    instructionsSection

                    CreateRecipeMultilineField(
                        title: "Notes & tips",
                        isOptional: true,
                        placeholder: "Add any tips, tricks or substitutions",
                        text: $viewModel.notes,
                        isFocused: focusedField == .notes
                    )
                    .focused($focusedField, equals: .notes)

                    photoSection

                    if let error = viewModel.errorMessage, !showsTitleError {
                        SaltFieldError(message: error)
                    }
                }
                .padding(.horizontal, SaltSpacing.screenMargin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                mainAction(scrollTo: proxy)
            }
        }
        .background(SaltColor.surfaceScreen)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if viewModel.savedSuccessfully {
                // Saved from the preview: back to Add Recipe with an empty form
                viewModel.reset()
                dismiss()
                return
            }
            // Initialize from recipe if in edit mode
            if let recipe = initialRecipe, viewModel.title.isEmpty {
                viewModel.initializeFrom(recipe)
            }
        }
        .alert(isEditMode ? "Discard changes?" : "Discard this recipe?", isPresented: $showingDiscardAlert) {
            Button("Keep editing", role: .cancel) { }
            Button("Discard", role: .destructive) { leave() }
        } message: {
            Text(isEditMode ? "Your changes won't be saved." : "What you've written won't be saved.")
        }
        .alert("Couldn't Save Changes", isPresented: Binding(
            get: { saveChangesError != nil },
            set: { if !$0 { saveChangesError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveChangesError ?? "")
        }
        .navigationDestination(isPresented: $navigateToPreview) {
            RecipeDetailView(
                recipe: viewModel.toRecipeDetail(),
                mode: .preview,
                editReturnsToForm: true,
                pendingPhotos: viewModel.photoImages,
                onSave: {
                    // Get ALL data from shared storage - no closure parameters!
                    let savedData = PendingSaveDataStorage.shared.retrieve()
                    guard let recipeDetail = savedData.recipe else {
                        return false
                    }
                    return await viewModel.saveRecipe(from: recipeDetail, photos: savedData.photos)
                },
                savedRecipeId: { viewModel.savedRecipeId }
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
        .confirmationDialog("Add photo", isPresented: $showingPhotoOptions, titleVisibility: .hidden) {
            if CameraView.isAvailable {
                Button("Take photo") { showingCamera = true }
            }
            Button("Choose from library") { showingPhotoPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: viewModel.title) { _, _ in
            if showsTitleError { showsTitleError = false }
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

    // MARK: - Header & Main Action

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                focusedField = nil
                if viewModel.hasUnsavedChanges {
                    showingDiscardAlert = true
                } else {
                    leave()
                }
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(SaltColor.iconDefault)
                    .frame(width: 44, height: 44)
            }
            .padding(.leading, -12)
            .accessibilityLabel("Back")

            Text(screenTitle)
                .font(SaltFont.h2)
                .foregroundStyle(SaltColor.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer()
        }
        .padding(.horizontal, SaltSpacing.screenMargin)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(SaltColor.surfaceScreen)
    }

    private func mainAction(scrollTo proxy: ScrollViewProxy) -> some View {
        Button {
            submit(proxy)
        } label: {
            SaltButtonLabel(title: mainActionTitle, isLoading: isSavingChanges)
        }
        .buttonStyle(.salt())
        .allowsHitTesting(!isSavingChanges)
        .padding(.horizontal, SaltSpacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            SaltColor.surfaceScreen
                .overlay(alignment: .top) {
                    Rectangle().fill(SaltColor.surfaceControl).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// Without a title: scroll up to it and mark it. Otherwise preview, update or save.
    private func submit(_ proxy: ScrollViewProxy) {
        guard viewModel.isValid else {
            withAnimation {
                showsTitleError = true
                proxy.scrollTo(CreateRecipeField.title, anchor: .top)
            }
            focusedField = .title
            return
        }
        focusedField = nil

        if let onSaveChanges {
            let updatedRecipe = viewModel.toRecipeDetail()
            let photos = copiedPhotos()
            Task {
                isSavingChanges = true
                do {
                    try await onSaveChanges(updatedRecipe, photos)
                } catch {
                    saveChangesError = error.localizedDescription
                }
                isSavingChanges = false
            }
        } else if isEditMode {
            // In edit mode, pass the updated recipe and any new photos back
            onUpdate?(viewModel.toRecipeDetail(), copiedPhotos())
        } else {
            navigateToPreview = true
        }
    }

    private func leave() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
            CreateRecipeSectionTitle(title: "Title")

            TextField("", text: $viewModel.title, prompt: Text("Give your recipe a name").foregroundStyle(SaltColor.textSecondary), axis: .vertical)
                .lineLimit(1...3)
                .submitLabel(.next)
                .focused($focusedField, equals: .title)
                .saltInput(isFocused: focusedField == .title, hasError: showsTitleError)

            if showsTitleError {
                Text("Add a title to save your recipe.")
                    .font(SaltFont.body)
                    .foregroundStyle(SaltColor.textDestructive)
            }
        }
    }

    // MARK: - Time & Servings

    private var timeAndServingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            CreateRecipeSectionTitle(title: "Time & servings", isOptional: true)
                .padding(.bottom, -4)

            HStack(spacing: 12) {
                minutesField(label: "Prep time", text: $viewModel.prepTime, field: .prep)
                minutesField(label: "Cook time", text: $viewModel.cookTime, field: .cook)
            }

            HStack {
                Text("Servings")
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textPrimary)
                Spacer()
                let servings = Int(viewModel.servings) ?? 2
                SaltStepper(
                    label: servings == 1 ? String(localized: "1 serving") : String(localized: "\(servings) servings"),
                    canDecrement: servings > 1,
                    canIncrement: servings < 99,
                    onDecrement: { viewModel.servings = "\(max(1, servings - 1))" },
                    onIncrement: { viewModel.servings = "\(min(99, servings + 1))" }
                )
                .padding(.trailing, -7)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Servings")
                .accessibilityValue("\(servings)")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: viewModel.servings = "\(min(99, servings + 1))"
                    case .decrement: viewModel.servings = "\(max(1, servings - 1))"
                    default: break
                    }
                }
            }
        }
    }

    /// Minutes field showing "15 min"
    private func minutesField(label: LocalizedStringKey, text: Binding<String>, field: CreateRecipeField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(SaltFont.body)
                .foregroundStyle(SaltColor.textSecondary)
            HStack(spacing: 4) {
                TextField("", text: text, prompt: Text("0").foregroundStyle(SaltColor.textSecondary))
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: field)
                    .fixedSize()
                Text("min")
                    .foregroundStyle(text.wrappedValue.isEmpty ? SaltColor.textSecondary : SaltColor.textPrimary)
                Spacer(minLength: 0)
            }
            .saltInput(isFocused: focusedField == field)
            .contentShape(Rectangle())
            .onTapGesture { focusedField = field }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
            CreateRecipeSectionTitle(title: "Ingredients")

            ForEach($viewModel.ingredientRows) { $row in
                HStack(alignment: .top, spacing: 8) {
                    TextField("", text: $row.amount, prompt: Text("1").foregroundStyle(SaltColor.textSecondary))
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .ingredientAmount(row.id))
                        .onSubmit { focusedField = .ingredientName(row.id) }
                        .saltInput(isFocused: focusedField == .ingredientAmount(row.id))
                        .frame(width: 60)
                        .accessibilityLabel("Amount")

                    CreateRecipeUnitPicker(unit: $row.unit)
                        .frame(width: 92)

                    // Multiline so Return (or pasting a list) can start the next ingredient
                    TextField("", text: $row.name, prompt: Text("Ingredient").foregroundStyle(SaltColor.textSecondary), axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focusedField, equals: .ingredientName(row.id))
                        .saltInput(isFocused: focusedField == .ingredientName(row.id))
                        .accessibilityLabel("Ingredient")

                    CreateRecipeDeleteButton(label: "Remove ingredient") {
                        withAnimation { viewModel.removeIngredient(row.id) }
                    }
                    .opacity(viewModel.ingredientRows.count > 1 || !row.line.isEmpty ? 1 : 0)
                    .disabled(viewModel.ingredientRows.count <= 1 && row.line.isEmpty)
                }
            }

            CreateRecipeAddButton(title: "Add ingredient") {
                focusedField = .ingredientAmount(viewModel.addIngredient())
            }

            Text("Tip: paste a whole list and Salt will split it into rows.")
                .font(SaltFont.caption)
                .foregroundStyle(SaltColor.textSecondary)
        }
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
            CreateRecipeSectionTitle(title: "Instructions")

            ForEach(Array($viewModel.instructionSteps.enumerated()), id: \.element.id) { index, $step in
                HStack(alignment: .top, spacing: 12) {
                    StepNumber(number: index + 1)
                        .accessibilityHidden(true)

                    TextField(
                        "",
                        text: $step.text,
                        prompt: Text(index == 0 ? "Describe the first step" : "Describe the next step")
                            .foregroundStyle(SaltColor.textSecondary),
                        axis: .vertical
                    )
                    .lineLimit(3...10)
                    .focused($focusedField, equals: .step(step.id))
                    .saltInput(isFocused: focusedField == .step(step.id))
                    .accessibilityLabel("Step \(index + 1)")
                    .contextMenu {
                        if viewModel.instructionSteps.count > 1 {
                            Button("Remove step", systemImage: "trash", role: .destructive) {
                                withAnimation { viewModel.removeStep(step.id) }
                            }
                        }
                    }
                }
            }

            CreateRecipeAddButton(title: "Add step") {
                focusedField = .step(viewModel.addStep())
            }
        }
    }

    // MARK: - Photos

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
            CreateRecipeSectionTitle(title: "Photo", isOptional: true)

            if viewModel.photoImages.isEmpty {
                Button {
                    focusedField = nil
                    showingPhotoOptions = true
                } label: {
                    VStack(spacing: 8) {
                        PhotoUploadIcon()
                            .padding(.bottom, 4)
                        Text("Add a cover photo")
                            .font(SaltFont.bodyLarge)
                            .foregroundStyle(SaltColor.textPrimary)
                        Text("You can add it later, after you cook · up to \(Self.maxPhotos)")
                            .font(SaltFont.caption)
                            .foregroundStyle(SaltColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
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
                                .clipShape(RoundedRectangle(cornerRadius: SaltRadius.input, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        withAnimation { viewModel.removePhoto(at: index) }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(SaltColor.iconDefault)
                                            .frame(width: 24, height: 24)
                                            .background(Color.white.opacity(0.92), in: Circle())
                                            .frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("Remove photo \(index + 1)")
                                }
                                .overlay(alignment: .bottomLeading) {
                                    // The first photo is the recipe's main image
                                    if index == 0 {
                                        Text("Cover")
                                            .font(SaltFont.captionStrong)
                                            .foregroundStyle(SaltColor.textPrimary)
                                            .padding(.horizontal, 8)
                                            .frame(height: 22)
                                            .background(Color.white.opacity(0.92), in: Capsule())
                                            .padding(6)
                                    }
                                }
                        }

                        if viewModel.photoImages.count < Self.maxPhotos {
                            Button {
                                showingPhotoOptions = true
                            } label: {
                                PhotoUploadIcon(size: 40)
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
                    .font(SaltFont.caption)
                    .foregroundStyle(SaltColor.textSecondary)
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

/// Form label for full-page forms: Playfair 22, with a quiet gray "Optional"
struct CreateRecipeSectionTitle: View {
    let title: LocalizedStringKey
    var isOptional = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(SaltFont.labelControl)
                .foregroundStyle(SaltColor.textPrimary)
            if isOptional {
                Text("Optional")
                    .font(SaltFont.body)
                    .foregroundStyle(SaltColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Multiline Field

struct CreateRecipeMultilineField: View {
    let title: LocalizedStringKey
    var isOptional = false
    let placeholder: String
    @Binding var text: String
    var isFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
            CreateRecipeSectionTitle(title: title, isOptional: isOptional)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(SaltColor.textSecondary), axis: .vertical)
                .lineLimit(3...10)
                .saltInput(isFocused: isFocused)
        }
    }
}

// MARK: - Unit Picker

/// "cups ⌄" menu of common units; keeps an unusual unit from an edited recipe
struct CreateRecipeUnitPicker: View {
    @Binding var unit: String

    private static let units = ["cups", "cup", "tbsp", "tsp", "g", "kg", "ml", "l", "oz", "lb", "pinch", "clove", "can", "piece"]

    private var options: [String] {
        let trimmed = unit.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || Self.units.contains(trimmed) ? Self.units : [trimmed] + Self.units
    }

    var body: some View {
        Menu {
            Picker("Unit", selection: $unit) {
                Text("No unit").tag("")
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(unit.isEmpty ? String(localized: "Unit") : unit)
                    .foregroundStyle(unit.isEmpty ? SaltColor.textSecondary : SaltColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SaltColor.textPrimary)
            }
            .saltInput()
        }
        .accessibilityLabel("Unit")
        .accessibilityValue(unit.isEmpty ? "None" : unit)
    }
}

// MARK: - Add Button

/// Small Secondary button with an orange +, e.g. "+ Add ingredient"
struct CreateRecipeAddButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SaltColor.iconAccent)
                Text(title)
            }
        }
        .buttonStyle(.salt(.secondary, size: .small))
    }
}

// MARK: - Create Recipe Delete Button

struct CreateRecipeDeleteButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 15))
                .foregroundStyle(SaltColor.textSecondary)
                .frame(width: 28, height: 50)
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Photo Upload

/// Orange camera icon in a white circle, as on the photo upload card
struct PhotoUploadIcon: View {
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: "camera")
            .font(.system(size: size * 0.38))
            .foregroundStyle(SaltColor.iconAccent)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white))
    }
}

/// Peach card with a dashed outline
struct PhotoUploadBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous)
            .fill(SaltColor.surfaceWarm)
            .overlay(
                RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous)
                    .stroke(SaltColor.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AddNewRecipeView()
    }
}

#Preview("Create Recipe") {
    NavigationStack {
        CreateRecipeView()
    }
}
