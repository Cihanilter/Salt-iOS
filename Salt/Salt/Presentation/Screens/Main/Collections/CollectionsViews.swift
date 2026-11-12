//
//  CollectionsViews.swift
//  Salt
//
//  Recipe collections: the row in My Recipes, collection screens and the sheets
//  for naming collections and adding recipes to them.
//

import SwiftUI

// MARK: - Collections Row (My Recipes)

/// Compact row of 92pt collection tiles, on every My Recipes tab. Shared collections show
/// small member avatars instead of a "Shared" label.
struct CollectionsRow: View {
    @ObservedObject private var manager = CollectionsManager.shared
    @State private var showingNewCollection = false

    static let tileSize: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
            HStack(alignment: .firstTextBaseline) {
                Text("Collections")
                    .font(SaltFont.h2)
                    .foregroundStyle(SaltColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if manager.collections.count > 2 {
                    NavigationLink {
                        AllCollectionsView()
                    } label: {
                        Text("See all")
                            .font(SaltFont.bodyLarge)
                            .foregroundStyle(SaltColor.textAccent)
                    }
                }
            }
            .padding(.horizontal, SaltSpacing.screenMargin)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    NewCollectionTile(size: Self.tileSize) {
                        showingNewCollection = true
                    }

                    ForEach(manager.collections) { collection in
                        NavigationLink {
                            CollectionDetailView(collectionId: collection.id)
                        } label: {
                            CollectionTile(collection: collection, size: Self.tileSize)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SaltSpacing.screenMargin)
            }
        }
        .sheet(isPresented: $showingNewCollection) {
            CollectionNameSheet(title: "New collection", actionTitle: "Create", hint: "You can invite people to it later.") { name in
                try await manager.createCollection(named: name)
            }
        }
    }
}

// MARK: - Tiles

/// Collection cover with its name, recipe count and (when shared) member avatars
struct CollectionTile: View {
    let collection: RecipeCollection
    let size: CGFloat
    @ObservedObject private var manager = CollectionsManager.shared

    /// Other people in it; the user's own avatar isn't shown on their tiles
    private var otherMembers: [CollectionMember] {
        manager.cachedMembers(of: collection.id).filter { member in
            member.userId.uuidString.lowercased() != AuthManager.shared.currentUser?.id.lowercased()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CollectionCover(imageUrls: collection.coverImageUrls, size: size)
                .padding(.bottom, 4)

            Text(collection.name)
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textPrimary)
                .lineLimit(1)

            Text(recipeCountText(collection.items.count))
                .font(SaltFont.body)
                .foregroundStyle(SaltColor.textSecondary)
                .lineLimit(1)

            // Members on their own line, under the count
            if collection.isShared {
                SaltAvatarStack(names: otherMembers.map(\.displayName), size: 20)
                    .padding(.top, 2)
            }
        }
        .frame(width: size, alignment: .leading)
        .task(id: collection.memberIds) {
            await manager.loadMembersIfNeeded(for: collection.id)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(collection.name), \(recipeCountText(collection.items.count))\(collection.isShared ? ", shared" : "")")
    }
}

/// "＋ New" tile that starts a new collection
struct NewCollectionTile: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(SaltColor.borderSubtle, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 24))
                            .foregroundStyle(SaltColor.iconAccent)
                    }
                    .padding(.bottom, 4)

                Text("New")
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textPrimary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New collection")
    }
}

/// Square cover: a 2×2 mosaic with four or more photos, otherwise the newest photo.
/// Empty: lightest peach with a gray book icon.
struct CollectionCover: View {
    let imageUrls: [String]
    let size: CGFloat
    var cornerRadius: CGFloat = 20

    var body: some View {
        Group {
            if imageUrls.count >= 4 {
                let half = (size - 2) / 2
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        photo(imageUrls[0], width: half, height: half)
                        photo(imageUrls[1], width: half, height: half)
                    }
                    HStack(spacing: 2) {
                        photo(imageUrls[2], width: half, height: half)
                        photo(imageUrls[3], width: half, height: half)
                    }
                }
            } else if let first = imageUrls.first {
                photo(first, width: size, height: size)
            } else {
                SaltColor.surfaceWarmSubtle
                    .overlay {
                        Image(systemName: "book")
                            .font(.system(size: size * 0.26))
                            .foregroundStyle(SaltColor.textSecondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func photo(_ urlString: String, width: CGFloat, height: CGFloat) -> some View {
        SaltColor.surfaceControl
            .frame(width: width, height: height)
            .overlay {
                CachedAsyncImage(url: URL(string: urlString)) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
            .clipped()
            // Clipping doesn't limit taps; keep the hidden overflow from taking nearby taps
            .contentShape(Rectangle())
    }
}

func recipeCountText(_ count: Int) -> String {
    count == 1 ? String(localized: "1 recipe") : String(localized: "\(count) recipes")
}

// MARK: - Feedback Toast

extension View {
    /// Shows a collection confirmation ("Added to Dinner ideas") with the shared toast
    func collectionToast(_ message: Binding<String?>) -> some View {
        onChange(of: message.wrappedValue) { _, newValue in
            guard let newValue else { return }
            SaltToastCenter.shared.show(newValue, duration: .seconds(2.5))
            AccessibilityNotification.Announcement(newValue).post()
            message.wrappedValue = nil
        }
    }
}

// MARK: - All Collections

/// Every collection in a grid ("See all")
struct AllCollectionsView: View {
    @ObservedObject private var manager = CollectionsManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingNewCollection = false
    /// Screen width, so two square tiles fit on any phone
    @State private var availableWidth: CGFloat = 402

    private var tileSize: CGFloat {
        min(MyRecipeCard.width, (availableWidth - 36 - 30) / 2)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [
                GridItem(.fixed(tileSize), spacing: 30, alignment: .top),
                GridItem(.fixed(tileSize), alignment: .top)
            ], spacing: 24) {
                NewCollectionTile(size: tileSize) {
                    showingNewCollection = true
                }

                ForEach(manager.collections) { collection in
                    NavigationLink {
                        CollectionDetailView(collectionId: collection.id)
                    } label: {
                        CollectionTile(collection: collection, size: tileSize)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, SaltSpacing.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, SaltSpacing.bottomTabPadding)
        }
        .background(SaltColor.surfaceScreen)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .safeAreaInset(edge: .top, spacing: 0) {
            SaltBackHeader(title: "Collections") { dismiss() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            Analytics.screen("All Collections")
        }
        .sheet(isPresented: $showingNewCollection) {
            CollectionNameSheet(title: "New collection", actionTitle: "Create", hint: "You can invite people to it later.") { name in
                try await manager.createCollection(named: name)
            }
        }
    }
}

/// Back arrow + Playfair page title, for pushed pages without a navigation bar
struct SaltBackHeader<Trailing: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(SaltColor.iconDefault)
                    .frame(width: 44, height: 44)
            }
            .padding(.leading, -12)
            .accessibilityLabel("Back")

            Text(title)
                .font(SaltFont.h1)
                .foregroundStyle(SaltColor.textPrimary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer()
            trailing()
        }
        .padding(.horizontal, SaltSpacing.screenMargin)
        .padding(.vertical, 8)
        .background(SaltColor.surfaceScreen)
    }
}

extension SaltBackHeader where Trailing == EmptyView {
    init(title: String, onBack: @escaping () -> Void) {
        self.init(title: title, onBack: onBack, trailing: { EmptyView() })
    }
}

// MARK: - Collection Detail

/// One collection: Playfair title, members as an avatar stack + counts (tap → Members),
/// the recipes, and Rename / Members / Add recipes / Delete in the native … menu.
struct CollectionDetailView: View {
    let collectionId: UUID

    @ObservedObject private var manager = CollectionsManager.shared
    @ObservedObject private var myRecipes = MyRecipesViewModel.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingRename = false
    @State private var showingAddRecipes = false
    @State private var showingDeleteAlert = false
    @State private var showingLeaveAlert = false
    @State private var showingMembers = false
    @State private var errorMessage: String?

    private var collection: RecipeCollection? {
        manager.collection(id: collectionId)
    }

    /// Owners can rename and delete; members can leave
    private var isOwner: Bool {
        collection?.isOwnedByCurrentUser ?? false
    }

    /// Viewers can't add or remove recipes
    private var canEdit: Bool {
        collection?.canCurrentUserEdit ?? false
    }

    private var members: [CollectionMember] {
        manager.cachedMembers(of: collectionId)
    }

    /// The collection's recipes, using the latest version of the user's own recipes
    /// (e.g. after an edit) when My Recipes has it
    private var items: [MyRecipeItem] {
        (collection?.items ?? []).map { item in
            if case .own(let recipe) = item,
               let latest = myRecipes.userRecipes.first(where: { $0.id == recipe.id }) {
                return .own(latest)
            }
            return item
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let collection {
                    Text(collection.name)
                        .font(SaltFont.h1)
                        .foregroundStyle(SaltColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, SaltSpacing.screenMargin)

                    summary(collection)
                        .padding(.horizontal, SaltSpacing.screenMargin)
                        .padding(.top, 12)

                    if items.isEmpty {
                        SaltEmptyState(
                            systemImage: canEdit ? "plus" : "book",
                            title: String(localized: "Nothing in \(collection.name) yet"),
                            message: canEdit
                                ? String(localized: "Add recipes you already have, or pick this collection when you save a new one.")
                                : String(localized: "Recipes added to this collection will show up here."),
                            buttonTitle: canEdit ? String(localized: "Add recipes") : nil,
                            action: canEdit ? { showingAddRecipes = true } : nil
                        )
                        .padding(.horizontal, SaltSpacing.screenMargin)
                        .padding(.top, 88)
                    } else {
                        LazyVGrid(columns: MyRecipeCard.gridColumns, spacing: 24) {
                            ForEach(items) { item in
                                MyRecipeCard(item: item, addedBy: addedBy(item))
                                    .contextMenu {
                                        if canEdit {
                                            Button(role: .destructive) {
                                                remove(item)
                                            } label: {
                                                Label("Remove from Collection", systemImage: "minus.circle")
                                            }
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, SaltSpacing.screenMargin)
                        .padding(.top, SaltSpacing.section)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, SaltSpacing.bottomTabPadding)
        }
        .background(SaltColor.surfaceScreen)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await manager.load()
        }
        .task {
            // Picks up recipes others added to a shared collection
            await manager.load()
            await manager.loadMembersIfNeeded(for: collectionId)
        }
        .onAppear {
            Analytics.screen("Collection")
        }
        .navigationDestination(isPresented: $showingMembers) {
            CollectionMembersView(collectionId: collectionId)
        }
        .alert("Leave \u{201C}\(collection?.name ?? "")\u{201D}?", isPresented: $showingLeaveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                Task {
                    do {
                        try await manager.leave(collectionId)
                        dismiss()
                    } catch {
                        errorMessage = "Couldn't leave the collection."
                    }
                }
            }
        } message: {
            Text("You won't see its recipes anymore. Recipes you added stay in it.")
        }
        .sheet(isPresented: $showingRename) {
            CollectionNameSheet(
                title: "Rename collection",
                actionTitle: "Save",
                initialName: collection?.name ?? ""
            ) { name in
                try await manager.renameCollection(collectionId, to: name)
                return nil
            }
        }
        .sheet(isPresented: $showingAddRecipes) {
            AddRecipesToCollectionSheet(collectionId: collectionId)
        }
        .alert("Delete \u{201C}\(collection?.name ?? "")\u{201D}?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await manager.deleteCollection(collectionId)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text(collection?.isShared == true
                 ? "Only the collection is deleted, and everyone in it loses access. Your recipes stay in My Recipes."
                 : "Only the collection is deleted. Your recipes stay in My Recipes.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(SaltColor.iconDefault)
                    .frame(width: 44, height: 44)
            }
            .padding(.leading, -12)
            .accessibilityLabel("Back")

            Spacer()

            Menu {
                if isOwner {
                    Section {
                        Button(action: { showingRename = true }) {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(action: { showingMembers = true }) {
                            Label("Members", systemImage: "person.2")
                        }
                    }
                    Section {
                        Button(action: { showingAddRecipes = true }) {
                            Label("Add recipes", systemImage: "plus")
                        }
                    }
                    Section {
                        Button(role: .destructive, action: { showingDeleteAlert = true }) {
                            Label("Delete collection", systemImage: "trash")
                        }
                    }
                } else {
                    Section {
                        Button(action: { showingMembers = true }) {
                            Label("Members", systemImage: "person.2")
                        }
                        if canEdit {
                            Button(action: { showingAddRecipes = true }) {
                                Label("Add recipes", systemImage: "plus")
                            }
                        }
                    }
                    Section {
                        Button(role: .destructive, action: { showingLeaveAlert = true }) {
                            Label("Leave collection", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SaltColor.iconDefault)
                    .frame(width: 44, height: 44)
            }
            .padding(.trailing, -12)
            .accessibilityLabel("Collection options")
        }
        .padding(.horizontal, SaltSpacing.screenMargin)
        .background(SaltColor.surfaceScreen)
    }

    /// "D C E  3 members · 13 recipes" (tap → Members); just the count before it's shared
    @ViewBuilder private func summary(_ collection: RecipeCollection) -> some View {
        let count = recipeCountText(items.count)
        if collection.isShared {
            Button { showingMembers = true } label: {
                HStack(spacing: 10) {
                    SaltAvatarStack(names: members.map(\.displayName), size: 26, maxVisible: 5)
                    Text("\(collection.peopleCount) members · \(count)")
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the members")
        } else {
            Text(count)
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textSecondary)
        }
    }

    /// Recipes others added carry that person's avatar; the user's own carry none
    private func addedBy(_ item: MyRecipeItem) -> CollectionMember? {
        guard case .own(let recipe) = item, !recipe.isByCurrentUser else { return nil }
        return members.first { $0.userId == recipe.userId }
    }

    private func remove(_ item: MyRecipeItem) {
        Task {
            do {
                try await manager.removeRecipe(CollectionRecipeRef(item), from: collectionId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Name Sheet

/// New collection / Rename: one field, focused with the keyboard open; the button is
/// disabled until a name is typed. Names are limited to 20 characters.
struct CollectionNameSheet: View {
    let title: String
    let actionTitle: String
    var initialName = ""
    var hint: String? = nil
    /// Returns the collection when one was created, so it can offer "Cook together"
    let onSave: (String) async throws -> RecipeCollection?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// The collection just made, when "Cook together" is offered: the sheet becomes it
    @State private var inviteCollection: RecipeCollection?
    @FocusState private var isFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        if let inviteCollection {
            CookTogetherView(collectionId: inviteCollection.id, collectionName: inviteCollection.name) { skipped in
                if skipped {
                    Analytics.log(.collectionPromptSkipped, ["step": "invite", "source": "new_collection"])
                }
                dismiss()
            }
            .padding(.top, 12)
            .saltFittedSheet()
            .onAppear {
                Analytics.log(.collectionPromptShown, ["step": "invite", "source": "new_collection"])
            }
        } else {
            nameForm
        }
    }

    private var nameForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(SaltFont.h2)
                .foregroundStyle(SaltColor.textPrimary)
                .padding(.bottom, 24)

            TextField("", text: $name, prompt: Text("Collection name").foregroundStyle(SaltColor.textSecondary))
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(save)
                .frame(height: 28)
                .saltInput(isFocused: isFocused, hasError: errorMessage != nil)

            Group {
                if let errorMessage {
                    SaltFieldError(message: errorMessage)
                } else if let hint {
                    Text(hint)
                        .font(SaltFont.body)
                        .foregroundStyle(SaltColor.textSecondary)
                }
            }
            .padding(.top, 12)

            Button(action: save) {
                SaltButtonLabel(title: actionTitle, isLoading: isSaving)
            }
            .buttonStyle(.salt())
            .disabled(trimmedName.isEmpty)
            .allowsHitTesting(!isSaving)
            .padding(.top, 24)
        }
        .saltFittedSheet()
        .onChange(of: name) { _, newValue in
            // Typing or pasting past the limit is cut off
            if newValue.count > RecipeCollection.maxNameLength {
                name = String(newValue.prefix(RecipeCollection.maxNameLength))
            }
            errorMessage = nil
        }
        .onAppear {
            name = initialName
            isFocused = true
        }
    }

    private func save() {
        guard !trimmedName.isEmpty, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let created = try await onSave(trimmedName)
                if let created, CookTogether.shouldOffer() {
                    CookTogether.recordOffer()
                    isFocused = false
                    withAnimation { inviteCollection = created }
                } else {
                    dismiss()
                }
            } catch {
                errorMessage = "Couldn't save. Please try again."
                print("❌ Collection save failed: \(error)")
            }
            isSaving = false
        }
    }
}

// MARK: - Add to Collection Sheet

/// Picks the collections a recipe is in (from the saved toast, the … menu and Explore).
/// "New collection" is always first; a recipe can be in several (peach + ✓ like chips).
/// Done closes and confirms with "Added to Dinner ideas".
struct AddToCollectionSheet: View {
    let ref: CollectionRecipeRef
    /// Where it was opened, for analytics
    let source: String

    @ObservedObject private var manager = CollectionsManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var busyIds: Set<UUID> = []
    @State private var showingNewCollection = false
    @State private var errorMessage: String?
    /// Collections it was added to while the sheet was open, for the confirmation
    @State private var addedNames: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add to collection")
                .font(SaltFont.h2)
                .foregroundStyle(SaltColor.textPrimary)
                .padding(.horizontal, SaltSpacing.screenMargin)
                .padding(.top, 32)
                .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    Button(action: { showingNewCollection = true }) {
                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(SaltColor.borderSubtle, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                                .frame(width: 52, height: 52)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: 18))
                                        .foregroundStyle(SaltColor.iconAccent)
                                }
                            Text("New collection")
                                .font(SaltFont.bodyLarge)
                                .foregroundStyle(SaltColor.textPrimary)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, SaltSpacing.screenMargin)

                    // Collections the user can only view aren't offered
                    ForEach(manager.collections.filter(\.canCurrentUserEdit)) { collection in
                        SelectableRow(
                            isSelected: collection.contains(ref),
                            isBusy: busyIds.contains(collection.id),
                            action: { toggle(collection.id) }
                        ) {
                            CollectionCover(imageUrls: collection.coverImageUrls, size: 52, cornerRadius: 12)
                        } text: {
                            Text(collection.name)
                                .font(SaltFont.bodyLarge)
                                .foregroundStyle(SaltColor.textPrimary)
                            Text(recipeCountText(collection.items.count))
                                .font(SaltFont.body)
                                .foregroundStyle(SaltColor.textSecondary)
                        }
                        .padding(.horizontal, SaltSpacing.screenMargin)
                    }
                }
            }

            Button("Done") { finish() }
                .buttonStyle(.salt())
                .padding(.horizontal, SaltSpacing.screenMargin)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .background(SaltColor.surfaceScreen)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(SaltRadius.sheet)
        .task {
            if !manager.hasLoaded { await manager.load() }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showingNewCollection) {
            CollectionNameSheet(title: "New collection", actionTitle: "Create", hint: "You can invite people to it later.") { name in
                // A collection made from here gets the recipe right away
                let collection = try await manager.createCollection(named: name)
                try await manager.addRecipe(ref, to: collection.id, source: source)
                await saveExploreRecipeIfNeeded()
                addedNames.append(collection.name)
                return collection
            }
        }
    }

    private func finish() {
        if addedNames.count == 1, let name = addedNames.first {
            SaltToastCenter.shared.show(String(localized: "Added to \(name)"), duration: .seconds(2.5))
        } else if addedNames.count > 1 {
            SaltToastCenter.shared.show(String(localized: "Added to \(addedNames.count) collections"), duration: .seconds(2.5))
        }
        dismiss()
    }

    private func toggle(_ collectionId: UUID) {
        guard let collection = manager.collection(id: collectionId) else { return }
        let wasAdded = collection.contains(ref)
        busyIds.insert(collectionId)
        Task {
            do {
                try await manager.toggle(ref, in: collectionId, source: source)
                if wasAdded {
                    addedNames.removeAll { $0 == collection.name }
                } else {
                    addedNames.append(collection.name)
                    await saveExploreRecipeIfNeeded()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            busyIds.remove(collectionId)
        }
    }

    /// Adding an Explore recipe to a collection also saves it
    private func saveExploreRecipeIfNeeded() async {
        guard case .explore(let recipeId) = ref, !BookmarkManager.shared.isBookmarked(recipeId) else { return }
        _ = await BookmarkManager.shared.toggleBookmark(for: recipeId)
    }
}

/// Row selected like a chip: peach with a white ✓ circle; unselected: an empty circle
struct SelectableRow<Leading: View, Label: View>: View {
    let isSelected: Bool
    var isBusy = false
    let action: () -> Void
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var text: () -> Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                leading()
                VStack(alignment: .leading, spacing: 2) {
                    text()
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                ZStack {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else if isSelected {
                        Circle().fill(Color.white)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SaltColor.textPrimary)
                    } else {
                        Circle().stroke(SaltColor.borderSubtle, lineWidth: 1.5)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous)
                        .fill(SaltColor.surfaceWarm)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .padding(.horizontal, -8)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Add Recipes Sheet

/// Full-height picker of the user's recipes (search + multi-select). The button counts the
/// selection: "Add 3 recipes".
struct AddRecipesToCollectionSheet: View {
    let collectionId: UUID

    @ObservedObject private var manager = CollectionsManager.shared
    @ObservedObject private var myRecipes = MyRecipesViewModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selection: [CollectionRecipeRef] = []
    @State private var isAdding = false
    @State private var errorMessage: String?

    private var collection: RecipeCollection? {
        manager.collection(id: collectionId)
    }

    /// Recipes not in the collection yet
    private var available: [MyRecipeItem] {
        myRecipes.items(for: .all, searchFiltered: false).filter { item in
            !(collection?.contains(CollectionRecipeRef(item)) ?? false)
        }
    }

    private var items: [MyRecipeItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return available }
        return available.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SaltSheetHeader(title: "Add to \(collection?.name ?? "collection")") {
                Button("Cancel") { dismiss() }
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textSecondary)
            }
            .padding(.horizontal, SaltSpacing.screenMargin)
            .padding(.top, 32)
            .padding(.bottom, 16)

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(SaltColor.textSecondary)
                TextField("", text: $searchText, prompt: Text("Search my recipes").foregroundStyle(SaltColor.textSecondary))
            }
            .frame(height: 28)
            .saltInput()
            .padding(.horizontal, SaltSpacing.screenMargin)
            .padding(.bottom, 12)

            if available.isEmpty {
                Text("All your recipes are already in this collection, or you haven't saved any yet.")
                    .font(SaltFont.body)
                    .foregroundStyle(SaltColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 40)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            let ref = CollectionRecipeRef(item)
                            SelectableRow(isSelected: selection.contains(ref), action: { toggle(ref) }) {
                                CollectionCover(
                                    imageUrls: item.displayImageUrl.isEmpty ? [] : [item.displayImageUrl],
                                    size: 56,
                                    cornerRadius: 12
                                )
                            } text: {
                                Text(item.title)
                                    .font(SaltFont.bodyLarge)
                                    .foregroundStyle(SaltColor.textPrimary)
                                Text(item.durationText)
                                    .font(SaltFont.body)
                                    .foregroundStyle(SaltColor.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, SaltSpacing.screenMargin)
                    .padding(.top, 4)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            Button(action: addSelected) {
                SaltButtonLabel(
                    title: selection.count == 1 ? String(localized: "Add 1 recipe") : String(localized: "Add \(selection.count) recipes"),
                    isLoading: isAdding
                )
            }
            .buttonStyle(.salt())
            .disabled(selection.isEmpty)
            .allowsHitTesting(!isAdding)
            .padding(.horizontal, SaltSpacing.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(SaltColor.surfaceScreen)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(SaltRadius.sheet)
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func toggle(_ ref: CollectionRecipeRef) {
        if let index = selection.firstIndex(of: ref) {
            selection.remove(at: index)
        } else {
            selection.append(ref)
        }
    }

    private func addSelected() {
        guard let collection, !selection.isEmpty else { return }
        isAdding = true
        Task {
            var added = 0
            for ref in selection {
                do {
                    try await manager.addRecipe(ref, to: collectionId, source: "collection_picker")
                    added += 1
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            isAdding = false
            guard errorMessage == nil else { return }
            SaltToastCenter.shared.show(
                added == 1 ? String(localized: "Added to \(collection.name)") : String(localized: "Added \(added) recipes to \(collection.name)"),
                duration: .seconds(2.5)
            )
            dismiss()
        }
    }
}

extension MyRecipeItem {
    var durationText: String {
        switch self {
        case .own(let recipe): recipe.durationText
        case .saved(let recipe): recipe.durationText
        }
    }
}
