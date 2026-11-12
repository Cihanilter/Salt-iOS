//
//  ImportTutorialBanner.swift
//  Salt
//
//  Card at the top of Explore for users who haven't imported a recipe yet.
//  Opens a sheet with the ways to add a first recipe: the social media or website
//  import tutorial, or creating one by hand on the Add Recipe tab.
//

import SwiftUI

struct ImportTutorialBanner: View {
    /// Opens the Add Recipe tab to paste a link
    let switchToAddRecipe: () -> Void
    /// Opens the Add Recipe tab on Create
    let openCreateRecipe: () -> Void

    /// Saved on the device, so it's cleared on sign out (see `resetDismissal()`)
    private static let dismissedKey = "importBannerDismissed"

    @AppStorage(dismissedKey) private var isDismissed = false
    /// Hidden until we know the user has no imports, so it doesn't flash for existing users
    @State private var hasImported = true
    @State private var showingOptions = false
    /// Picked in the options sheet; acted on once the sheet is gone
    @State private var pendingOption: ImportBannerOption?
    @State private var tutorialSource: ShareTutorialView.Source?
    @State private var tutorialOutcome: ShareTutorialView.Outcome?

    var body: some View {
        // A VStack rather than a Group: a Group's modifiers go to its contents, and it's
        // empty until the import count loads, so onAppear (and the sheets) would never attach
        VStack(spacing: 0) {
            if !isDismissed && !hasImported {
                ImportTutorialBannerCard(
                    onTap: {
                        Analytics.log(.importBannerTapped)
                        showingOptions = true
                    },
                    onDismiss: {
                        Analytics.log(.importBannerDismissed)
                        isDismissed = true
                    }
                )
                // Inside the condition, so the hidden banner takes no space
                .padding(.top, 8)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isDismissed || hasImported)
        .onAppear {
            // Checked on every appear, so it goes away after an import on the Add Recipe tab.
            // The import log keeps counting after a recipe is deleted, so the banner
            // stays away once the user has imported anything.
            Task {
                guard !isDismissed else { return }
                do {
                    let count = try await RecipeService.shared.getImportedRecipesCount()
                    hasImported = count > 0
                } catch {
                    // Stays hidden: better than showing it to someone who has imported
                    print("ImportTutorialBanner: Failed to count imports: \(error)")
                }
            }
        }
        .sheet(isPresented: $showingOptions, onDismiss: openPendingOption) {
            ImportOptionsSheet { option in
                Analytics.log(.importBannerOptionSelected, ["option": option.rawValue])
                pendingOption = option
                showingOptions = false
            }
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $tutorialSource, onDismiss: {
            if tutorialOutcome == .pasteLink {
                switchToAddRecipe()
            }
            tutorialOutcome = nil
        }) { source in
            ShareTutorialView(context: .explore, sources: [source]) { outcome in
                tutorialOutcome = outcome
                tutorialSource = nil
            }
        }
    }

    /// Shows the banner again for the next account signed in on this device
    static func resetDismissal() {
        UserDefaults.standard.removeObject(forKey: dismissedKey)
    }

    /// The tutorial can only open once the sheet is fully closed
    private func openPendingOption() {
        guard let option = pendingOption else { return }
        pendingOption = nil
        if let source = option.tutorialSource {
            tutorialSource = source
        } else {
            openCreateRecipe()
        }
    }
}

extension ShareTutorialView.Source: Identifiable {
    var id: String { rawValue }
}

/// Ways to add a first recipe, in the banner's sheet
enum ImportBannerOption: String, CaseIterable, Identifiable {
    case instagram
    case tiktok
    case facebook
    case youtubeShorts = "youtube_shorts"
    case website
    case createManually = "create_manually"

    var id: String { rawValue }

    static let socialApps: [ImportBannerOption] = [.instagram, .tiktok, .facebook, .youtubeShorts]

    /// The walkthrough it opens; Create manually has none
    var tutorialSource: ShareTutorialView.Source? {
        switch self {
        case .instagram: .instagram
        case .tiktok: .tiktok
        case .facebook: .facebook
        case .youtubeShorts: .youtubeShorts
        case .website: .website
        case .createManually: nil
        }
    }
}

// MARK: - Card

/// The banner's card: illustration band (Instagram, TikTok, website → Salt icon) and a white
/// bottom with the title and a small "Start". Dismissible.
struct ImportTutorialBannerCard: View {
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ImportLogosArt()
                .frame(height: 118)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [SaltColor.surfaceWarm, SaltColor.surfaceWarmStrong],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import your first recipe")
                        .font(SaltFont.h3)
                        .foregroundStyle(SaltColor.textPrimary)
                    Text("From social media or any website")
                        .font(SaltFont.body)
                        .foregroundStyle(SaltColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Start", action: onTap)
                    .buttonStyle(.salt(.primary, size: .small))
            }
            .padding(16)
            .background(SaltColor.surfaceScreen)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SaltColor.borderSubtle, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SaltColor.iconDefault)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.85), in: Circle())
                    .frame(width: 44, height: 44)
            }
            .padding(2)
            .accessibilityLabel("Dismiss")
        }
        .accessibilityElement(children: .contain)
    }
}

/// Three sources (Instagram, TikTok, a website) with an arrow into the Salt icon
private struct ImportLogosArt: View {
    var body: some View {
        HStack(spacing: 22) {
            HStack(spacing: -12) {
                LogoTile { Image("instagramLogo").resizable().scaledToFit() }
                    .rotationEffect(.degrees(-6))
                LogoTile { Image("tiktokLogo").resizable().scaledToFit() }
                    .offset(y: -3)
                LogoTile {
                    Image(systemName: "globe")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(SaltColor.textSecondary)
                }
                .rotationEffect(.degrees(6))
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(SaltColor.iconAccent)

            Image("saltAppIcon")
                .resizable()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityHidden(true)
    }

    private struct LogoTile<Content: View>: View {
        @ViewBuilder let content: Content

        var body: some View {
            content
                .frame(width: 24, height: 24)
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
    }
}

// MARK: - Options Sheet

private struct ImportOptionsSheet: View {
    let onSelect: (ImportBannerOption) -> Void

    /// Social media opens its own page with one tile per app
    @State var showingApps = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showingApps {
                appsPage
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                mainPage
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.ignoresSafeArea())
    }

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add your first recipe")
                    .font(.custom("Playfair9pt-SemiBold", size: 24))
                Text("Pick where it's from and we'll show you how.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("GraniteGray"))
            }

            VStack(spacing: 10) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showingApps = true }
                } label: {
                    optionRow(title: "From social media", subtitle: "Instagram, TikTok, Facebook, YouTube Shorts") {
                        socialIcon
                    }
                }
                .buttonStyle(.plain)

                Button {
                    onSelect(.website)
                } label: {
                    optionRow(title: "From a website", subtitle: "Any recipe blog or website") {
                        symbolIcon("globe")
                    }
                }
                .buttonStyle(.plain)

                Button {
                    onSelect(.createManually)
                } label: {
                    optionRow(title: "Create manually", subtitle: "Type in your own recipe") {
                        symbolIcon("square.and.pencil")
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var appsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showingApps = false }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Back")

                VStack(alignment: .leading, spacing: 4) {
                    Text("From social media")
                        .font(.custom("Playfair9pt-SemiBold", size: 24))
                    Text("Which app is the recipe on?")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color("GraniteGray"))
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(ImportBannerOption.socialApps) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        appTile(option)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Two overlapping logos
    private var socialIcon: some View {
        ZStack {
            Image("instagramLogo")
                .resizable()
                .frame(width: 20, height: 20)
                .offset(x: -6, y: -5)
            Image("tiktokLogo")
                .resizable()
                .frame(width: 20, height: 20)
                .padding(2)
                .background(Circle().fill(Color("PeachCream")))
                .offset(x: 7, y: 6)
        }
    }

    private func symbolIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 22))
            .foregroundColor(Color("Orange"))
    }

    private func appTile(_ option: ImportBannerOption) -> some View {
        let source = option.tutorialSource
        return HStack(spacing: 10) {
            if let logo = source?.logo {
                Image(logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
            }
            Text(source?.name ?? "")
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
        .background(RoundedRectangle(cornerRadius: 16).stroke(Color("GrayButtonBorderColor"), lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func optionRow<Icon: View>(title: String, subtitle: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 14) {
            icon()
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color("PeachCream")))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundColor(.black)
                Text(subtitle)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundColor(Color("GraniteGray"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color("GraniteGray"))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).stroke(Color("GrayButtonBorderColor"), lineWidth: 1))
        .contentShape(Rectangle())
    }
}

#Preview("Card") {
    ImportTutorialBannerCard(onTap: {}, onDismiss: {})
        .padding()
}

#Preview("Options") {
    ImportOptionsSheet { _ in }
}

#Preview("Social Apps") {
    ImportOptionsSheet(onSelect: { _ in }, showingApps: true)
}
