//
//  SaveToCollectionPrompt.swift
//  Salt
//
//  Shown right after a recipe is imported or created: offers to put it in a collection.
//  If the user makes a new collection here, it then offers to invite someone to it,
//  so it becomes a shared cookbook.
//

import SwiftUI

struct SaveToCollectionPrompt: View {
    let ref: CollectionRecipeRef

    init(ref: CollectionRecipeRef) {
        self.ref = ref
    }

    /// `step` is only for previews; the prompt always starts at pick
    fileprivate init(ref: CollectionRecipeRef, startingAt step: Step) {
        self.ref = ref
        _step = State(initialValue: step)
    }

    fileprivate enum Step: Equatable {
        case pick
        case name
        /// The collection just made here
        case invite(collectionId: UUID, name: String)

        var analyticsName: String {
            switch self {
            case .pick: "pick"
            case .name: "name"
            case .invite: "invite"
            }
        }
    }

    /// Set when the user taps Not now; the prompt isn't shown again on this device
    /// (cleared on sign out, see `resetOptOut()`)
    private static let optedOutKey = "collectionPromptOptedOut"

    /// Whether to offer the prompt after a save
    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: optedOutKey)
    }

    /// Asks again for the next account signed in on this device
    static func resetOptOut() {
        UserDefaults.standard.removeObject(forKey: optedOutKey)
    }

    @ObservedObject private var manager = CollectionsManager.shared
    @StateObject private var invite = CollectionInviteState()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: Step = .pick
    @State private var name = ""
    @State private var busyId: UUID?
    @State private var isCreating = false
    @State private var addedTo: String?
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .pick: pickStep
            case .name: nameStep
            case .invite(let collectionId, let collectionName): inviteStep(collectionId: collectionId, name: collectionName)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            if !manager.hasLoaded { await manager.load() }
        }
        .onAppear {
            Analytics.log(.collectionPromptShown, ["step": step.analyticsName])
        }
        .onChange(of: step) { _, newStep in
            Analytics.log(.collectionPromptShown, ["step": newStep.analyticsName])
        }
        .sheet(item: $invite.shareItem, onDismiss: { dismiss() }) { item in
            ActivityView(items: [item.message, item.url])
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .bottom) {
            if invite.isCreating {
                CreatingLinkToast()
            }
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

    // MARK: - Pick a Collection

    private var pickStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Add to a collection?")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    Button(action: { goTo(.name) }) {
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
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    ForEach(manager.collections) { collection in
                        collectionRow(collection)
                    }
                }
            }

            secondaryButton("Not now") {
                // Once is enough: don't ask after later saves
                UserDefaults.standard.set(true, forKey: Self.optedOutKey)
                skip()
            }
        }
        .overlay(alignment: .bottom) {
            if let addedTo {
                Label("Added to \(addedTo)", systemImage: "checkmark.circle.fill")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func collectionRow(_ collection: RecipeCollection) -> some View {
        Button(action: { add(to: collection) }) {
            HStack(spacing: 12) {
                CollectionCover(imageUrls: collection.coverImageUrls, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.name)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundColor(.primary)
                    Text(collection.items.count == 1 ? "1 recipe" : "\(collection.items.count) recipes")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundColor(Color("GraniteGray"))
                }
                Spacer()
                if busyId == collection.id {
                    ProgressView()
                } else {
                    Image(systemName: collection.contains(ref) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(collection.contains(ref) ? Color("Orange") : Color("DarkSilver"))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busyId != nil || collection.contains(ref))
    }

    // MARK: - Name a New Collection

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                header(title: "New collection", subtitle: "Give it a name. You can change it later.")
                Spacer()
                Button(action: { goTo(.pick) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Back")
            }

            VStack(alignment: .trailing, spacing: 6) {
                TextField("Collection name", text: $name)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit(createCollection)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color("DarkSilver"), lineWidth: 1))
                Text("\(name.count)/\(RecipeCollection.maxNameLength)")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundColor(Color("GraniteGray"))
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            primaryButton("Create and add", isLoading: isCreating, isEnabled: !trimmedName.isEmpty) {
                createCollection()
            }
        }
        .onAppear { isNameFocused = true }
        .onChange(of: name) { _, newValue in
            // Typing or pasting past the limit is cut off
            if newValue.count > RecipeCollection.maxNameLength {
                name = String(newValue.prefix(RecipeCollection.maxNameLength))
            }
        }
    }

    // MARK: - Invite

    private func inviteStep(collectionId: UUID, name collectionName: String) -> some View {
        VStack(spacing: 16) {
            // Two people sharing a cookbook
            HStack(spacing: -14) {
                personCircle("person.fill", color: Color("PeachCream"))
                Image("saltAppIcon")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white, lineWidth: 3))
                    .zIndex(1)
                personCircle("person.fill", color: Color("LightGrayishPink"))
            }
            .padding(.top, 8)
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Cook together")
                    .font(.custom("Playfair9pt-SemiBold", size: 24))
                Text("Invite your partner, friends or family to \u{201C}\(collectionName)\u{201D}. They can see, add and remove recipes, so it becomes your shared cookbook.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("GraniteGray"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            primaryButton("Invite someone", isLoading: invite.isCreating, isEnabled: true) {
                Task { await invite.create(for: collectionId, reset: false) }
            }
            secondaryButton("Maybe later") { skip() }
        }
        .frame(maxWidth: .infinity)
    }

    private func personCircle(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 22))
            .foregroundColor(Color("GraniteGray"))
            .frame(width: 56, height: 56)
            .background(Circle().fill(color))
            .overlay(Circle().stroke(Color.white, lineWidth: 3))
    }

    // MARK: - Building Blocks

    private func header(title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.custom("Playfair9pt-SemiBold", size: 24))
            if let subtitle {
                Text(subtitle)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("GraniteGray"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func primaryButton(_ title: String, isLoading: Bool, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                }
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 16))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color("Orange").opacity(isEnabled ? 1 : 0.4)))
        }
        .disabled(!isEnabled || isLoading)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.custom("OpenSans-Regular", size: 15))
            .foregroundColor(Color("GraniteGray"))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
    }

    // MARK: - Actions

    private func goTo(_ next: Step) {
        isNameFocused = false
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            step = next
        }
    }

    private func skip() {
        Analytics.log(.collectionPromptSkipped, ["step": step.analyticsName])
        dismiss()
    }

    /// Adds to an existing collection, shows a confirmation, then closes
    private func add(to collection: RecipeCollection) {
        busyId = collection.id
        Task {
            do {
                try await manager.addRecipe(ref, to: collection.id, source: "save_prompt")
                withAnimation { addedTo = collection.name }
                try? await Task.sleep(for: .seconds(1))
                dismiss()
            } catch {
                errorMessage = "Couldn't add the recipe. Please try again."
            }
            busyId = nil
        }
    }

    /// Makes the collection with the recipe in it, then offers to invite someone
    private func createCollection() {
        guard !trimmedName.isEmpty, !isCreating else { return }
        isCreating = true
        Task {
            do {
                let collection = try await manager.createCollection(named: trimmedName)
                try await manager.addRecipe(ref, to: collection.id, source: "save_prompt")
                goTo(.invite(collectionId: collection.id, name: collection.name))
            } catch {
                errorMessage = "Couldn't create the collection. Please try again."
            }
            isCreating = false
        }
    }
}

#Preview("Pick") {
    SaveToCollectionPrompt(ref: .own(UUID()))
}

#Preview("Name") {
    SaveToCollectionPrompt(ref: .own(UUID()), startingAt: .name)
}

#Preview("Invite") {
    SaveToCollectionPrompt(
        ref: .own(UUID()),
        startingAt: .invite(collectionId: UUID(), name: "Date night")
    )
}
