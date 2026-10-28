//
//  OnboardingView.swift
//  Salt
//
//  First screens for signed-out users: Welcome (Get started / Log in), a few short
//  questions, then the import tutorial before creating an account.
//

import SwiftUI

// MARK: - Welcome

struct WelcomeView: View {
    @ObservedObject var router: AuthRouter
    /// Set once the questions and tutorial have been seen, so Get started goes straight to sign up
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Every recipe you love,\nin one place")
                    .font(.custom("Playfair9pt-SemiBold", size: 30))
                    .multilineTextAlignment(.center)
                Text("Save recipes from Instagram, TikTok, YouTube and any website.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundColor(Color("GraniteGray"))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)

            WelcomePhoneMockup()
                .padding(.vertical, 24)
                .frame(maxHeight: .infinity)

            VStack(spacing: 14) {
                OnboardingPrimaryButton(title: "Get started") {
                    if hasCompletedOnboarding {
                        router.navigate(to: .signUp)
                    } else {
                        router.navigate(to: .onboarding)
                    }
                }

                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .foregroundColor(Color("GrayText"))
                    Button("Log in") { router.navigate(to: .login) }
                        .foregroundColor(Color("Orange"))
                }
                .font(.custom("OpenSans-Regular", size: 15))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Color.white.ignoresSafeArea())
    }
}

/// Phone showing a grid of recipe photos, like a filled-in Salt library
private struct WelcomePhoneMockup: View {
    private let photos: [URL?] = Array(
        CuratedRecipesManager.shared.recipes
            .compactMap { $0.imageUrl.flatMap(URL.init(string:)) }
            .prefix(6)
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("My Recipes")
                    .font(.custom("Playfair9pt-SemiBold", size: 16))
                Spacer()
                Image("saltAppIcon")
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    TutorialRecipePhoto(url: index < photos.count ? photos[index] : nil)
                        .frame(height: 78)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .padding(.top, 10)
        .frame(width: 210)
        .frame(maxHeight: 380)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.black, lineWidth: 6))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .accessibilityHidden(true)
    }
}

// MARK: - Questions

private struct OnboardingOption: Identifiable, Hashable {
    let id: String
    let emoji: String
    let title: String
}

private enum OnboardingPage: Int, CaseIterable {
    case goals
    case sources
    case referral
    case showHow

    var analyticsName: String {
        switch self {
        case .goals: "goals"
        case .sources: "recipe_sources"
        case .referral: "referral_source"
        case .showHow: "show_how"
        }
    }
}

struct OnboardingFlowView: View {
    @ObservedObject var router: AuthRouter
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var page: OnboardingPage = .goals
    @State private var goals: Set<String> = []
    @State private var sources: Set<String> = []
    @State private var referral: String?
    @State private var showingTutorial = false
    /// How the tutorial ended; sign up opens once it has fully closed
    @State private var tutorialOutcome: ShareTutorialView.Outcome?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let goalOptions = [
        OnboardingOption(id: "save_social", emoji: "📱", title: "Save recipes from social media"),
        OnboardingOption(id: "organize", emoji: "📚", title: "Keep all my recipes in one place"),
        OnboardingOption(id: "eat_healthier", emoji: "🥗", title: "Eat healthier"),
        OnboardingOption(id: "cooking_skills", emoji: "👩‍🍳", title: "Improve my cooking"),
        OnboardingOption(id: "new_cuisines", emoji: "🌍", title: "Try new cuisines"),
        OnboardingOption(id: "save_money", emoji: "💰", title: "Save money")
    ]

    private let sourceOptions = [
        OnboardingOption(id: "instagram", emoji: "📸", title: "Instagram"),
        OnboardingOption(id: "tiktok", emoji: "🎵", title: "TikTok"),
        OnboardingOption(id: "youtube", emoji: "▶️", title: "YouTube"),
        OnboardingOption(id: "pinterest", emoji: "📌", title: "Pinterest"),
        OnboardingOption(id: "websites", emoji: "🌐", title: "Recipe websites"),
        OnboardingOption(id: "cookbooks", emoji: "📖", title: "Cookbooks & family recipes")
    ]

    private let referralOptions = [
        OnboardingOption(id: "instagram", emoji: "📸", title: "Instagram"),
        OnboardingOption(id: "tiktok", emoji: "🎵", title: "TikTok"),
        OnboardingOption(id: "app_store", emoji: "🔎", title: "App Store search"),
        OnboardingOption(id: "google", emoji: "🌐", title: "Google search"),
        OnboardingOption(id: "friend", emoji: "💬", title: "A friend or family member"),
        OnboardingOption(id: "other", emoji: "✨", title: "Something else")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch page {
                case .goals:
                    questionPage(
                        title: "What brings you to Salt?",
                        subtitle: "Select all that apply",
                        options: goalOptions,
                        isSelected: { goals.contains($0.id) },
                        onSelect: { toggle($0.id, in: &goals) }
                    )
                case .sources:
                    questionPage(
                        title: "Where do you find recipes?",
                        subtitle: "Select all that apply",
                        options: sourceOptions,
                        isSelected: { sources.contains($0.id) },
                        onSelect: { toggle($0.id, in: &sources) }
                    )
                case .referral:
                    questionPage(
                        title: "How did you hear about Salt?",
                        subtitle: nil,
                        options: referralOptions,
                        isSelected: { referral == $0.id },
                        onSelect: { referral = $0.id }
                    )
                case .showHow:
                    showHowPage
                }
            }
            .id(page)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity
            ))
            .frame(maxHeight: .infinity, alignment: .top)

            footer
        }
        .background(Color.white.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: goals)
        .sensoryFeedback(.selection, trigger: sources)
        .sensoryFeedback(.selection, trigger: referral)
        .onAppear {
            Analytics.log(.onboardingStarted)
        }
        .fullScreenCover(isPresented: $showingTutorial, onDismiss: {
            complete(tutorialOutcome: tutorialOutcome ?? .skipped)
        }) {
            ShareTutorialView(context: .onboarding) { outcome in
                tutorialOutcome = outcome
                showingTutorial = false
            }
        }
    }

    // MARK: Header & Footer

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Back")

            ProgressView(value: Double(page.rawValue + 1), total: Double(OnboardingPage.allCases.count))
                .tint(Color("Orange"))
                .animation(.easeInOut, value: page)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if page == .showHow {
                OnboardingPrimaryButton(title: "Show me how") {
                    showingTutorial = true
                }
                Button("Maybe later") {
                    complete(tutorialOutcome: nil)
                }
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundColor(Color("GrayText"))
            } else {
                OnboardingPrimaryButton(title: "Continue", isEnabled: canContinue) {
                    goForward()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var canContinue: Bool {
        switch page {
        case .goals: !goals.isEmpty
        case .sources: !sources.isEmpty
        case .referral: referral != nil
        case .showHow: true
        }
    }

    // MARK: Pages

    private func questionPage(
        title: String,
        subtitle: String?,
        options: [OnboardingOption],
        isSelected: @escaping (OnboardingOption) -> Bool,
        onSelect: @escaping (OnboardingOption) -> Void
    ) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.custom("Playfair9pt-SemiBold", size: 26))
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundColor(Color("GraniteGray"))
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 20)
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                ForEach(options) { option in
                    OnboardingOptionRow(option: option, isSelected: isSelected(option)) {
                        onSelect(option)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    /// "Awesome" page before the tutorial, mentioning the apps the user picked
    private var showHowPage: some View {
        VStack(spacing: 8) {
            Text("Awesome 🎉")
                .font(.custom("Playfair9pt-SemiBold", size: 28))
            Text(showHowMessage)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundColor(Color("GraniteGray"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            ImportSourcesIllustration()
                .padding(.top, 28)
        }
        .padding(.top, 28)
    }

    private var showHowMessage: String {
        let appNames = ["instagram": "Instagram", "tiktok": "TikTok", "youtube": "YouTube", "pinterest": "Pinterest"]
        let picked = sourceOptions.compactMap { sources.contains($0.id) ? appNames[$0.id] : nil }
        guard !picked.isEmpty else {
            return "Salt imports recipes from Instagram, TikTok, YouTube and any website. Let us show you how it works."
        }
        return "Salt imports recipes straight from \(picked.formatted(.list(type: .and))). It takes 3 taps. Let us show you how."
    }

    // MARK: Navigation

    private func toggle(_ id: String, in set: inout Set<String>) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }

    private func goForward() {
        logAnswer(for: page)
        guard let next = OnboardingPage(rawValue: page.rawValue + 1) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            page = next
        }
    }

    private func goBack() {
        guard let previous = OnboardingPage(rawValue: page.rawValue - 1) else {
            router.navigateBack()
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            page = previous
        }
    }

    private func logAnswer(for page: OnboardingPage) {
        let answers: [String]
        switch page {
        case .goals: answers = goals.sorted()
        case .sources: answers = sources.sorted()
        case .referral: answers = referral.map { [$0] } ?? []
        case .showHow: return
        }
        Analytics.log(.onboardingQuestionAnswered, ["question": page.analyticsName, "answers": answers])
    }

    /// Saves the answers on the user's analytics profile and moves on to sign up
    private func complete(tutorialOutcome: ShareTutorialView.Outcome?) {
        let tutorial: String
        switch tutorialOutcome {
        case .completed, .pasteLink: tutorial = "completed"
        case .skipped: tutorial = "skipped"
        case nil: tutorial = "not_started"
        }
        Analytics.log(
            .onboardingCompleted,
            ["tutorial": tutorial],
            userProperties: [
                "onboarding_goals": goals.sorted(),
                "onboarding_recipe_sources": sources.sorted(),
                "referral_source": referral ?? ""
            ]
        )
        hasCompletedOnboarding = true
        router.replace(with: .signUp)
    }
}

// MARK: - Building Blocks

private struct OnboardingOptionRow: View {
    let option: OnboardingOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(option.emoji)
                    .font(.system(size: 20))
                Text(option.title)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundColor(.black)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color("Orange"))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color("PeachCream") : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color("Orange") : Color("GrayButtonBorderColor"), lineWidth: isSelected ? 2 : 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct OnboardingPrimaryButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color("Orange").opacity(isEnabled ? 1 : 0.4))
                )
        }
        .disabled(!isEnabled)
    }
}

/// Recipe photo surrounded by the apps Salt imports from
private struct ImportSourcesIllustration: View {
    private let recipe = TutorialSampleRecipe.current

    var body: some View {
        ZStack {
            TutorialRecipePhoto(url: recipe.imageUrl)
                .frame(width: 170, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)

            sourceChip("Instagram", systemImage: "camera", color: Color(red: 0.84, green: 0.16, blue: 0.46))
                .offset(x: -110, y: -70)
            sourceChip("TikTok", systemImage: "music.note", color: .black)
                .offset(x: 115, y: -30)
            sourceChip("YouTube", systemImage: "play.fill", color: .red)
                .offset(x: -105, y: 60)
            sourceChip("Websites", systemImage: "globe", color: Color("Orange"))
                .offset(x: 105, y: 95)
        }
        .frame(height: 260)
        .accessibilityHidden(true)
    }

    private func sourceChip(_ title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.custom("OpenSans-SemiBold", size: 13))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(color))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

// MARK: - Preview

#Preview("Welcome") {
    WelcomeView(router: AuthRouter())
}

#Preview("Questions") {
    OnboardingFlowView(router: AuthRouter())
}
