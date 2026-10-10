//
//  SharedCollectionsViews.swift
//  Salt
//
//  Shared collections: the invite screen opened from a link, the Members screen,
//  and recipes from other people in a shared collection.
//

import SwiftUI
import Combine

// MARK: - Invite (opened from a link)

/// "Cihan invited you to Home" with Join Collection
struct CollectionInviteView: View {
    let code: String
    /// Takes the user to My Recipes, where the collection now shows
    var onOpenMyRecipes: () -> Void

    @ObservedObject private var manager = CollectionsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var invite: CollectionInvite?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var hasJoined = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Spacer()
                content
                Spacer()
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
        } else if let invite {
            MemberAvatar(imageUrl: invite.ownerImageUrl, size: 76)

            Text("\(invite.ownerName ?? "Someone") invited you to")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundColor(Color("GraniteGray"))
                .multilineTextAlignment(.center)

            Text(invite.name)
                .font(.custom("Playfair9pt-SemiBold", size: 30))
                .multilineTextAlignment(.center)

            Text("\(peopleText(invite.peopleCount)) \u{00B7} \(recipesText(invite.recipeCount))")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(Color("GraniteGray"))

            if hasJoined || invite.isMember {
                Text(hasJoined ? "You joined \(invite.name)" : "You're already in this collection")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .padding(.top, 12)
                primaryButton("Open My Recipes") {
                    dismiss()
                    onOpenMyRecipes()
                }
            } else if invite.isFull {
                Text("This collection already has \(RecipeCollection.maxPeople) people.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("OrangeRed"))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            } else {
                primaryButton("Join Collection", isBusy: isJoining) {
                    Task { await join() }
                }
                .padding(.top, 12)
                Text("You can see, add and remove recipes, and leave at any time.")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundColor(Color("GraniteGray"))
                    .multilineTextAlignment(.center)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundColor(Color("OrangeRed"))
                    .multilineTextAlignment(.center)
            }
        } else {
            Image(systemName: "link")
                .font(.system(size: 44))
                .foregroundColor(Color("DarkSilver"))
            Text(errorMessage ?? CollectionShareError.inviteNotFound.errorDescription ?? "")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundColor(Color("GraniteGray"))
                .multilineTextAlignment(.center)
        }
    }

    private func primaryButton(_ title: String, isBusy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color("Orange"))
            .cornerRadius(10)
        }
        .disabled(isBusy)
    }

    private func load() async {
        isLoading = true
        do {
            invite = try await CollectionService.shared.invite(code: code)
            if invite != nil {
                Analytics.log(.collectionInviteOpened)
            }
        } catch {
            errorMessage = "Couldn't open the invite. Check your connection and try again."
        }
        isLoading = false
    }

    private func join() async {
        isJoining = true
        errorMessage = nil
        do {
            try await manager.join(code: code)
            withAnimation { hasJoined = true }
        } catch {
            errorMessage = error.localizedDescription
        }
        isJoining = false
    }
}

// MARK: - Members

/// Everyone in a collection. The owner invites, manages the link and removes people;
/// members can leave.
struct CollectionMembersView: View {
    let collectionId: UUID

    @ObservedObject private var manager = CollectionsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var members: [CollectionMember] = []
    @State private var isLoading = true
    @State private var memberToRemove: CollectionMember?
    @State private var showingResetAlert = false
    @State private var showingTurnOffAlert = false
    @State private var showingLeaveAlert = false
    @StateObject private var invite = CollectionInviteState()
    @State private var errorMessage: String?

    private var collection: RecipeCollection? {
        manager.collection(id: collectionId)
    }

    private var isOwner: Bool {
        collection?.isOwnedByCurrentUser ?? false
    }

    var body: some View {
        List {
            Section {
                if isLoading && members.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
                ForEach(members) { member in
                    memberRow(member)
                        .swipeActions {
                            if isOwner && !member.isOwner {
                                Button("Remove", role: .destructive) {
                                    memberToRemove = member
                                }
                            }
                        }
                }
            } footer: {
                Text("\(members.count) of \(RecipeCollection.maxPeople) people")
            }

            if isOwner {
                Section {
                    Button(action: { Task { await invite.create(for: collectionId, reset: false) } }) {
                        Label("Invite People", systemImage: "person.badge.plus")
                    }
                    .disabled(collection?.isFull ?? true || invite.isCreating)

                    Button(action: { showingResetAlert = true }) {
                        Label("Reset Invite Link", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive, action: { showingTurnOffAlert = true }) {
                        Label("Turn Off Invite Link", systemImage: "link.badge.plus")
                    }
                } footer: {
                    Text(collection?.isFull ?? false
                         ? "This collection is full. Remove someone to invite another person."
                         : "Anyone with the link can join until you reset it or turn it off.")
                }
            } else {
                Section {
                    Button(role: .destructive, action: { showingLeaveAlert = true }) {
                        Label("Leave Collection", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMembers()
        }
        .refreshable {
            await loadMembers()
        }
        .onAppear {
            Analytics.screen("Collection Members")
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
        .alert("Remove \(memberToRemove?.displayName ?? "")?", isPresented: Binding(
            get: { memberToRemove != nil },
            set: { if !$0 { memberToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                if let member = memberToRemove {
                    Task { await remove(member) }
                }
            }
        } message: {
            Text("They won't see this collection anymore. Recipes they added stay in it.")
        }
        .alert("Reset Invite Link?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset") {
                Task { await invite.create(for: collectionId, reset: true) }
            }
        } message: {
            Text("Links you've already sent will stop working. People already in the collection stay.")
        }
        .alert("Turn Off Invite Link?", isPresented: $showingTurnOffAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Turn Off", role: .destructive) {
                Task { await turnOffLink() }
            }
        } message: {
            Text("No one new can join with it. Tap Invite People to get a new link later.")
        }
        .alert("Leave \u{201C}\(collection?.name ?? "")\u{201D}?", isPresented: $showingLeaveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                Task { await leave() }
            }
        } message: {
            Text("You won't see its recipes anymore. Recipes you added stay in it.")
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

    private func memberRow(_ member: CollectionMember) -> some View {
        HStack(spacing: 12) {
            MemberAvatar(imageUrl: member.profileImageUrl, size: 40)
            Text(member.displayName + (isCurrentUser(member) ? " (You)" : ""))
                .font(.custom("OpenSans-Regular", size: 16))
            Spacer()
            if member.isOwner {
                Text("Owner")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundColor(Color("Orange"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color("Orange").opacity(0.12)))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func isCurrentUser(_ member: CollectionMember) -> Bool {
        member.userId.uuidString.lowercased() == AuthManager.shared.currentUser?.id.lowercased()
    }

    private func loadMembers() async {
        isLoading = true
        do {
            members = try await manager.members(of: collectionId)
        } catch {
            errorMessage = "Couldn't load the members."
        }
        isLoading = false
    }

    private func remove(_ member: CollectionMember) async {
        do {
            try await manager.removeMember(member.userId, from: collectionId)
            members.removeAll { $0.userId == member.userId }
        } catch {
            errorMessage = "Couldn't remove \(member.displayName)."
        }
    }

    private func turnOffLink() async {
        do {
            try await manager.disableInviteLink(for: collectionId)
        } catch {
            errorMessage = "Couldn't turn off the link."
        }
    }

    private func leave() async {
        do {
            try await manager.leave(collectionId)
            dismiss()
        } catch {
            errorMessage = "Couldn't leave the collection."
        }
    }
}

// MARK: - Invite Link Sharing

/// Creates the invite link and holds it for the share sheet
@MainActor
final class CollectionInviteState: ObservableObject {
    struct ShareItem: Identifiable {
        let url: URL
        let message: String
        var id: URL { url }
    }

    @Published var isCreating = false
    @Published var shareItem: ShareItem?
    @Published var errorMessage: String?

    func create(for collectionId: UUID, reset: Bool) async {
        guard !isCreating else { return }
        let manager = CollectionsManager.shared
        let name = manager.collection(id: collectionId)?.name ?? "my collection"

        withAnimation { isCreating = true }
        do {
            let url = reset
                ? try await manager.resetInviteLink(for: collectionId)
                : try await manager.inviteLink(for: collectionId)
            shareItem = ShareItem(url: url, message: "Join my \u{201C}\(name)\u{201D} collection on Salt")
        } catch {
            errorMessage = error.localizedDescription
        }
        withAnimation { isCreating = false }
    }
}

/// "Creating link…" capsule while an invite link is made
struct CreatingLinkToast: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.8)
            Text("Creating link\u{2026}")
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.8)))
        .padding(.bottom, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Round profile photo, or a person icon
struct MemberAvatar: View {
    let imageUrl: String?
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color("LightGrayishPink"))
            .frame(width: size, height: size)
            .overlay {
                if let imageUrl, let url = URL(string: imageUrl) {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            personIcon
                        }
                    }
                } else {
                    personIcon
                }
            }
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private var personIcon: some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.45))
            .foregroundColor(Color("GraniteGray"))
    }
}

// MARK: - Someone Else's Recipe

/// A recipe another person added to a shared collection: view it, and Save Recipe keeps
/// a copy in My Recipes (their original can't be changed)
struct CollectionRecipeCopyView: View {
    let recipe: UserRecipe
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RecipeDetailView(
            recipe: recipe.toRecipeDetail(),
            mode: .preview,
            onSave: {
                // The recipe on screen (edits included) is in shared storage
                let savedData = PendingSaveDataStorage.shared.retrieve()
                guard let detail = savedData.recipe else { return false }
                do {
                    _ = try await MyRecipesViewModel.shared.saveSharedRecipe(from: detail, newPhotos: savedData.photos)
                    Analytics.log(.recipeCopiedFromCollection)
                    return true
                } catch {
                    print("❌ Failed to save a copy: \(error)")
                    return false
                }
            },
            onAddMoreRecipes: { dismiss() },
            onGoToMyRecipes: { dismiss() }
        )
    }
}

// MARK: - Text

private func peopleText(_ count: Int) -> String {
    count == 1 ? "1 person" : "\(count) people"
}

private func recipesText(_ count: Int) -> String {
    count == 1 ? "1 recipe" : "\(count) recipes"
}
