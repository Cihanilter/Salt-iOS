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
                Text("You can see its recipes and leave at any time. The owner decides who can add recipes.")
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

/// Everyone in a collection: white page, one orange action (Invite people → share sheet),
/// quiet link rows with Reset link the only red item. The owner taps a member to remove them;
/// members can leave.
struct CollectionMembersView: View {
    let collectionId: UUID

    @ObservedObject private var manager = CollectionsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var members: [CollectionMember] = []
    @State private var isLoading = true
    @State private var selectedMember: CollectionMember?
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(collection?.name ?? "")
                    .font(SaltFont.h2)
                    .foregroundStyle(SaltColor.textPrimary)
                    .padding(.bottom, 24)

                if isLoading && members.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }

                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    memberRow(member)
                    if index < members.count - 1 {
                        Rectangle().fill(SaltColor.borderSubtle).frame(height: 1)
                    }
                }

                Text("\(members.count) of \(RecipeCollection.maxPeople) people")
                    .font(SaltFont.caption)
                    .foregroundStyle(SaltColor.textSecondary)
                    .padding(.top, 12)

                if isOwner {
                    Button(action: { Task { await invite.create(for: collectionId, reset: false) } }) {
                        SaltButtonLabel(title: String(localized: "Invite people"), isLoading: invite.isCreating)
                    }
                    .buttonStyle(.salt())
                    .disabled(collection?.isFull ?? true)
                    .padding(.top, SaltSpacing.section)

                    if collection?.isFull == true {
                        Text("This collection is full. Remove someone to invite another person.")
                            .font(SaltFont.body)
                            .foregroundStyle(SaltColor.textSecondary)
                            .padding(.top, 8)
                    }

                    linkSettings
                        .padding(.top, SaltSpacing.section)
                } else {
                    Button("Leave collection") { showingLeaveAlert = true }
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textDestructive)
                        .frame(minHeight: 44)
                        .padding(.top, SaltSpacing.section)
                }
            }
            .padding(.horizontal, SaltSpacing.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, SaltSpacing.bottomTabPadding)
        }
        .background(SaltColor.surfaceScreen)
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("Members")
                    .font(SaltFont.bodyLargeStrong)
                    .foregroundStyle(SaltColor.textPrimary)
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
                }
            }
            .padding(.horizontal, SaltSpacing.screenMargin)
            .background(SaltColor.surfaceScreen)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadMembers()
        }
        .refreshable {
            await loadMembers()
        }
        .onAppear {
            Analytics.screen("Collection Members")
        }
        .sheet(item: $invite.shareItem) { item in
            ActivityView(items: [item.message, item.url], onComplete: invite.shareFinished)
                .presentationDetents([.medium, .large])
        }
        .collectionToast($invite.sentMessage)
        .confirmationDialog(
            selectedMember?.displayName ?? "",
            isPresented: Binding(get: { selectedMember != nil }, set: { if !$0 { selectedMember = nil } }),
            titleVisibility: .visible,
            presenting: selectedMember
        ) { member in
            // Current role has a ✓
            ForEach(CollectionRole.allCases) { role in
                Button((member.role ?? .editor) == role ? "\(role.title)  \u{2713}" : role.title) {
                    Task { await setRole(role, of: member) }
                }
            }
            Button("Remove from collection", role: .destructive) {
                memberToRemove = member
            }
            Button("Cancel", role: .cancel) { }
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
        .alert("Reset invite link?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                Task { await invite.create(for: collectionId, reset: true) }
            }
        } message: {
            Text("Links you've already sent will stop working. People already in the collection stay.")
        }
        .alert("Turn off invite link?", isPresented: $showingTurnOffAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Turn off", role: .destructive) {
                Task { await turnOffLink() }
            }
        } message: {
            Text("No one new can join with it. Tap Invite people to get a new link later.")
        }
        .alert("Leave \u{201C}\(collection?.name ?? "")\u{201D}?", isPresented: $showingLeaveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                Task { await leave() }
            }
        } message: {
            Text("You won't see its recipes anymore. Recipes you added stay in it.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { (errorMessage ?? invite.errorMessage) != nil },
            set: { if !$0 { errorMessage = nil; invite.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? invite.errorMessage ?? "")
        }
    }

    /// Quiet list rows for the invite link; Reset link is the only red item
    private var linkSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Invite link")
                .font(SaltFont.bodyStrong)
                .foregroundStyle(SaltColor.textSecondary)
                .padding(.bottom, 4)

            Button {
                Task { await copyLink() }
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "link")
                        .font(.system(size: 17))
                        .foregroundStyle(SaltColor.iconDefault)
                    Text("Copy link")
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textPrimary)
                    Spacer()
                }
                .frame(height: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if collection?.supportsInviteExpiry == true {
                Menu {
                    Picker("Link expires", selection: Binding(
                        get: { collection?.inviteExpiryDays },
                        set: { days in Task { await setInviteExpiry(days) } }
                    )) {
                        ForEach(RecipeCollection.inviteExpiryOptions, id: \.self) { days in
                            Text(days == nil ? RecipeCollection.inviteExpiryTitle(nil) : String(localized: "After \(RecipeCollection.inviteExpiryTitle(days))"))
                                .tag(days)
                        }
                    }
                } label: {
                    settingRow("Link expires", value: collection?.inviteExpiryStatus ?? "")
                }
                .accessibilityLabel("Link expires: \(collection?.inviteExpiryStatus ?? "")")
            }

            Menu {
                Picker("New members can", selection: Binding(
                    get: { collection?.newMemberRole ?? .editor },
                    set: { role in Task { await setNewMemberRole(role) } }
                )) {
                    ForEach(CollectionRole.allCases) { role in
                        Text(role.shortTitle).tag(role)
                    }
                }
            } label: {
                HStack(spacing: 16) {
                    Text("New members can")
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textPrimary)
                    Spacer()
                    Text((collection?.newMemberRole ?? .editor).shortTitle)
                        .font(SaltFont.body)
                        .foregroundStyle(SaltColor.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SaltColor.textSecondary)
                }
                .frame(height: 50)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("New members can: \((collection?.newMemberRole ?? .editor).shortTitle)")

            Button("Turn off link") { showingTurnOffAlert = true }
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textPrimary)
                .frame(height: 50)

            Button("Reset link") { showingResetAlert = true }
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textDestructive)
                .frame(height: 50)

            Text("Anyone with the link can join until it expires, or until you reset it or turn it off.")
                .font(SaltFont.caption)
                .foregroundStyle(SaltColor.textSecondary)
                .padding(.top, 4)
        }
    }

    private func memberRow(_ member: CollectionMember) -> some View {
        let canManage = isOwner && !member.isOwner
        return Button {
            if canManage { selectedMember = member }
        } label: {
            HStack(spacing: 16) {
                SaltAvatar(
                    name: member.displayName,
                    imageURL: member.profileImageUrl.flatMap(URL.init(string:)),
                    size: 40
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName + (isCurrentUser(member) ? String(localized: " (you)") : ""))
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textPrimary)
                    Text(member.isOwner ? String(localized: "Owner") : (member.role ?? .editor).title)
                        .font(SaltFont.body)
                        .foregroundStyle(SaltColor.textSecondary)
                }
                Spacer()
                if canManage {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SaltColor.textSecondary)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canManage)
        .accessibilityElement(children: .combine)
    }

    private func isCurrentUser(_ member: CollectionMember) -> Bool {
        member.userId.uuidString.lowercased() == AuthManager.shared.currentUser?.id.lowercased()
    }

    private func loadMembers() async {
        isLoading = true
        do {
            members = try await manager.members(of: collectionId).sorted { $0.isOwner && !$1.isOwner }
        } catch {
            errorMessage = "Couldn't load the members."
        }
        isLoading = false
    }

    private func copyLink() async {
        do {
            let url = try await manager.inviteLink(for: collectionId)
            UIPasteboard.general.url = url
            SaltToastCenter.shared.show(String(localized: "Invite link copied"), duration: .seconds(2.5))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setRole(_ role: CollectionRole, of member: CollectionMember) async {
        guard member.role != role else { return }
        do {
            try await manager.setRole(role, of: member.userId, in: collectionId)
            if let index = members.firstIndex(where: { $0.userId == member.userId }) {
                members[index].role = role
            }
        } catch {
            errorMessage = String(localized: "Couldn't change \(member.displayName)'s role. If this keeps happening, the roles update may not be set up yet.")
        }
    }

    /// "Link expires     In 7 days ›"
    private func settingRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textPrimary)
            Spacer()
            Text(value)
                .font(SaltFont.body)
                .foregroundStyle(SaltColor.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SaltColor.textSecondary)
        }
        .frame(height: 50)
        .contentShape(Rectangle())
    }

    private func setInviteExpiry(_ days: Int?) async {
        do {
            try await manager.setInviteExpiry(days: days, in: collectionId)
        } catch {
            errorMessage = String(localized: "Couldn't change the setting. Please try again.")
        }
    }

    private func setNewMemberRole(_ role: CollectionRole) async {
        do {
            try await manager.setNewMemberRole(role, in: collectionId)
        } catch {
            errorMessage = String(localized: "Couldn't change the setting. Please try again.")
        }
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
    /// "Invite sent" once the share sheet went through, for a toast
    @Published var sentMessage: String?

    /// From the share sheet: confirms the invite went out (or the link was copied)
    func shareFinished(_ activityType: UIActivity.ActivityType?, completed: Bool) {
        guard completed else { return }
        withAnimation {
            sentMessage = activityType == .copyToPasteboard ? "Invite link copied" : "Invite sent"
        }
    }

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
