//
//  CollectionsViews.swift
//  Salt
//
//  Recipe collections: the row in My Recipes, collection screens and the sheets
//  for naming collections and adding recipes to them.
//

import SwiftUI

// MARK: - Collections Row (My Recipes)

/// Horizontal row of collections under the My Recipes search bar. Shows every collection
/// whatever the All / Imports / Saved toggle is set to.
struct CollectionsRow: View {
    @ObservedObject private var manager = CollectionsManager.shared
    @State private var showingNewCollection = false

    static let tileSize: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Collections")
                    .font(.custom("Playfair9pt-SemiBold", size: 20))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !manager.collections.isEmpty {
                    NavigationLink {
                        AllCollectionsView()
                    } label: {
                        Text("See all")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundColor(Color("OrangeRed"))
                    }
                }
            }
            .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    NewCollectionTile(size: Self.tileSize) {
                        showingNewCollection = true
                    }

                    if manager.collections.isEmpty && manager.hasLoaded {
                        Text("Group recipes into collections,\nlike Dinner or Kids")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundColor(Color("GraniteGray"))
                            .frame(height: Self.tileSize)
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
                .padding(.horizontal, 18)
            }
        }
        .sheet(isPresented: $showingNewCollection) {
            CollectionNameSheet(title: "New Collection", actionTitle: "Create") { name in
                try await manager.createCollection(named: name)
            }
        }
    }
}

// MARK: - Tiles

/// Collection cover with its name and recipe count
struct CollectionTile: View {
    let collection: RecipeCollection
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CollectionCover(imageUrls: collection.coverImageUrls, size: size)

            VStack(alignment: .leading, spacing: 1) {
                Text(collection.name)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(recipeCountText(collection.items.count))
                    .lineLimit(1)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundColor(Color("GraniteGray"))

                // On its own line so the count isn't cut off in narrow tiles
                if collection.isShared {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                        Text("Shared")
                    }
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundColor(Color("Orange"))
                }
            }
            .frame(width: size, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "＋ New" tile that starts a new collection
struct NewCollectionTile: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color("DarkSilver"), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundColor(Color("OrangeRed"))
                    }

                Text("New")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New collection")
    }
}

/// Square cover: a 2×2 mosaic with four or more photos, otherwise the newest photo
struct CollectionCover: View {
    let imageUrls: [String]
    let size: CGFloat

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
                Color("LightGrayishPink")
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.system(size: size * 0.24))
                            .foregroundColor(Color("GraniteGray"))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func photo(_ urlString: String, width: CGFloat, height: CGFloat) -> some View {
        Color("LightGrayishPink")
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
    }
}

private func recipeCountText(_ count: Int) -> String {
    count == 1 ? "1 recipe" : "\(count) recipes"
}

// MARK: - Feedback Toast

/// Short confirmation at the bottom ("Added to Atlas"), hidden after a moment
private struct CollectionToast: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color("Orange"))
                    Text(message)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.8)))
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(message)  // A new message replaces the old one
                .task(id: message) {
                    // VoiceOver reads it out, since it disappears on its own
                    AccessibilityNotification.Announcement(message).post()
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { self.message = nil }
                }
            }
        }
    }
}

private extension View {
    func collectionToast(_ message: Binding<String?>) -> some View {
        modifier(CollectionToast(message: message))
    }
}

// MARK: - All Collections

/// Every collection in a grid ("See all")
struct AllCollectionsView: View {
    @ObservedObject private var manager = CollectionsManager.shared
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
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Analytics.screen("All Collections")
        }
        .sheet(isPresented: $showingNewCollection) {
            CollectionNameSheet(title: "New Collection", actionTitle: "Create") { name in
                try await manager.createCollection(named: name)
            }
        }
    }
}

// MARK: - Collection Detail

/// One collection's recipes, with Add Recipes, Rename and Delete
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
    @StateObject private var invite = CollectionInviteState()
    @State private var errorMessage: String?

    private var collection: RecipeCollection? {
        manager.collection(id: collectionId)
    }

    /// Owners can rename, delete and invite; members can leave
    private var isOwner: Bool {
        collection?.isOwnedByCurrentUser ?? false
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
        Group {
            if collection == nil {
                // Deleted
                Color.clear
            } else if items.isEmpty {
                emptyState
            } else {
                recipeGrid
            }
        }
        .navigationTitle(collection?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { showingAddRecipes = true }) {
                        Label("Add Recipes", systemImage: "plus")
                    }
                    if isOwner {
                        Button(action: { Task { await invite.create(for: collectionId, reset: false) } }) {
                            Label("Invite People", systemImage: "person.badge.plus")
                        }
                        .disabled(collection?.isFull ?? true)
                    }
                    if isOwner == false || collection?.isShared == true {
                        Button(action: { showingMembers = true }) {
                            Label("Members", systemImage: "person.2")
                        }
                    }
                    if isOwner {
                        Button(action: { showingRename = true }) {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive, action: { showingDeleteAlert = true }) {
                            Label("Delete Collection", systemImage: "trash")
                        }
                    } else {
                        Button(role: .destructive, action: { showingLeaveAlert = true }) {
                            Label("Leave Collection", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.primary)
                }
                .accessibilityLabel("Collection options")
            }
        }
        .refreshable {
            await manager.load()
        }
        .task {
            // Picks up recipes others added to a shared collection
            await manager.load()
        }
        .onAppear {
            Analytics.screen("Collection")
        }
        .navigationDestination(isPresented: $showingMembers) {
            CollectionMembersView(collectionId: collectionId)
        }
        .overlay(alignment: .bottom) {
            if invite.isCreating {
                CreatingLinkToast()
            }
        }
        .sheet(item: $invite.shareItem) { item in
            ActivityView(items: [item.message, item.url])
                .presentationDetents([.medium, .large])
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
                title: "Rename Collection",
                actionTitle: "Save",
                initialName: collection?.name ?? ""
            ) { name in
                try await manager.renameCollection(collectionId, to: name)
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
                 ? "Everyone in it loses access. The recipes stay in My Recipes."
                 : "The recipes stay in My Recipes.")
        }
        .alert("Something Went Wrong", isPresented: Binding(
            get: { (errorMessage ?? invite.errorMessage) != nil },
            set: { if !$0 { errorMessage = nil; invite.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? invite.errorMessage ?? "")
        }
    }

    private var recipeGrid: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text(recipeCountText(items.count))
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("GraniteGray"))
                    .padding(.horizontal, 18)

                LazyVGrid(columns: MyRecipeCard.gridColumns, spacing: 30) {
                    ForEach(items) { item in
                        MyRecipeCard(item: item)
                            .contextMenu {
                                Button(role: .destructive) {
                                    remove(item)
                                } label: {
                                    Label("Remove from Collection", systemImage: "minus.circle")
                                }
                            }
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.vertical, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 52))
                .foregroundColor(Color("DarkSilver"))
            Text("No recipes yet")
                .font(.custom("Playfair9pt-SemiBold", size: 22))
            Text("Add recipes from My Recipes,\nor from any recipe's \u{22EF} menu")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(Color("GraniteGray"))
                .multilineTextAlignment(.center)
            Button(action: { showingAddRecipes = true }) {
                Text("Add Recipes")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color("Orange"))
                    .cornerRadius(10)
            }
            .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
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

/// Name field for creating or renaming a collection, limited to 20 characters
struct CollectionNameSheet: View {
    let title: String
    let actionTitle: String
    var initialName = ""
    let onSave: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Collection name", text: $name)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color("DarkSilver"), lineWidth: 1)
                    )

                HStack {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundColor(Color("OrangeRed"))
                    }
                    Spacer()
                    Text("\(name.count)/\(RecipeCollection.maxNameLength)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundColor(Color("GraniteGray"))
                        .monospacedDigit()
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(actionTitle, action: save)
                            .disabled(trimmedName.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.height(190)])
        .onChange(of: name) { _, newValue in
            // Typing or pasting past the limit is cut off
            if newValue.count > RecipeCollection.maxNameLength {
                name = String(newValue.prefix(RecipeCollection.maxNameLength))
            }
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
                try await onSave(trimmedName)
                dismiss()
            } catch {
                errorMessage = "Couldn't save. Please try again."
                print("❌ Collection save failed: \(error)")
            }
            isSaving = false
        }
    }
}

// MARK: - Add to Collection Sheet

/// Picks the collections a recipe is in (from a recipe's ⋯ menu or a long press)
struct AddToCollectionSheet: View {
    let ref: CollectionRecipeRef
    /// Where it was opened, for analytics
    let source: String

    @ObservedObject private var manager = CollectionsManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var busyIds: Set<UUID> = []
    @State private var showingNewCollection = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Button(action: { showingNewCollection = true }) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color("DarkSilver"), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                            .frame(width: 48, height: 48)
                            .overlay {
                                Image(systemName: "plus")
                                    .foregroundColor(Color("OrangeRed"))
                            }
                        Text("New Collection")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundColor(.primary)
                    }
                }

                ForEach(manager.collections) { collection in
                    Button(action: { toggle(collection.id) }) {
                        HStack(spacing: 12) {
                            CollectionCover(imageUrls: collection.coverImageUrls, size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(collection.name)
                                    .font(.custom("OpenSans-SemiBold", size: 16))
                                    .foregroundColor(.primary)
                                Text(recipeCountText(collection.items.count))
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundColor(Color("GraniteGray"))
                            }
                            Spacer()
                            if busyIds.contains(collection.id) {
                                ProgressView()
                            } else {
                                Image(systemName: collection.contains(ref) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundColor(collection.contains(ref) ? Color("Orange") : Color("DarkSilver"))
                            }
                        }
                    }
                    .disabled(busyIds.contains(collection.id))
                    .accessibilityAddTraits(collection.contains(ref) ? .isSelected : [])
                }
            }
            .listStyle(.plain)
            .collectionToast($toastMessage)
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Something Went Wrong", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            if !manager.hasLoaded { await manager.load() }
        }
        .sheet(isPresented: $showingNewCollection) {
            CollectionNameSheet(title: "New Collection", actionTitle: "Create") { name in
                // A collection made from here gets the recipe right away
                let collection = try await manager.createCollection(named: name)
                try await manager.addRecipe(ref, to: collection.id, source: source)
                withAnimation { toastMessage = "Added to \(collection.name)" }
            }
        }
    }

    private func toggle(_ collectionId: UUID) {
        guard let collection = manager.collection(id: collectionId) else { return }
        let wasAdded = collection.contains(ref)
        busyIds.insert(collectionId)
        Task {
            do {
                try await manager.toggle(ref, in: collectionId, source: source)
                withAnimation {
                    toastMessage = wasAdded ? "Removed from \(collection.name)" : "Added to \(collection.name)"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            busyIds.remove(collectionId)
        }
    }
}

// MARK: - Add Recipes Sheet

/// Picks recipes from My Recipes to put in a collection
struct AddRecipesToCollectionSheet: View {
    let collectionId: UUID

    @ObservedObject private var manager = CollectionsManager.shared
    @ObservedObject private var myRecipes = MyRecipesViewModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var busyRefs: Set<CollectionRecipeRef> = []
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    private var collection: RecipeCollection? {
        manager.collection(id: collectionId)
    }

    private var items: [MyRecipeItem] {
        let all = myRecipes.items(for: .all, searchFiltered: false)
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if myRecipes.items(for: .all, searchFiltered: false).isEmpty {
                    Text("Import, create or save recipes first,\nthen add them here")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color("GraniteGray"))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(items) { item in
                        let ref = CollectionRecipeRef(item)
                        let isAdded = collection?.contains(ref) ?? false
                        Button(action: { toggle(ref) }) {
                            HStack(spacing: 12) {
                                CollectionCover(
                                    imageUrls: item.displayImageUrl.isEmpty ? [] : [item.displayImageUrl],
                                    size: 52
                                )
                                Text(item.title)
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                Spacer()
                                if busyRefs.contains(ref) {
                                    ProgressView()
                                } else {
                                    Image(systemName: isAdded ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundColor(isAdded ? Color("Orange") : Color("DarkSilver"))
                                }
                            }
                        }
                        .disabled(busyRefs.contains(ref))
                        .accessibilityAddTraits(isAdded ? .isSelected : [])
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search recipes")
                }
            }
            .collectionToast($toastMessage)
            .navigationTitle("Add to \(collection?.name ?? "Collection")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Something Went Wrong", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func toggle(_ ref: CollectionRecipeRef) {
        guard let collection else { return }
        let wasAdded = collection.contains(ref)
        busyRefs.insert(ref)
        Task {
            do {
                try await manager.toggle(ref, in: collectionId, source: "collection_picker")
                withAnimation {
                    toastMessage = wasAdded ? "Removed from \(collection.name)" : "Added to \(collection.name)"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            busyRefs.remove(ref)
        }
    }
}
