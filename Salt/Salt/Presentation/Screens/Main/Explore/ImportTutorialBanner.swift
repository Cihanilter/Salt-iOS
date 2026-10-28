//
//  ImportTutorialBanner.swift
//  Salt
//
//  Card at the top of Explore for users who haven't imported a recipe yet.
//  Opens the interactive import tutorial, then Instagram or the Add Recipe tab.
//

import SwiftUI

struct ImportTutorialBanner: View {
    /// Opens the Add Recipe tab to paste a link
    let switchToAddRecipe: () -> Void

    @AppStorage("importBannerDismissed") private var isDismissed = false
    /// Hidden until we know the user has no imports, so it doesn't flash for existing users
    @State private var hasImported = true
    @State private var showingTutorial = false
    @State private var tutorialOutcome: ShareTutorialView.Outcome?

    var body: some View {
        Group {
            if !isDismissed && !hasImported {
                ImportTutorialBannerCard(
                    onTap: {
                        Analytics.log(.importBannerTapped)
                        showingTutorial = true
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
        .fullScreenCover(isPresented: $showingTutorial, onDismiss: {
            if tutorialOutcome == .pasteLink {
                switchToAddRecipe()
            }
            tutorialOutcome = nil
        }) {
            ShareTutorialView(context: .explore) { outcome in
                tutorialOutcome = outcome
                showingTutorial = false
            }
        }
    }

}

/// The banner's card
struct ImportTutorialBannerCard: View {
    let onTap: () -> Void
    let onDismiss: () -> Void

    private let recipe = TutorialSampleRecipe.current

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Import your first recipe")
                        .font(.custom("Playfair9pt-SemiBold", size: 19))
                        .foregroundColor(.black)
                    Text("Save any recipe from Instagram or TikTok in 3 taps.")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundColor(Color("GraniteGray"))
                        .fixedSize(horizontal: false, vertical: true)
                    Label("Show me how", systemImage: "play.fill")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color("Orange")))
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack(alignment: .bottomTrailing) {
                    TutorialRecipePhoto(url: recipe.imageUrl)
                        .frame(width: 78, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .rotationEffect(.degrees(4))
                    Image("saltAppIcon")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 2))
                        .offset(x: 8, y: 8)
                }
                .padding(.trailing, 8)
                .accessibilityHidden(true)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color("PeachCream")))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color("GraniteGray"))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.8)))
            }
            .padding(8)
            .accessibilityLabel("Dismiss")
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ImportTutorialBannerCard(onTap: {}, onDismiss: {})
        .padding()
}
