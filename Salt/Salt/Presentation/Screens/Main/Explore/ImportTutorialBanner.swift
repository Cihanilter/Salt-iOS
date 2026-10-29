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
            .presentationDetents([.height(460)])
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

/// The banner's card: app logos around the Salt icon, and a call to action
struct ImportTutorialBannerCard: View {
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ImportLogosArt()
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [Color("PeachCream"), Color("Orange").opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Import your first recipe")
                            .font(.custom("Playfair9pt-SemiBold", size: 18))
                            .foregroundColor(.black)
                        Text("From social media, websites, or your own")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundColor(Color("GraniteGray"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        Text("Start")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color("Orange")))
                }
                .padding(14)
                .background(Color.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color("GrayButtonBorderColor"), lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color("GraniteGray"))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.85)))
            }
            .padding(8)
            .accessibilityLabel("Dismiss")
        }
        .accessibilityElement(children: .contain)
    }
}

/// Fanned-out app logos with an arrow into the Salt icon
private struct ImportLogosArt: View {
    private let logos = ["instagramLogo", "tiktokLogo", "facebookLogo", "youtubeShortsLogo"]

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: -10) {
                ForEach(Array(logos.enumerated()), id: \.offset) { index, logo in
                    LogoTile {
                        Image(logo)
                            .resizable()
                            .scaledToFit()
                    }
                    .rotationEffect(.degrees(Double(index - 1) * 8 - 4))
                    .offset(y: index.isMultiple(of: 2) ? 4 : -4)
                }
                LogoTile {
                    Image(systemName: "globe")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color("GraniteGray"))
                }
                .rotationEffect(.degrees(14))
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color("Orange"))

            Image("saltAppIcon")
                .resizable()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .accessibilityHidden(true)
    }

    private struct LogoTile<Content: View>: View {
        @ViewBuilder let content: Content

        var body: some View {
            content
                .frame(width: 24, height: 24)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
    }
}

// MARK: - Options Sheet

private struct ImportOptionsSheet: View {
    let onSelect: (ImportBannerOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add your first recipe")
                    .font(.custom("Playfair9pt-SemiBold", size: 24))
                Text("Pick where it's from and we'll show you how.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("GraniteGray"))
            }
            .padding(.top, 28)

            // One tile per social app
            HStack(spacing: 10) {
                ForEach(ImportBannerOption.socialApps) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        appTile(option)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 10) {
                Button {
                    onSelect(.website)
                } label: {
                    optionRow(title: "From a website", subtitle: "Any recipe blog or website", systemImage: "globe")
                }
                .buttonStyle(.plain)

                Button {
                    onSelect(.createManually)
                } label: {
                    optionRow(title: "Create manually", subtitle: "Type in your own recipe", systemImage: "square.and.pencil")
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.ignoresSafeArea())
    }

    private func appTile(_ option: ImportBannerOption) -> some View {
        let source = option.tutorialSource
        return VStack(spacing: 8) {
            if let logo = source?.logo {
                Image(logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
            }
            Text(source?.name ?? "")
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundColor(.black)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background(RoundedRectangle(cornerRadius: 16).stroke(Color("GrayButtonBorderColor"), lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func optionRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .foregroundColor(Color("Orange"))
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color("PeachCream")))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundColor(.black)
                Text(subtitle)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundColor(Color("GraniteGray"))
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
