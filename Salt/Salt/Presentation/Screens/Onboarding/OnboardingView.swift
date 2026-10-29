//
//  OnboardingView.swift
//  Salt
//
//  First screens for signed-out users: Welcome (Get started / Log in), then a short
//  questionnaire with the import tutorial, and finally account creation.
//

import SwiftUI
import StoreKit

/// Onboarding values kept on the device until sign-up
enum OnboardingStorage {
    /// Set once the questions have been answered, so Get started goes straight to Create account
    static let completedKey = "hasCompletedOnboarding"
    /// Name from "What should we call you?", pre-filled on the email sign-up form
    static let nameKey = "onboardingName"
    /// The App Store rating prompt is requested only once
    static let reviewRequestedKey = "onboardingReviewRequested"
}

// MARK: - Welcome

struct WelcomeView: View {
    @ObservedObject var router: AuthRouter
    @AppStorage(OnboardingStorage.completedKey) private var hasCompletedOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Ready to get started?")
                .font(.custom("Playfair9pt-SemiBold", size: 30))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 40)

            WelcomePhoneMockup()
                .padding(.vertical, 28)
                .frame(maxHeight: .infinity)

            VStack(spacing: 14) {
                OnboardingPrimaryButton(title: "Get started") {
                    router.navigate(to: hasCompletedOnboarding ? .createAccount : .onboarding)
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
        .frame(maxHeight: 400)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.black, lineWidth: 6))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .accessibilityHidden(true)
    }
}

// MARK: - Questionnaire

private struct OnboardingOption: Identifiable, Hashable {
    let id: String
    let emoji: String
    let title: String
}

private enum OnboardingPage: Int, CaseIterable {
    case intro
    case goals
    case goalsGreat
    case goalsPlan
    case cookingTime
    case name
    case firstAction
    case sources
    case showHow
    case referral
    case settingUp
    case progress

    var analyticsName: String {
        switch self {
        case .intro: "intro"
        case .goals: "goals"
        case .goalsGreat: "goals_great"
        case .goalsPlan: "goals_plan"
        case .cookingTime: "cooking_time"
        case .name: "name"
        case .firstAction: "first_action"
        case .sources: "recipe_sources"
        case .showHow: "show_how"
        case .referral: "referral_code"
        case .settingUp: "setting_up"
        case .progress: "progress"
        }
    }
}

struct OnboardingFlowView: View {
    @ObservedObject var router: AuthRouter
    @AppStorage(OnboardingStorage.completedKey) private var hasCompletedOnboarding = false
    @AppStorage(OnboardingStorage.reviewRequestedKey) private var hasRequestedReview = false

    @State private var page: OnboardingPage
    @State private var goals: Set<String>
    @State private var cookingTime: String?
    @State private var name = ""
    @State private var firstAction: String?
    @State private var sources: Set<String> = []
    @State private var referralCode = ""
    @State private var tutorialOutcome: ShareTutorialView.Outcome?
    @State private var showingTutorial = false
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(router: AuthRouter) {
        self.router = router
        _page = State(initialValue: .intro)
        _goals = State(initialValue: [])
    }

    /// `page` and `goals` are only for previews; onboarding always starts at the intro
    fileprivate init(router: AuthRouter, startingAt page: OnboardingPage, goals: Set<String> = []) {
        self.router = router
        _page = State(initialValue: page)
        _goals = State(initialValue: goals)
    }

    private let goalOptions = [
        OnboardingOption(id: "eat_healthier", emoji: "🥗", title: "Eat healthier"),
        OnboardingOption(id: "save_money", emoji: "💰", title: "Save money"),
        OnboardingOption(id: "cooking_skills", emoji: "🔪", title: "Improve cooking skills"),
        OnboardingOption(id: "organize", emoji: "🗂️", title: "Organize recipes"),
        OnboardingOption(id: "plan_meals", emoji: "🗓️", title: "Plan out meals"),
        OnboardingOption(id: "new_cuisines", emoji: "🌶️", title: "Try new cuisines")
    ]

    private let cookingTimeOptions = [
        OnboardingOption(id: "morning", emoji: "", title: "In the morning, I like to plan ahead"),
        OnboardingOption(id: "lunch", emoji: "", title: "Around lunch time, when I start thinking about it"),
        OnboardingOption(id: "evening", emoji: "", title: "In the evening, when I'm ready to cook")
    ]

    private let sourceOptions = [
        OnboardingOption(id: "social", emoji: "📸 🎵 ▶️ 📌", title: "Social media"),
        OnboardingOption(id: "websites", emoji: "🌐", title: "Recipe websites"),
        OnboardingOption(id: "printed", emoji: "📕 📝", title: "Printed/handwritten recipes")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch page {
                case .intro: introPage
                case .goals:
                    questionPage(title: "What are your goals?", subtitle: "Select all that apply") {
                        ForEach(goalOptions) { option in
                            OnboardingOptionRow(option: option, isSelected: goals.contains(option.id)) {
                                toggle(option.id, in: &goals)
                            }
                        }
                    }
                case .goalsGreat: goalsGreatPage
                case .goalsPlan: goalsPlanPage
                case .cookingTime:
                    questionPage(
                        title: "When do you usually think about what to cook?",
                        subtitle: "We'll check in at the right moment, not a random one."
                    ) {
                        ForEach(cookingTimeOptions) { option in
                            OnboardingOptionRow(option: option, isSelected: cookingTime == option.id) {
                                cookingTime = option.id
                            }
                        }
                    }
                case .name: namePage
                case .firstAction: firstActionPage
                case .sources:
                    questionPage(title: "Where do you get your recipes from?", subtitle: "Select all that apply") {
                        ForEach(sourceOptions) { option in
                            OnboardingOptionRow(option: option, isSelected: sources.contains(option.id), emojiTrailing: true) {
                                toggle(option.id, in: &sources)
                            }
                        }
                    }
                case .showHow: showHowPage
                case .referral: referralPage
                case .settingUp: settingUpPage
                case .progress: progressPage
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
        .sensoryFeedback(.selection, trigger: cookingTime)
        .onAppear {
            Analytics.log(.onboardingStarted)
        }
        .fullScreenCover(isPresented: $showingTutorial, onDismiss: {
            // The questionnaire continues after the tutorial, however it ended
            goForward()
        }) {
            ShareTutorialView(context: .onboarding) { outcome in
                tutorialOutcome = outcome
                showingTutorial = false
            }
        }
    }

    // MARK: Header & Footer

    private var header: some View {
        VStack(spacing: 10) {
            OnboardingLogo()

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
                // Nothing to go back to while it's setting up
                .opacity(page == .settingUp ? 0 : 1)
                .disabled(page == .settingUp)

                // One more step after these pages: Create account
                ProgressView(value: Double(page.rawValue + 1), total: Double(OnboardingPage.allCases.count + 1))
                    .tint(Color("Orange"))
                    .animation(.easeInOut, value: page)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 12) {
            switch page {
            case .firstAction, .settingUp:
                // Tapping a card moves on; Setting up moves on by itself
                EmptyView()
            case .showHow:
                OnboardingPrimaryButton(title: "Show me how") {
                    showingTutorial = true
                }
            case .referral:
                OnboardingPrimaryButton(title: "Continue", isEnabled: !referralCode.trimmed.isEmpty) {
                    goForward()
                }
                Button("Skip") {
                    referralCode = ""
                    goForward()
                }
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundColor(Color("GrayText"))
            default:
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
        case .cookingTime: cookingTime != nil
        case .name: !name.trimmed.isEmpty
        case .sources: !sources.isEmpty
        default: true
        }
    }

    // MARK: Pages

    private func questionPage<Options: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder options: () -> Options
    ) -> some View {
        ScrollView(showsIndicators: false) {
            OnboardingTitle(title: title, subtitle: subtitle)
                .padding(.bottom, 24)

            VStack(spacing: 10) {
                options()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    /// What Salt is for, in place of ReciMe's user count and review
    private var introPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                Text("Your recipes,")
                    .font(.custom("Playfair9pt-SemiBold", size: 26))
                Text("finally in one place")
                    .font(.custom("Playfair9pt-SemiBold", size: 26))
                    .foregroundColor(Color("Orange"))
                Text("Be more organized and save time in the kitchen.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundColor(Color("GraniteGray"))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)

            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(Color("Orange"))
                Text("No more lost screenshots")
                    .font(.custom("Playfair9pt-SemiBold", size: 20))
                Text("Recipes from Instagram, TikTok and Pinterest end up buried in your camera roll. With Salt, you import them straight from the app and keep everything organized in one place.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundColor(Color("GraniteGray"))
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    benefitRow("square.and.arrow.down", "Import from social media and any website")
                    benefitRow("folder", "Sort recipes into collections")
                    benefitRow("arrow.left.arrow.right", "Scale servings and swap ingredients")
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color("GrayButtonBorderColor"), lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 28)
        }
    }

    private func benefitRow(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color("Orange"))
                .frame(width: 22)
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
        }
    }

    private var goalsGreatPage: some View {
        VStack(spacing: 0) {
            OnboardingTitle(
                title: "That's great!",
                subtitle: "Salt helps you \(selectedGoalPhrases.formatted(.list(type: .and))), all from one recipe library."
            )

            OnboardingPhotoBlob()
                .padding(.top, 28)

            Text("We're here to help you\nwith your goals 🤝")
                .font(.custom("OpenSans-SemiBold", size: 17))
                .multilineTextAlignment(.center)
                .padding(.top, 24)
        }
    }

    private var goalsPlanPage: some View {
        VStack(spacing: 0) {
            OnboardingTitle(
                title: "Let's make your goals happen!",
                subtitle: "You want to \(selectedGoalPhrases.formatted(.list(type: .and))) — we'll help you get there."
            )

            GoalsIllustration(emojis: goalOptions.filter { goals.contains($0.id) }.map(\.emoji))
                .padding(.top, 36)
        }
    }

    private var namePage: some View {
        VStack(spacing: 24) {
            OnboardingTitle(title: "What should we call you?", subtitle: "This helps us to personalize your experience.")

            TextField("Your name", text: $name)
                .font(.custom("OpenSans-Regular", size: 16))
                .textContentType(.givenName)
                .submitLabel(.continue)
                .focused($isTextFieldFocused)
                .onSubmit { if canContinue { goForward() } }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 14).stroke(Color("GrayButtonBorderColor"), lineWidth: 1))
                .padding(.horizontal, 20)
        }
        .onAppear { isTextFieldFocused = true }
    }

    private var firstActionPage: some View {
        ScrollView(showsIndicators: false) {
            OnboardingTitle(title: "What do you want to do first?", subtitle: nil)
                .padding(.bottom, 24)

            VStack(spacing: 14) {
                FirstActionCard(highlighted: "Import Recipes", rest: " from Social Media") {
                    ImportCardIllustration()
                } action: {
                    chooseFirstAction("import")
                }
                FirstActionCard(highlighted: "Explore", rest: " new recipes") {
                    ExploreCardIllustration()
                } action: {
                    chooseFirstAction("explore")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    /// "Awesome" page before the tutorial, mentioning where the user gets recipes
    private var showHowPage: some View {
        VStack(spacing: 0) {
            OnboardingTitle(title: "Awesome 🎉", subtitle: showHowMessage)
            ImportSourcesIllustration()
                .padding(.top, 32)
        }
    }

    private var showHowMessage: String {
        switch (sources.contains("social"), sources.contains("websites")) {
        case (true, true): "Salt can import recipes from Instagram, TikTok, YouTube, Pinterest, and websites."
        case (false, true): "Salt can import recipes from websites."
        default: "Salt can import recipes from Instagram, TikTok, YouTube, and Pinterest."
        }
    }

    private var referralPage: some View {
        VStack(spacing: 24) {
            OnboardingTitle(title: "Enter referral code (optional)", subtitle: "You can skip this step")

            TextField("Referral code", text: $referralCode)
                .font(.custom("OpenSans-Regular", size: 16))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($isTextFieldFocused)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 14).stroke(Color("GrayButtonBorderColor"), lineWidth: 1))
                .padding(.horizontal, 20)
        }
    }

    private var settingUpPage: some View {
        VStack(spacing: 32) {
            Text("We're setting everything\nup for you")
                .font(.custom("Playfair9pt-SemiBold", size: 26))
                .multilineTextAlignment(.center)
                .padding(.top, 60)

            SettingUpAnimation()

            Text("Preparing features just for you...")
                .font(.custom("Playfair9pt-Regular", size: 17))
                .foregroundColor(Color("GraniteGray"))
        }
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            goForward()
        }
    }

    private var progressPage: some View {
        VStack(spacing: 0) {
            OnboardingTitle(title: "Become a better cook,\nwith Salt", subtitle: nil)

            ProgressCurveChart()
                .frame(height: 200)
                .padding(.horizontal, 32)
                .padding(.top, 48)

            Text("You're on your way! Watch as your cooking habits evolve and your kitchen experience gets easier.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundColor(Color("GraniteGray"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 48)
        }
        .task {
            // App Store rating prompt, once. iOS decides whether it actually appears.
            guard !hasRequestedReview else { return }
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            hasRequestedReview = true
            requestReview()
        }
    }

    // MARK: Navigation

    private var selectedGoalPhrases: [String] {
        let phrases: [String: String] = [
            "eat_healthier": "eat healthier",
            "save_money": "save money",
            "cooking_skills": "improve your cooking skills",
            "organize": "organize your recipes",
            "plan_meals": "plan out your meals",
            "new_cuisines": "try new cuisines"
        ]
        let picked = goalOptions.compactMap { goals.contains($0.id) ? phrases[$0.id] : nil }
        return picked.isEmpty ? ["organize your recipes"] : picked
    }

    /// Pages shown for the answers so far: choosing Explore skips the import pages
    private func isShown(_ page: OnboardingPage) -> Bool {
        switch page {
        case .sources, .showHow: firstAction != "explore"
        default: true
        }
    }

    private func toggle(_ id: String, in set: inout Set<String>) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }

    private func chooseFirstAction(_ action: String) {
        firstAction = action
        goForward()
    }

    private func goForward() {
        logAnswer(for: page)
        isTextFieldFocused = false
        var next = OnboardingPage(rawValue: page.rawValue + 1)
        while let candidate = next, !isShown(candidate) {
            next = OnboardingPage(rawValue: candidate.rawValue + 1)
        }
        guard let next else {
            finish()
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            page = next
        }
    }

    private func goBack() {
        isTextFieldFocused = false
        var previous = OnboardingPage(rawValue: page.rawValue - 1)
        // Setting up only runs forwards
        while let candidate = previous, !isShown(candidate) || candidate == .settingUp {
            previous = OnboardingPage(rawValue: candidate.rawValue - 1)
        }
        guard let previous else {
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
        case .cookingTime: answers = cookingTime.map { [$0] } ?? []
        case .firstAction: answers = firstAction.map { [$0] } ?? []
        case .sources: answers = sources.sorted()
        case .referral: answers = referralCode.trimmed.isEmpty ? [] : [referralCode.trimmed]
        default: return
        }
        Analytics.log(.onboardingQuestionAnswered, ["question": page.analyticsName, "answers": answers])
    }

    /// Saves the answers on the user's analytics profile and moves on to Create account.
    /// The name stays on the device (not sent to analytics); it pre-fills the email sign-up form.
    private func finish() {
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
                "onboarding_cooking_time": cookingTime ?? "",
                "onboarding_first_action": firstAction ?? "",
                "onboarding_recipe_sources": sources.sorted(),
                "referral_code": referralCode.trimmed
            ]
        )
        UserDefaults.standard.set(name.trimmed, forKey: OnboardingStorage.nameKey)
        hasCompletedOnboarding = true
        router.replace(with: .createAccount)
    }
}

// MARK: - Create Account

/// Last onboarding step: Apple, Google, or the email form under Other options
struct OnboardingAccountView: View {
    @ObservedObject var router: AuthRouter
    @StateObject private var viewModel = SignUpViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                OnboardingLogo()
                HStack(spacing: 14) {
                    Button {
                        router.navigateToRoot()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Back")
                    ProgressView(value: 1)
                        .tint(Color("Orange"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            VStack(spacing: 8) {
                Text("Create an account")
                    .font(.custom("Playfair9pt-SemiBold", size: 26))
                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .foregroundColor(Color("GrayText"))
                    Button("Log in") { router.replace(with: .login) }
                        .foregroundColor(Color("Orange"))
                }
                .font(.custom("OpenSans-Regular", size: 15))
            }
            .padding(.top, 28)

            VStack(spacing: 12) {
                accountButton("Continue with Apple", icon: Image("apple")) {
                    Task { await viewModel.signUpWithApple() }
                }
                accountButton("Continue with Google", icon: Image("google")) {
                    Task { await viewModel.signUpWithGoogle() }
                }
                accountButton("Other options", icon: nil) {
                    router.navigate(to: .signUp)
                }
            }
            .disabled(viewModel.isLoading)
            .padding(.horizontal, 20)
            .padding(.top, 28)

            Spacer()

            Label("Your information is secure. We don't sell your personal information.", systemImage: "lock.fill")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundColor(Color("GrayText"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
        }
        .background(Color.white.ignoresSafeArea())
        .overlay {
            if viewModel.isLoading {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
        }
        .alert("Sign Up", isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private func accountButton(_ title: String, icon: Image?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                }
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 16))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16).stroke(Color("GrayButtonBorderColor"), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Building Blocks

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private struct OnboardingLogo: View {
    var body: some View {
        HStack(spacing: 8) {
            Image("saltAppIcon")
                .resizable()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("Salt")
                .font(.custom("Playfair9pt-SemiBold", size: 22))
                .foregroundColor(Color("Orange"))
        }
        .accessibilityHidden(true)
    }
}

private struct OnboardingTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.custom("Playfair9pt-SemiBold", size: 26))
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundColor(Color("GraniteGray"))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }
}

private struct OnboardingOptionRow: View {
    let option: OnboardingOption
    let isSelected: Bool
    /// Source rows show their app icons after the title
    var emojiTrailing = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if !emojiTrailing && !option.emoji.isEmpty {
                    Text(option.emoji)
                        .font(.system(size: 20))
                }
                Text(option.title)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.leading)
                if emojiTrailing {
                    Text(option.emoji)
                        .font(.system(size: 16))
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color("Orange"))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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

/// Recipe photo in a soft rounded shape, for "That's great!"
private struct OnboardingPhotoBlob: View {
    private let recipe = TutorialSampleRecipe.current

    var body: some View {
        TutorialRecipePhoto(url: recipe.imageUrl)
            .frame(width: 250, height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 110, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 120, style: .continuous)
                    .fill(Color("PeachCream"))
                    .frame(width: 280, height: 270)
                    .rotationEffect(.degrees(-8))
            )
            .accessibilityHidden(true)
    }
}

/// The chosen goals' emojis spilling out of a bowl
private struct GoalsIllustration: View {
    let emojis: [String]

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(Array(emojis.prefix(6).enumerated()), id: \.offset) { index, emoji in
                Text(emoji)
                    .font(.system(size: 54))
                    .rotationEffect(.degrees(Double(index % 3 - 1) * 12))
                    .offset(x: CGFloat(index % 3 - 1) * 70, y: index < 3 ? -150 : -90)
            }
            Text("🥣")
                .font(.system(size: 150))
        }
        .frame(height: 280)
        .accessibilityHidden(true)
    }
}

private struct FirstActionCard<Illustration: View>: View {
    let highlighted: String
    let rest: String
    @ViewBuilder let illustration: () -> Illustration
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                illustration()
                    .frame(height: 120)
                HStack(spacing: 4) {
                    (Text(highlighted).foregroundColor(Color("Orange")) + Text(rest).foregroundColor(.black))
                        .font(.custom("OpenSans-SemiBold", size: 16))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color("GrayButtonBorderColor"), lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct ImportCardIllustration: View {
    private let recipe = TutorialSampleRecipe.current

    var body: some View {
        ZStack {
            TutorialRecipePhoto(url: recipe.imageUrl)
                .frame(width: 90, height: 115)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color("Orange")))
                .offset(x: 52, y: 38)
        }
        .accessibilityHidden(true)
    }
}

private struct ExploreCardIllustration: View {
    private let photos: [URL?] = Array(
        CuratedRecipesManager.shared.recipes
            .dropFirst(6)
            .compactMap { $0.imageUrl.flatMap(URL.init(string:)) }
            .prefix(3)
    )

    var body: some View {
        HStack(spacing: -18) {
            ForEach(0..<3, id: \.self) { index in
                TutorialRecipePhoto(url: index < photos.count ? photos[index] : nil)
                    .frame(width: 80, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white, lineWidth: 3))
                    .rotationEffect(.degrees(Double(index - 1) * 8))
                    .offset(y: index == 1 ? -6 : 4)
                    .zIndex(index == 1 ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
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
            sourceChip("Pinterest", systemImage: "pin.fill", color: Color(red: 0.8, green: 0.1, blue: 0.15))
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

/// Salt icon with ingredients circling it
private struct SettingUpAnimation: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(Array(["🥑", "🍋", "🌶️", "🥕"].enumerated()), id: \.offset) { index, emoji in
                Text(emoji)
                    .font(.system(size: 38))
                    .offset(y: -90)
                    .rotationEffect(.degrees(Double(index) * 90 + (isAnimating ? 360 : 0)))
            }
            Image("saltAppIcon")
                .resizable()
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .frame(height: 230)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// "Scattered recipes" now, rising to "Organized recipes" at your goal
private struct ProgressCurveChart: View {
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height - 24
            let start = CGPoint(x: width * 0.12, y: height * 0.75)
            let end = CGPoint(x: width * 0.88, y: height * 0.12)

            ZStack(alignment: .topLeading) {
                // Grid lines
                ForEach(0..<4, id: \.self) { line in
                    Path { path in
                        let y = height * CGFloat(line) / 3
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(Color("GrayButtonBorderColor"), lineWidth: 1)
                }

                // Flat at first, then steep
                Path { path in
                    path.move(to: start)
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: width * 0.55, y: height * 0.78),
                        control2: CGPoint(x: width * 0.85, y: height * 0.6)
                    )
                }
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [Color("GraniteGray"), Color("Orange")], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )

                marker(at: start, label: "Scattered recipes", color: Color("GraniteGray"))
                marker(at: end, label: "Organized recipes", color: Color("Orange"))
                    .opacity(progress >= 1 ? 1 : 0)

                Text("Now")
                    .position(x: start.x, y: height + 14)
                Text("Your goal")
                    .position(x: end.x, y: height + 14)
            }
            .font(.custom("OpenSans-Regular", size: 12))
            .foregroundColor(Color("GraniteGray"))
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.2).delay(0.2)) {
                progress = 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your recipes go from scattered now to organized at your goal")
    }

    private func marker(at point: CGPoint, label: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .position(point)
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 11))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(color))
                .fixedSize()
                .position(x: point.x, y: point.y - 22)
        }
    }
}

// MARK: - Preview

#Preview("Welcome") {
    WelcomeView(router: AuthRouter())
}

#Preview("Intro") {
    OnboardingFlowView(router: AuthRouter())
}

#Preview("Goals") {
    OnboardingFlowView(router: AuthRouter(), startingAt: .goals, goals: ["eat_healthier", "organize"])
}

#Preview("That's Great") {
    OnboardingFlowView(router: AuthRouter(), startingAt: .goalsGreat, goals: ["eat_healthier", "organize"])
}

#Preview("Goals Plan") {
    OnboardingFlowView(router: AuthRouter(), startingAt: .goalsPlan, goals: ["eat_healthier", "organize"])
}

#Preview("First Action") {
    OnboardingFlowView(router: AuthRouter(), startingAt: .firstAction)
}

#Preview("Sources") {
    OnboardingFlowView(router: AuthRouter(), startingAt: .sources)
}

#Preview("Setting Up") {
    OnboardingFlowView(router: AuthRouter(), startingAt: .settingUp)
}

#Preview("Progress") {
    OnboardingFlowView(router: AuthRouter(), startingAt: .progress)
}

#Preview("Create Account") {
    OnboardingAccountView(router: AuthRouter())
}
