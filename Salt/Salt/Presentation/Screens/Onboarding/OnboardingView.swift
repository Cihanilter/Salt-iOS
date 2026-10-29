//
//  OnboardingView.swift
//  Salt
//
//  First screens for signed-out users: Welcome (Get started / Log in), then a short
//  questionnaire with the import tutorial, and finally account creation. The paywall
//  comes after sign-up (see LaunchPaywall).
//

import SwiftUI

/// Onboarding values kept on the device until sign-up
enum OnboardingStorage {
    /// Name from "What should we call you?", pre-filled on the email sign-up form
    static let nameKey = "onboardingName"
}

// MARK: - Review

/// User reviews on the first onboarding screen.
/// Use real reviews (an App Store rating, or a user who agreed to be quoted), never made-up ones.
struct OnboardingReview: Identifiable {
    let quote: String
    let name: String
    /// Image in the asset catalog; initials are shown without one
    let avatarImage: String?

    var id: String { name }

    static let featured = [
        OnboardingReview(
            quote: "I used to have recipes scattered across my social media, screenshots and notes. Salt has been a lifesaver for getting everything into one place.",
            name: "steph291",
            avatarImage: nil
        ),
        OnboardingReview(
            quote: "Love how easy cooking has become with this app. All of my recipes on Instagram and TikTok are now in Salt.",
            name: "john88j",
            avatarImage: nil
        )
    ]

    /// "JD" for "Jane Doe", "S" for a username like "steph291"
    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @ObservedObject var router: AuthRouter

    var body: some View {
        VStack(spacing: 0) {
            Text("All your recipes\nin one place")
                .font(.custom("Playfair9pt-SemiBold", size: 30))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 40)

            WelcomePhoneMockup()
                .padding(.vertical, 24)
                .frame(maxHeight: .infinity)

            VStack(spacing: 14) {
                OnboardingPrimaryButton(title: "Get started") {
                    router.navigate(to: .onboarding)
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

/// Phone showing a My Recipes screenshot (`welcomeScreenshot`), or recipe photos until it's added
private struct WelcomePhoneMockup: View {
    private let photos: [URL?] = Array(
        CuratedRecipesManager.shared.recipes
            .compactMap { $0.imageUrl.flatMap(URL.init(string:)) }
            .prefix(6)
    )

    var body: some View {
        Group {
            if let screenshot = UIImage(named: "welcomeScreenshot") {
                Image(uiImage: screenshot)
                    .resizable()
                    .scaledToFill()
            } else {
                photoGrid
            }
        }
        .aspectRatio(9.0 / 19.5, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color.black))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .accessibilityHidden(true)
    }

    private var photoGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My Recipes")
                .font(.custom("Playfair9pt-SemiBold", size: 16))
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
        .padding(.top, 24)
        .background(Color.white)
    }
}

// MARK: - Questionnaire

private enum OnboardingPage: Int, CaseIterable {
    case intro
    case name
    case sources
    case showHow
    case settingUp

    var analyticsName: String {
        switch self {
        case .intro: "intro"
        case .name: "name"
        case .sources: "recipe_sources"
        case .showHow: "show_how"
        case .settingUp: "setting_up"
        }
    }
}

/// Where the user keeps recipes, on "Where do you usually store your recipes?"
private enum RecipeSource: String, CaseIterable, Identifiable {
    case instagram
    case tiktok
    case facebook
    case youtubeShorts = "youtube_shorts"
    case websites

    var id: String { rawValue }

    var name: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .facebook: "Facebook"
        case .youtubeShorts: "YouTube Shorts"
        case .websites: "Recipe websites"
        }
    }

    /// Logo in the asset catalog; websites use a globe symbol
    var logo: String? {
        switch self {
        case .instagram: "instagramLogo"
        case .tiktok: "tiktokLogo"
        case .facebook: "facebookLogo"
        case .youtubeShorts: "youtubeShortsLogo"
        case .websites: nil
        }
    }
}

struct OnboardingFlowView: View {
    @ObservedObject var router: AuthRouter
    /// Set when Create account opens on top, so coming back lands on the page before Setting up
    @State private var didOpenCreateAccount = false
    @State private var hasLoggedStart = false

    @State private var page: OnboardingPage
    @State private var name = ""
    @State private var sources: Set<RecipeSource> = []
    @State private var tutorialOutcome: ShareTutorialView.Outcome?
    @State private var showingTutorial = false
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(router: AuthRouter) {
        self.router = router
        _page = State(initialValue: .intro)
    }

    /// `page` is only for previews; onboarding always starts at the intro
    fileprivate init(router: AuthRouter, startingAt page: OnboardingPage) {
        self.router = router
        _page = State(initialValue: page)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch page {
                case .intro: introPage
                case .name: namePage
                case .sources: sourcesPage
                case .showHow: showHowPage
                case .settingUp: settingUpPage
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
        .sensoryFeedback(.selection, trigger: sources)
        .onAppear {
            if !hasLoggedStart {
                hasLoggedStart = true
                Analytics.log(.onboardingStarted)
            }
            // Back from Create account: Setting up only runs forwards, so show the page before it
            if didOpenCreateAccount {
                didOpenCreateAccount = false
                page = .showHow
            }
        }
        .fullScreenCover(isPresented: $showingTutorial, onDismiss: {
            // The questionnaire continues after the tutorial, however it ended
            goForward()
        }) {
            ShareTutorialView(context: .onboarding, sources: tutorialSources) { outcome in
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
            case .settingUp:
                // Moves on by itself
                EmptyView()
            case .showHow:
                OnboardingPrimaryButton(title: "Show me how") {
                    showingTutorial = true
                }
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
        case .name: !name.trimmed.isEmpty
        case .sources: !sources.isEmpty
        default: true
        }
    }

    // MARK: Pages

    /// Social proof: a user review
    private var introPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                Text("We've helped thousands of cooks")
                    .font(.custom("Playfair9pt-SemiBold", size: 26))
                Text("be more organized")
                    .font(.custom("Playfair9pt-SemiBold", size: 26))
                    .foregroundColor(Color("Orange"))
                Text("in the kitchen")
                    .font(.custom("Playfair9pt-SemiBold", size: 26))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 12)

            VStack(spacing: 14) {
                ForEach(OnboardingReview.featured) { review in
                    ReviewCard(review: review)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
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

    private var sourcesPage: some View {
        ScrollView(showsIndicators: false) {
            OnboardingTitle(title: "Where do you usually store your recipes?", subtitle: "Select all that apply")
                .padding(.bottom, 24)

            VStack(spacing: 10) {
                ForEach(RecipeSource.allCases) { source in
                    SourceOptionRow(source: source, isSelected: sources.contains(source)) {
                        toggle(source)
                    }
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

    /// The first social app picked (Instagram if none), unless only websites were picked;
    /// then websites if picked
    private var tutorialSources: [ShareTutorialView.Source] {
        var tutorials: [ShareTutorialView.Source] = []
        let apps: [(RecipeSource, ShareTutorialView.Source)] = [
            (.instagram, .instagram), (.tiktok, .tiktok), (.facebook, .facebook), (.youtubeShorts, .youtubeShorts)
        ]
        if let app = apps.first(where: { sources.contains($0.0) }) {
            tutorials.append(app.1)
        } else if !sources.contains(.websites) {
            tutorials.append(.instagram)
        }
        if sources.contains(.websites) {
            tutorials.append(.website)
        }
        return tutorials
    }

    /// Names the apps the user picked, plus websites
    private var showHowMessage: String {
        var names = RecipeSource.allCases.filter { $0 != .websites && sources.contains($0) }.map(\.name)
        if names.isEmpty {
            names = RecipeSource.allCases.filter { $0 != .websites }.map(\.name)
        }
        if sources.contains(.websites) {
            names.append("websites")
        }
        return "Salt can import recipes from \(names.formatted(.list(type: .and)))."
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
            // Not again when coming back from Create account
            guard !Task.isCancelled, !didOpenCreateAccount else { return }
            goForward()
        }
    }

    // MARK: Navigation

    private func toggle(_ source: RecipeSource) {
        if sources.contains(source) {
            sources.remove(source)
        } else {
            sources.insert(source)
        }
    }

    private func goForward() {
        logAnswer(for: page)
        isTextFieldFocused = false
        guard let next = OnboardingPage(rawValue: page.rawValue + 1) else {
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
        while let candidate = previous, candidate == .settingUp {
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
        guard page == .sources else { return }
        Analytics.log(.onboardingQuestionAnswered, [
            "question": page.analyticsName,
            "answers": sources.map(\.rawValue).sorted()
        ])
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
            userProperties: ["onboarding_recipe_sources": sources.map(\.rawValue).sorted()]
        )
        UserDefaults.standard.set(name.trimmed, forKey: OnboardingStorage.nameKey)
        // Pushed on top, so Create account's back button returns here
        didOpenCreateAccount = true
        router.navigate(to: .createAccount)
    }
}

// MARK: - Create Account

/// Last onboarding step: Apple, Google, or the email form under Other options.
/// The launch paywall shows right after the account is created.
struct OnboardingAccountView: View {
    @ObservedObject var router: AuthRouter
    @StateObject private var viewModel = SignUpViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                OnboardingLogo()
                HStack(spacing: 14) {
                    Button {
                        router.navigateBack()
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

/// Five stars, the quote and the reviewer, like an App Store review
private struct ReviewCard: View {
    let review: OnboardingReview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.76, blue: 0.03))
                    }
                }
                .font(.system(size: 16))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("5 stars")

                Spacer()

                Image(systemName: "quote.opening")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Color("Orange"))
                    .accessibilityHidden(true)
            }

            Text("\u{201C}\(review.quote)\u{201D}")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundColor(Color("GraniteGray"))
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 10) {
                avatar
                Text(review.name)
                    .font(.custom("OpenSans-SemiBold", size: 14))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color("GrayButtonBorderColor"), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    @ViewBuilder
    private var avatar: some View {
        if let image = review.avatarImage {
            Image(image)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else {
            Text(review.initials)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundColor(Color("Orange"))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color("PeachCream")))
        }
    }
}

/// A recipe source with its logo and a checkbox
private struct SourceOptionRow: View {
    let source: RecipeSource
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Group {
                    if let logo = source.logo {
                        Image(logo)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "globe")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(Color("GraniteGray"))
                    }
                }
                .frame(width: 24, height: 24)

                Text(source.name)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundColor(.black)

                Spacer()

                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Color("Orange") : Color("GrayButtonBorderColor"))
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color("PeachCream") : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color("Orange") : Color("GrayButtonBorderColor"), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
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

/// Recipe photo surrounded by the logos of the apps Salt imports from
private struct ImportSourcesIllustration: View {
    private let recipe = TutorialSampleRecipe.current

    var body: some View {
        ZStack {
            TutorialRecipePhoto(url: recipe.imageUrl)
                .frame(width: 170, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)

            logoBadge("instagramLogo")
                .offset(x: -100, y: -80)
            logoBadge("tiktokLogo")
                .offset(x: 105, y: -40)
            logoBadge("facebookLogo")
                .offset(x: -100, y: 55)
            logoBadge("youtubeShortsLogo")
                .offset(x: 100, y: 90)
        }
        .frame(height: 260)
        .accessibilityHidden(true)
    }

    private func logoBadge(_ logo: String) -> some View {
        Image(logo)
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 30)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }
}

/// Salt icon with ramen ingredients circling it
private struct SettingUpAnimation: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(Array(["🍜", "🥚", "🌶️", "🧄"].enumerated()), id: \.offset) { index, emoji in
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

// MARK: - Preview

#Preview("Welcome") {
    WelcomeView(router: AuthRouter())
}

#Preview("Intro") {
    OnboardingFlowView(router: AuthRouter())
}

#Preview("Sources") {
    OnboardingFlowView(router: AuthRouter(), startingAt: .sources)
}

#Preview("Show How") {
    OnboardingFlowView(router: AuthRouter(), startingAt: .showHow)
}

#Preview("Setting Up") {
    OnboardingFlowView(router: AuthRouter(), startingAt: .settingUp)
}

#Preview("Create Account") {
    OnboardingAccountView(router: AuthRouter())
}
