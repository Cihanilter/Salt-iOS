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
    /// Set once the import tutorial has been shown in onboarding, so a web buyer who went
    /// through Get started before logging in doesn't get it again (see WebBuyerWelcome)
    static let tutorialSeenKey = "onboardingTutorialSeen"
    /// The social app picked in "Where do you find recipes?", so the in-app share how-to
    /// shows that app's walkthrough (a `ShareTutorialView.Source` raw value)
    static let socialSourceKey = "onboardingSocialSource"

    /// The walkthrough to show in the app: the onboarding pick, otherwise Instagram
    static var preferredSocialSource: ShareTutorialView.Source {
        UserDefaults.standard.string(forKey: socialSourceKey)
            .flatMap(ShareTutorialView.Source.init(rawValue:)) ?? .instagram
    }
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
        ),
        OnboardingReview(
            quote: "I am so thankful that I finally found a way to organize my recipes.",
            name: "sophia81",
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
    /// The short demos picked from the sources (OnboardingDemos.swift)
    case demos

    var analyticsName: String {
        switch self {
        case .intro: "intro"
        case .name: "name"
        case .sources: "recipe_sources"
        case .demos: "demos"
        }
    }

    /// Pages with the logo and progress bar on top; the rest have their own top bar
    var showsProgressHeader: Bool {
        self == .intro || self == .name
    }
}

/// Answers to "Where do you find recipes?" (saved for analytics)
private enum RecipeSource: String, CaseIterable, Identifiable {
    case instagram
    case tiktok
    case youtube
    case facebook
    case websites
    case cookbooks
    case handwritten
    case screenshots
    case notes

    var id: String { rawValue }

    var name: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .facebook: "Facebook"
        case .websites: "Websites & blogs"
        case .cookbooks: "Cookbooks"
        case .handwritten: "Handwritten & family"
        case .screenshots: "Screenshots"
        case .notes: "Notes"
        }
    }

    /// The app's own logo, for the social apps
    var logo: String? {
        switch self {
        case .instagram: "instagramLogo"
        case .tiktok: "tiktokLogo"
        case .youtube: "youtubeShortsLogo"
        case .facebook: "facebookLogo"
        case .websites, .cookbooks, .handwritten, .screenshots, .notes: nil
        }
    }

    /// Gray icon in the row's cream circle, for the rest
    var systemImage: String {
        switch self {
        case .instagram, .tiktok, .youtube, .facebook: "play.rectangle"
        case .websites: "globe"
        case .cookbooks: "book"
        case .handwritten: "pencil"
        case .screenshots: "photo.on.rectangle"
        case .notes: "note.text"
        }
    }

    /// The share walkthrough for the social apps
    var tutorialSource: ShareTutorialView.Source? {
        switch self {
        case .instagram: .instagram
        case .tiktok: .tiktok
        case .youtube: .youtubeShorts
        case .facebook: .facebook
        case .websites, .cookbooks, .handwritten, .screenshots, .notes: nil
        }
    }

    /// Notes have no demo: a note is shared or pasted as text, which needs no showing
    var demo: OnboardingDemo? {
        switch self {
        case .instagram, .tiktok, .youtube, .facebook: .social
        case .websites: .website
        case .cookbooks, .handwritten, .screenshots: .photo
        case .notes: nil
        }
    }
}

/// Where the app opens after sign-up, from the end of onboarding (read by MainTabView)
enum OnboardingDestination: String {
    case addRecipe = "add_recipe"
    case explore

    static let key = "onboardingDestination"

    /// Read once after sign-up; nil when onboarding didn't set one
    static func consume() -> OnboardingDestination? {
        defer { UserDefaults.standard.removeObject(forKey: key) }
        return UserDefaults.standard.string(forKey: key).flatMap(OnboardingDestination.init(rawValue:))
    }
}

struct OnboardingFlowView: View {
    @ObservedObject var router: AuthRouter
    @State private var hasLoggedStart = false

    @State private var page: OnboardingPage
    @State private var name = ""
    @State private var sources: Set<RecipeSource> = []
    /// Demos picked from the sources, in order: social, websites, photos (up to 3)
    @State private var demos: [OnboardingDemo] = []
    @State private var demoIndex = 0
    @State private var learned: Set<OnboardingDemo> = []
    @State private var showingSocialDemo = false
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

    private var currentDemo: OnboardingDemo? {
        demos.indices.contains(demoIndex) ? demos[demoIndex] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if page.showsProgressHeader {
                header
            }

            Group {
                switch page {
                case .intro: introPage
                case .name: namePage
                case .sources: sourcesPage
                case .demos: demoPage
                }
            }
            .id(page.rawValue * 10 + (page == .demos ? demoIndex : 0))
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity
            ))
            .frame(maxHeight: .infinity, alignment: .top)

            if page.showsProgressHeader || page == .sources {
                footer
            }
        }
        .background(Color.white.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: sources)
        .onAppear {
            if !hasLoggedStart {
                hasLoggedStart = true
                Analytics.log(.onboardingStarted)
            }
        }
        .fullScreenCover(isPresented: $showingSocialDemo) {
            // The existing share walkthrough, with the progress line; its Skip goes to the next demo
            ShareTutorialView(
                context: .onboarding,
                sources: [socialSource],
                progress: progress(for: .social),
                nextTitle: demos.indices.contains(demoIndex + 1) ? demos[demoIndex + 1].nextTitle : String(localized: "Continue")
            ) { outcome in
                UserDefaults.standard.set(true, forKey: OnboardingStorage.tutorialSeenKey)
                if outcome != .skipped { learned.insert(.social) }
                showingSocialDemo = false
                nextDemo()
            }
        }
    }

    // MARK: Header & Footer

    private var header: some View {
        VStack(spacing: 10) {
            OnboardingLogo()

            HStack(spacing: 14) {
                backButton

                // Then the sources question, the demos and Create account
                ProgressView(value: Double(page.rawValue + 1), total: Double(OnboardingPage.allCases.count + 1))
                    .tint(SaltColor.actionPrimary)
                    .animation(.easeInOut, value: page)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var backButton: some View {
        Button {
            goBack()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SaltColor.iconDefault)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Back")
    }

    private var footer: some View {
        OnboardingPrimaryButton(title: "Continue", isEnabled: canContinue) {
            goForward()
        }
        .padding(.horizontal, SaltSpacing.screenMargin)
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
            Text("Thousands of cooks \(Text("love").foregroundStyle(SaltColor.textAccent)) using Salt")
                .font(.custom("Playfair9pt-Regular", size: 28))
                .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 28)

            ReviewSlider(reviews: OnboardingReview.featured)
                .padding(.top, 24)
                .padding(.bottom, 16)
        }
    }

    private var namePage: some View {
        VStack(spacing: 24) {
            OnboardingTitle(title: "What should we call you?", subtitle: "This helps us to personalize your experience.")

            TextField("Your name", text: $name)
                .textContentType(.givenName)
                .submitLabel(.continue)
                .focused($isTextFieldFocused)
                .onSubmit { if canContinue { goForward() } }
                .frame(height: 28)
                .saltInput(isFocused: isTextFieldFocused)
                .padding(.horizontal, SaltSpacing.screenMargin)
        }
        .onAppear { isTextFieldFocused = true }
    }

    /// "Where do you find recipes?": a calm list in one color; Skip goes straight on
    private var sourcesPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                backButton
                    .padding(.leading, -12)
                Spacer()
                Button("Skip") {
                    Analytics.log(.onboardingQuestionAnswered, ["question": OnboardingPage.sources.analyticsName, "answers": [String]()])
                    finish(destination: .addRecipe)
                }
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textSecondary)
            }
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Where do you find recipes?")
                        .font(SaltFont.h1)
                        .foregroundStyle(SaltColor.textPrimary)
                        .padding(.top, 16)
                    Text("Pick all that apply. We\u{2019}ll show you how to save from each \u{2014} skip any you don\u{2019}t need.")
                        .font(SaltFont.bodyLarge)
                        .foregroundStyle(SaltColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)

                    VStack(spacing: 8) {
                        ForEach(RecipeSource.allCases) { source in
                            OnboardingSourceRow(
                                logo: source.logo,
                                systemImage: source.systemImage,
                                title: source.name,
                                isSelected: sources.contains(source)
                            ) {
                                toggle(source)
                            }
                        }
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                }
            }
        }
        .padding(.horizontal, SaltSpacing.screenMargin)
    }

    @ViewBuilder private var demoPage: some View {
        switch currentDemo {
        case .website, .photo:
            OnboardingSampleDemoView(
                demo: currentDemo!,
                progress: progress(for: currentDemo!),
                onDone: {
                    learned.insert(currentDemo!)
                    nextDemo()
                },
                onSkip: nextDemo
            )
        case .social, nil:
            // The social demo plays full screen on top
            Color.white
        }
    }

    // MARK: Demos

    /// The first social app picked (in list order); its walkthrough covers them all
    private var socialSource: ShareTutorialView.Source {
        RecipeSource.allCases.first { sources.contains($0) && $0.tutorialSource != nil }?.tutorialSource ?? .instagram
    }

    /// "Instagram & TikTok · 1 of 3"
    private func progress(for demo: OnboardingDemo) -> OnboardingDemoProgress? {
        guard demos.count > 1, let index = demos.firstIndex(of: demo) else { return nil }
        let label: String
        switch demo {
        case .social:
            let apps = RecipeSource.allCases.filter { sources.contains($0) && $0.tutorialSource != nil }.map(\.name)
            label = apps.prefix(2).joined(separator: " & ")
        case .website:
            label = String(localized: "Websites & food blogs")
        case .photo:
            label = String(localized: "Cookbooks & handwritten notes")
        }
        return OnboardingDemoProgress(label: label, index: index, total: demos.count)
    }

    private func startDemos() {
        let order: [OnboardingDemo] = [.social, .website, .photo]
        let picked = Set(sources.compactMap(\.demo))
        demos = order.filter(picked.contains)
        demoIndex = 0
        learned = []
        showCurrentDemo()
    }

    private func showCurrentDemo() {
        // After the last demo, straight on to Create account; the app then opens on Add Recipe
        guard let demo = currentDemo else {
            finish(destination: .addRecipe)
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { page = .demos }
        if demo == .social {
            showingSocialDemo = true
        }
    }

    private func nextDemo() {
        demoIndex += 1
        // After the full-screen walkthrough closes, so the next screen isn't covered
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            showCurrentDemo()
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
        if page == .sources {
            startDemos()
            return
        }
        guard let next = OnboardingPage(rawValue: page.rawValue + 1) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            page = next
        }
    }

    private func goBack() {
        isTextFieldFocused = false
        guard let previous = OnboardingPage(rawValue: page.rawValue - 1) else {
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
    /// After sign-up the app opens on `destination`.
    private func finish(destination: OnboardingDestination) {
        let tutorial: String
        if demos.isEmpty {
            tutorial = "not_started"
        } else {
            tutorial = learned.isEmpty ? "skipped" : "completed"
        }
        Analytics.log(
            .onboardingCompleted,
            [
                "tutorial": tutorial,
                "demos": demos.map(\.rawValue),
                "demos_completed": learned.map(\.rawValue).sorted()
            ],
            userProperties: ["onboarding_recipe_sources": sources.map(\.rawValue).sorted()]
        )
        UserDefaults.standard.set(name.trimmed, forKey: OnboardingStorage.nameKey)
        if sources.contains(where: { $0.tutorialSource != nil }) {
            UserDefaults.standard.set(socialSource.rawValue, forKey: OnboardingStorage.socialSourceKey)
        }
        UserDefaults.standard.set(destination.rawValue, forKey: OnboardingDestination.key)
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

struct OnboardingLogo: View {
    var body: some View {
        Image("saltAppIcon")
            .resizable()
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

struct OnboardingTitle: View {
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

/// Reviews one at a time: swipe between them, or they move on every few seconds
private struct ReviewSlider: View {
    let reviews: [OnboardingReview]

    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            TabView(selection: $index) {
                ForEach(Array(reviews.enumerated()), id: \.element.id) { offset, review in
                    ReviewCard(review: review)
                        .padding(.horizontal, 20)
                        // Room for the card's shadow
                        .padding(.vertical, 10)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 228)

            // Page dots in the app's colors (the system ones are white)
            HStack(spacing: 8) {
                ForEach(reviews.indices, id: \.self) { dot in
                    Capsule()
                        .fill(dot == index ? Color("Orange") : Color("GrayButtonBorderColor"))
                        .frame(width: dot == index ? 18 : 8, height: 8)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: index)
            .accessibilityHidden(true)
        }
        // Restarts after every change, so a swipe gets the full time before it moves on
        .task(id: index) {
            guard !reduceMotion, reviews.count > 1 else { return }
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                index = (index + 1) % reviews.count
            }
        }
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
        // Same height for every card in the slider, content at the top
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

struct OnboardingPrimaryButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.salt())
            .disabled(!isEnabled)
    }
}

/// Recipe photo surrounded by the logos of the apps Salt imports from
struct ImportSourcesIllustration: View {
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

#Preview("Create Account") {
    OnboardingAccountView(router: AuthRouter())
}
