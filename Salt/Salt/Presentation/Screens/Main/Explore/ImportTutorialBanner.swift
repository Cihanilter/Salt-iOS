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

    @AppStorage("importBannerDismissed") private var isDismissed = false
    /// Hidden until we know the user has no imports, so it doesn't flash for existing users
    @State private var hasImported = true
    @State private var showingOptions = false
    /// Picked in the options sheet; acted on once the sheet is gone
    @State private var pendingOption: ImportBannerOption?
    @State private var tutorialSource: ShareTutorialView.Source?
    @State private var tutorialOutcome: ShareTutorialView.Outcome?

    var body: some View {
        Group {
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
                let count = (try? await RecipeService.shared.getImportedRecipesCount()) ?? 1
                hasImported = count > 0
            }
        }
        .sheet(isPresented: $showingOptions, onDismiss: openPendingOption) {
            ImportOptionsSheet { option in
                Analytics.log(.importBannerOptionSelected, ["option": option.rawValue])
                pendingOption = option
                showingOptions = false
            }
            .presentationDetents([.medium])
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

    /// The tutorial can only open once the sheet is fully closed
    private func openPendingOption() {
        guard let option = pendingOption else { return }
        pendingOption = nil
        switch option {
        case .socialMedia: tutorialSource = .social
        case .website: tutorialSource = .website
        case .createManually: openCreateRecipe()
        }
    }
}

extension ShareTutorialView.Source: Identifiable {
    var id: String { rawValue }
}

/// Ways to add a first recipe, in the banner's sheet
enum ImportBannerOption: String, CaseIterable, Identifiable {
    case socialMedia = "social_media"
    case website
    case createManually = "create_manually"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .socialMedia: "From social media"
        case .website: "From a website"
        case .createManually: "Create manually"
        }
    }

    var subtitle: String {
        switch self {
        case .socialMedia: "Instagram, TikTok, Facebook, YouTube Shorts"
        case .website: "Any recipe blog or website"
        case .createManually: "Type in your own recipe"
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
                Text("We'll show you how in a few taps.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("GraniteGray"))
            }
            .padding(.top, 28)

            VStack(spacing: 10) {
                ForEach(ImportBannerOption.allCases) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        optionRow(option)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.ignoresSafeArea())
    }

    private func optionRow(_ option: ImportBannerOption) -> some View {
        HStack(spacing: 14) {
            icon(for: option)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color("PeachCream")))

            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundColor(.black)
                Text(option.subtitle)
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

    @ViewBuilder
    private func icon(for option: ImportBannerOption) -> some View {
        switch option {
        case .socialMedia:
            // Two overlapping logos
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
        case .website:
            Image(systemName: "globe")
                .font(.system(size: 22))
                .foregroundColor(Color("Orange"))
        case .createManually:
            Image(systemName: "square.and.pencil")
                .font(.system(size: 22))
                .foregroundColor(Color("Orange"))
        }
    }
}

#Preview("Card") {
    ImportTutorialBannerCard(onTap: {}, onDismiss: {})
        .padding()
}

#Preview("Options") {
    ImportOptionsSheet { _ in }
}
