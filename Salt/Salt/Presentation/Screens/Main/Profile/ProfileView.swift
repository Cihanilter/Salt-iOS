//
//  ProfileView.swift
//  Salt
//
//  Profile (Figma "Profile — Final"): cream band with Edit profile and the settings gear,
//  left-aligned avatar overlapping it, name (+ Premium badge), bio, two stats, the Free plan
//  card for free users, and the cuisines the user picked. Settings has the rest.
//

import SwiftUI
import PhotosUI
import StoreKit
import RevenueCatUI

/// Where "Help & feedback" writes to
enum SupportConfig {
    static let feedbackEmail = "saltrecipesapp@gmail.com"
}

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var myRecipes = MyRecipesViewModel.shared
    @ObservedObject private var collections = CollectionsManager.shared
    @State private var showingPaywall = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        // Photo and name hidden in session recordings
                        .analyticsMasked()

                    stats
                        .padding(.top, 20)
                        .padding(.horizontal, SaltSpacing.screenMargin)

                    if RevenueCatConfig.isEnabled && !subscriptionManager.isPremium {
                        freePlanCard
                            .padding(.top, SaltSpacing.section)
                            .padding(.horizontal, SaltSpacing.screenMargin)
                    }

                    favoriteCuisines
                        .padding(.top, SaltSpacing.section)
                        .padding(.horizontal, SaltSpacing.screenMargin)
                }
                .padding(.bottom, SaltSpacing.bottomTabPadding)
            }
            .background(SaltColor.surfaceScreen)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingSettings) {
                SettingsView(viewModel: viewModel, showingPaywall: $showingPaywall)
            }
            .task {
                // The tab stays alive between visits, so refresh the counts each time
                await viewModel.loadRecipesCount()
                if !collections.hasLoaded { await collections.load() }
            }
            .sheet(isPresented: $viewModel.isEditing) {
                EditProfileView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingPaywall) {
                // Remote paywall: shows whatever is attached to the current offering in the RevenueCat dashboard
                PaywallView(displayCloseButton: true)
                    .onAppear {
                        Analytics.log(.paywallShown, ["source": "profile"])
                    }
                    .onPurchaseCompleted { customerInfo in
                        Analytics.log(.subscriptionStarted, ["source": "profile"])
                        subscriptionManager.update(with: customerInfo)
                        showingPaywall = false
                    }
                    .onRestoreCompleted { customerInfo in
                        Analytics.log(.purchasesRestored, ["source": "profile"])
                        subscriptionManager.update(with: customerInfo)
                        if subscriptionManager.isPremium {
                            showingPaywall = false
                        }
                    }
            }
        }
    }

    // MARK: - Header

    private static let bandHeight: CGFloat = 150
    private static let avatarSize: CGFloat = 88

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                SaltColor.surfaceWarmSubtle
                    .frame(height: Self.bandHeight)
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 12) {
                            Button("Edit profile") { viewModel.startEditing() }
                                .buttonStyle(.salt(.outline, size: .small))
                            Button { showingSettings = true } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 18))
                                    .foregroundStyle(SaltColor.iconDefault)
                                    .frame(width: 38, height: 38)
                                    .background(SaltColor.surfaceScreen, in: Circle())
                                    .overlay(Circle().stroke(SaltColor.borderSubtle, lineWidth: 1))
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Settings")
                        }
                        .padding(.horizontal, SaltSpacing.screenMargin)
                        .padding(.bottom, 52)
                    }

                avatar
                    .padding(.leading, SaltSpacing.screenMargin)
                    .offset(y: Self.avatarSize / 2)
            }
            .padding(.bottom, Self.avatarSize / 2 + 16)

            HStack(spacing: 10) {
                Text(viewModel.displayName)
                    .font(SaltFont.h1)
                    .foregroundStyle(SaltColor.textPrimary)
                    .lineLimit(2)
                if RevenueCatConfig.isEnabled && subscriptionManager.isPremium {
                    SaltPremiumBadge()
                }
            }
            .padding(.horizontal, SaltSpacing.screenMargin)

            if let bio = viewModel.userProfile?.bio, !bio.isEmpty {
                Text(bio)
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    .padding(.horizontal, SaltSpacing.screenMargin)
            }
        }
    }

    /// Photo, or a pink circle with initials; the camera button opens Edit profile
    private var avatar: some View {
        ProfileAvatar(
            name: viewModel.displayName,
            imageUrl: viewModel.userProfile?.profileImageUrl,
            size: Self.avatarSize,
            isLoading: viewModel.isUploadingImage
        )
        .overlay(Circle().stroke(Color.white, lineWidth: 4))
        .overlay(alignment: .bottomTrailing) {
            Button { viewModel.startEditing() } label: {
                Image(systemName: "camera")
                    .font(.system(size: 13))
                    .foregroundStyle(SaltColor.iconDefault)
                    .frame(width: 30, height: 30)
                    .background(SaltColor.surfaceScreen, in: Circle())
                    .overlay(Circle().stroke(SaltColor.borderSubtle, lineWidth: 1))
                    .frame(width: 44, height: 44)
            }
            .offset(x: 12, y: 6)
            .accessibilityLabel("Change photo")
        }
    }

    // MARK: - Stats

    /// Two stats without a box, in Number/XLarge
    private var stats: some View {
        HStack(spacing: 20) {
            stat(count: myRecipes.totalRecipesCount, label: myRecipes.totalRecipesCount == 1 ? "recipe" : "recipes")
            Rectangle()
                .fill(SaltColor.borderSubtle)
                .frame(width: 1, height: 28)
            stat(count: collections.collections.count, label: collections.collections.count == 1 ? "collection" : "collections")
        }
    }

    private func stat(count: Int, label: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(count)")
                .font(SaltFont.numberXLarge)
                .foregroundStyle(SaltColor.textPrimary)
            Text(label)
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Free Plan

    /// Clean white upgrade card with usage; Upgrade is the only strong orange on the page
    private var freePlanCard: some View {
        let limit = RevenueCatConfig.freeImportLimit
        let used = min(viewModel.importedRecipesCount, limit)
        return HStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 18))
                .foregroundStyle(SaltColor.iconAccent)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(SaltColor.borderSubtle, lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                Text("Free plan")
                    .font(SaltFont.bodyLargeStrong)
                    .foregroundStyle(SaltColor.textPrimary)
                Text("\(used) of \(limit) free imports used")
                    .font(SaltFont.body)
                    .foregroundStyle(SaltColor.textSecondary)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(SaltColor.surfaceControl)
                        Capsule()
                            .fill(SaltColor.actionPrimary)
                            .frame(width: proxy.size.width * CGFloat(used) / CGFloat(max(limit, 1)))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }

            Button("Upgrade") { showingPaywall = true }
                .buttonStyle(.salt(.primary, size: .small))
        }
        .padding(16)
        .background(SaltColor.surfaceScreen, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SaltColor.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Favorite Cuisines

    /// Only the cuisines the user picked (read-only peach tags without ✓); Edit opens the list
    private var favoriteCuisines: some View {
        VStack(alignment: .leading, spacing: SaltSpacing.titleToContent) {
            HStack(alignment: .firstTextBaseline) {
                Text("Favorite cuisines")
                    .font(SaltFont.h2)
                    .foregroundStyle(SaltColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Edit") { viewModel.startEditing() }
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textAccent)
            }

            if let cuisines = viewModel.userProfile?.favoriteCuisines, !cuisines.isEmpty {
                ChipFlow(spacing: 8) {
                    ForEach(cuisines, id: \.self) { cuisine in
                        SaltChip(title: cuisine, isSelected: true, showsCheck: false)
                    }
                }
            } else {
                Text("Pick the cuisines you love to personalize Explore.")
                    .font(SaltFont.body)
                    .foregroundStyle(SaltColor.textSecondary)
            }
        }
    }
}

// MARK: - Profile Avatar

/// Profile photo, or a pink circle with Playfair initials
struct ProfileAvatar: View {
    let name: String
    let imageUrl: String?
    let size: CGFloat
    var isLoading = false

    var body: some View {
        ZStack {
            Circle().fill(SaltColor.surfacePink)
            if let imageUrl, !imageUrl.isEmpty, let url = URL(string: imageUrl) {
                CachedAsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initials
                    }
                }
                .clipShape(Circle())
            } else {
                initials
            }
            if isLoading {
                Circle().fill(Color.white.opacity(0.6))
                ProgressView()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var initials: some View {
        Text(SaltAvatar.initials(from: name))
            .font(SaltFont.playfair(size * 0.3, semibold: true))
            .foregroundStyle(SaltColor.textPrimary)
    }
}

// MARK: - Settings

/// Preferences (units, notifications), Subscription, Support and Account.
/// Delete account stays a quiet red link.
struct SettingsView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Binding var showingPaywall: Bool
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Default for every recipe; the … menu on a recipe changes it too
    @AppStorage("preferredUnitSystem") private var preferredUnits: UnitSystem?
    @State private var showingManageSubscription = false
    @State private var showingSignOutAlert = false
    @State private var showingDeleteAccountAlert = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                group("Preferences") {
                    Menu {
                        Picker("Default units", selection: $preferredUnits) {
                            Text("As written").tag(UnitSystem?.none)
                            Text("Imperial").tag(UnitSystem?.some(.imperial))
                            Text("Metric").tag(UnitSystem?.some(.metric))
                        }
                    } label: {
                        SettingsRow(systemImage: "ruler", title: "Default units", value: unitsLabel)
                    }
                    divider
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    } label: {
                        SettingsRow(systemImage: "bell", title: "Notifications")
                    }
                }

                if RevenueCatConfig.isEnabled {
                    group("Subscription") {
                        Button {
                            if subscriptionManager.hasWebSubscription {
                                manageWebSubscription()
                            } else if subscriptionManager.isPremium {
                                showingManageSubscription = true
                            } else {
                                showingPaywall = true
                            }
                        } label: {
                            SettingsRow(
                                systemImage: "crown",
                                title: "Salt Premium",
                                value: subscriptionManager.isPremium ? String(localized: "Manage") : String(localized: "Upgrade")
                            )
                        }
                    }
                }

                group("Support") {
                    Button {
                        if let url = URL(string: "mailto:\(SupportConfig.feedbackEmail)?subject=Salt%20feedback") { openURL(url) }
                    } label: {
                        SettingsRow(systemImage: "questionmark.circle", title: "Help & feedback")
                    }
                }

                group("Account") {
                    if let email = viewModel.email {
                        HStack(spacing: 16) {
                            Image(systemName: "envelope")
                                .font(.system(size: 17))
                                .foregroundStyle(SaltColor.iconDefault)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Email")
                                    .font(SaltFont.caption)
                                    .foregroundStyle(SaltColor.textSecondary)
                                Text(email)
                                    .font(SaltFont.bodyLarge)
                                    .foregroundStyle(SaltColor.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .analyticsMasked()
                        divider
                    }
                    Button { showingSignOutAlert = true } label: {
                        SettingsRow(systemImage: "rectangle.portrait.and.arrow.right", title: "Sign out", showsChevron: false)
                    }
                }

                VStack(spacing: 16) {
                    if let memberSince = viewModel.memberSince {
                        Text("Member since \(memberSince)")
                            .font(SaltFont.body)
                            .foregroundStyle(SaltColor.textSecondary)
                    }
                    Button("Delete account") { showingDeleteAccountAlert = true }
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textDestructive)
                        .frame(minHeight: 44)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .padding(.horizontal, SaltSpacing.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, SaltSpacing.bottomTabPadding)
        }
        .background(SaltColor.surfaceScreen)
        .safeAreaInset(edge: .top, spacing: 0) {
            SaltBackHeader(title: "Settings") { dismiss() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .manageSubscriptionsSheet(isPresented: $showingManageSubscription)
        .alert("Sign out?", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) {
                viewModel.signOut()
            }
        }
        .alert("Delete your account?", isPresented: $showingDeleteAccountAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete account", role: .destructive) {
                Task { await viewModel.deleteAccount() }
            }
        } message: {
            Text("This can't be undone. Your recipes, collections and profile are deleted for good.")
        }
    }

    private var unitsLabel: String {
        switch preferredUnits {
        case .imperial: String(localized: "Imperial")
        case .metric: String(localized: "Metric")
        case nil: String(localized: "As written")
        }
    }

    /// Web subscriptions are managed on RevenueCat's page, not in Apple's sheet; without
    /// that page (e.g. Premium given as a promo), support can help
    private func manageWebSubscription() {
        if let url = subscriptionManager.webManagementURL {
            openURL(url)
        } else if let url = URL(string: "mailto:\(SupportConfig.feedbackEmail)?subject=Salt%20Premium%20subscription") {
            openURL(url)
        }
    }

    private var divider: some View {
        Rectangle().fill(SaltColor.borderSubtle).frame(height: 1)
    }

    private func group<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SaltFont.bodyStrong)
                .foregroundStyle(SaltColor.textSecondary)
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous)
                    .stroke(SaltColor.borderSubtle, lineWidth: 1)
            )
        }
    }
}

/// Icon, title, optional gray value and a chevron
private struct SettingsRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    var value: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .foregroundStyle(SaltColor.iconDefault)
                .frame(width: 24)
            Text(title)
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textPrimary)
            Spacer()
            if let value {
                Text(value)
                    .font(SaltFont.body)
                    .foregroundStyle(SaltColor.textSecondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SaltColor.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

// MARK: - Edit Profile View

/// Sheet with Cancel / Save: photo, name, bio (120 characters) and favorite cuisines.
/// Save is active only after a change; Cancel with changes asks "Discard changes?".
struct EditProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDiscardAlert = false
    @State private var showingPhotoOptions = false
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var photoItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, bio }

    private var nameIsEmpty: Bool {
        viewModel.editFullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSave: Bool {
        viewModel.hasEditChanges && !nameIsEmpty && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            // Cancel / Edit profile / Save
            ZStack {
                Text("Edit profile")
                    .font(SaltFont.bodyLargeStrong)
                    .foregroundStyle(SaltColor.textPrimary)
                HStack {
                    Button("Cancel", action: cancel)
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textPrimary)
                    Spacer()
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .font(SaltFont.bodyLargeStrong)
                    .foregroundStyle(canSave ? SaltColor.textAccent : SaltColor.textDisabled)
                    .disabled(!canSave)
                }
            }
            .frame(height: 44)
            .padding(.horizontal, SaltSpacing.screenMargin)
            .padding(.top, 20)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 12) {
                        ProfileAvatar(
                            name: viewModel.editFullName.isEmpty ? viewModel.displayName : viewModel.editFullName,
                            imageUrl: viewModel.userProfile?.profileImageUrl,
                            size: 96,
                            isLoading: viewModel.isUploadingImage
                        )
                        Button("Change photo") { showingPhotoOptions = true }
                            .font(SaltFont.bodyLargeStrong)
                            .foregroundStyle(SaltColor.textAccent)
                            .disabled(viewModel.isUploadingImage)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Name")
                        TextField("", text: $viewModel.editFullName, prompt: Text("Your name").foregroundStyle(SaltColor.textSecondary))
                            .focused($focusedField, equals: .name)
                            .textContentType(.name)
                            .frame(height: 28)
                            .saltInput(isFocused: focusedField == .name, hasError: nameIsEmpty)
                        if nameIsEmpty {
                            Text("Add your name.")
                                .font(SaltFont.body)
                                .foregroundStyle(SaltColor.textDestructive)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            fieldLabel("Bio")
                            Text("Optional")
                                .font(SaltFont.body)
                                .foregroundStyle(SaltColor.textSecondary)
                        }
                        TextField("", text: $viewModel.editBio, prompt: Text("A line about you and your cooking").foregroundStyle(SaltColor.textSecondary), axis: .vertical)
                            .lineLimit(3...4)
                            .focused($focusedField, equals: .bio)
                            .saltInput(isFocused: focusedField == .bio)
                        Text("\(viewModel.editBio.count)/\(ProfileViewModel.maxBioLength)")
                            .font(SaltFont.caption)
                            .foregroundStyle(SaltColor.textSecondary)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Favorite cuisines")
                        Text("Pick as many as you like. We use them to personalize Explore.")
                            .font(SaltFont.body)
                            .foregroundStyle(SaltColor.textSecondary)
                        ChipFlow(spacing: 8) {
                            ForEach(viewModel.availableCuisines, id: \.self) { cuisine in
                                let isSelected = viewModel.editFavoriteCuisines.contains(cuisine)
                                SaltChip(title: cuisine, isSelected: isSelected) {
                                    viewModel.toggleCuisine(cuisine)
                                }
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, SaltSpacing.screenMargin)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(SaltColor.surfaceScreen)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(SaltRadius.sheet)
        // With changes, swiping down doesn't throw them away; Cancel asks first
        .interactiveDismissDisabled(viewModel.hasEditChanges)
        .onChange(of: viewModel.editBio) { _, newValue in
            if newValue.count > ProfileViewModel.maxBioLength {
                viewModel.editBio = String(newValue.prefix(ProfileViewModel.maxBioLength))
            }
        }
        .alert("Discard changes?", isPresented: $showingDiscardAlert) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard", role: .destructive) {
                viewModel.cancelEditing()
                dismiss()
            }
        }
        .confirmationDialog("Profile photo", isPresented: $showingPhotoOptions, titleVisibility: .hidden) {
            if CameraView.isAvailable {
                Button("Take photo") { showingCamera = true }
            }
            Button("Choose from library") { showingLibrary = true }
            if viewModel.hasProfileImage {
                Button("Remove photo", role: .destructive) {
                    Task { await viewModel.removeProfileImage() }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showingLibrary, selection: $photoItem, matching: .images)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView(image: $capturedImage)
                .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await viewModel.uploadProfileImage(image)
                }
                photoItem = nil
            }
        }
        .onChange(of: capturedImage) { _, image in
            guard let image else { return }
            capturedImage = nil
            Task { await viewModel.uploadProfileImage(image) }
        }
    }

    /// Small gray Open Sans labels (sheet rule)
    private func fieldLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(SaltFont.bodyStrong)
            .foregroundStyle(SaltColor.textSecondary)
    }

    private func cancel() {
        if viewModel.hasEditChanges {
            showingDiscardAlert = true
        } else {
            viewModel.cancelEditing()
            dismiss()
        }
    }

    private func save() {
        focusedField = nil
        isSaving = true
        Task {
            if await viewModel.saveProfile() {
                dismiss()
            }
            isSaving = false
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        ChipFlow(spacing: spacing).sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        ChipFlow(spacing: spacing).placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }
}

// MARK: - Preview

#Preview {
    ProfileView()
}
