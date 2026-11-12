//
//  ShareTutorialView.swift
//  Salt
//
//  Interactive walkthrough of importing a recipe: the user taps Share > Share to... >
//  More > Salt on a mock social post (or ••• > Share > More > Salt on a recipe website
//  in Safari) and sees the recipe land in Salt.
//  Used at the end of onboarding, from the Explore banner, and after a web buyer's first login.
//

import SwiftUI

struct ShareTutorialView: View {
    /// Where the tutorial was opened from; changes the final call to action
    enum Context: String {
        case onboarding
        case explore
        /// After a web funnel buyer's first login (WebBuyerWelcomeView)
        case webWelcome = "web_welcome"

        /// Ends with "Try it on Instagram" and Maybe later instead of Continue
        var endsWithRealImport: Bool { self != .onboarding }
    }

    /// How the tutorial ended
    enum Outcome {
        /// Finished the walkthrough and tapped the main button
        case completed
        /// Finished and chose to paste a link instead (Explore only)
        case pasteLink
        case skipped
    }

    /// What the walkthrough imports from: a social app's recipe post, or a website in Safari
    enum Source: String {
        case instagram
        case tiktok
        case facebook
        case youtubeShorts = "youtube_shorts"
        case website

        var isSocial: Bool { self != .website }

        var name: String {
            switch self {
            case .instagram: "Instagram"
            case .tiktok: "TikTok"
            case .facebook: "Facebook"
            case .youtubeShorts: "YouTube Shorts"
            case .website: "Safari"
            }
        }

        /// Logo in the asset catalog
        var logo: String? {
            switch self {
            case .instagram: "instagramLogo"
            case .tiktok: "tiktokLogo"
            case .facebook: "facebookLogo"
            case .youtubeShorts: "youtubeShortsLogo"
            case .website: nil
            }
        }

        /// Shown under the shared item on the iOS share sheet
        var domain: String {
            switch self {
            case .instagram: "instagram.com"
            case .tiktok: "tiktok.com"
            case .facebook: "facebook.com"
            case .youtubeShorts: "youtube.com"
            case .website: TutorialWebsiteView.domain
            }
        }

        /// The post's share button
        var shareIcon: String {
            self == .instagram ? "paperplane" : "arrowshape.turn.up.right.fill"
        }

        /// Button on the app's own share sheet that opens the iOS share sheet
        var shareToLabel: String {
            switch self {
            case .instagram: "Share to..."
            case .facebook: "More options"
            case .tiktok, .youtubeShorts, .website: "More"
            }
        }

        /// Opens the app, to try a real import after the tutorial
        var appURL: URL {
            switch self {
            case .instagram: URL(string: "instagram://app")!
            case .tiktok: URL(string: "tiktok://")!
            case .facebook: URL(string: "fb://")!
            case .youtubeShorts: URL(string: "youtube://")!
            case .website: webURL
            }
        }

        /// Used when the app isn't installed
        var webURL: URL {
            switch self {
            case .instagram: URL(string: "https://www.instagram.com")!
            case .tiktok: URL(string: "https://www.tiktok.com")!
            case .facebook: URL(string: "https://www.facebook.com")!
            case .youtubeShorts: URL(string: "https://www.youtube.com/shorts")!
            case .website: URL(string: "https://www.google.com/search?q=easy+dinner+recipes")!
            }
        }
    }

    let context: Context
    /// Played in order; the next one starts after the first is imported.
    /// State so "See how" on the last screen can add the website walkthrough.
    @State private var sources: [Source]
    let onFinish: (Outcome) -> Void
    /// In the onboarding demo queue: "Instagram & TikTok · 1 of 3" under the top bar
    var progress: OnboardingDemoProgress?
    /// The saved screen's button when another demo follows, e.g. "Next: websites"
    var nextTitle: String?

    @State private var step: Step
    @State private var sourceIndex = 0
    /// Bumped when the user taps outside the highlighted target, to bounce the hint
    @State private var missedTaps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private let recipe = TutorialSampleRecipe.current

    /// `step` is only for previews; the tutorial always starts on the post
    init(
        context: Context,
        sources: [Source] = [.instagram],
        startingAt step: Step = .post,
        progress: OnboardingDemoProgress? = nil,
        nextTitle: String? = nil,
        onFinish: @escaping (Outcome) -> Void
    ) {
        self.context = context
        _sources = State(initialValue: sources.isEmpty ? [.instagram] : sources)
        self.onFinish = onFinish
        self.progress = progress
        self.nextTitle = nextTitle
        _step = State(initialValue: step)
    }

    private var source: Source { sources[sourceIndex] }
    private var hasNextSource: Bool { sourceIndex < sources.count - 1 }
    /// The last screen offers trying it for real (in-app only), or Maybe later
    private var showsRealImportChoices: Bool { context.endsWithRealImport && !hasNextSource }
    /// Onboarding sells the one tap: Salt sits right on the share sheet. The in-app how-to
    /// also shows finding it under More and adding it to Favorites, as on a real phone.
    private var sharesToSaltDirectly: Bool { context == .onboarding }

    private var primaryTitle: String {
        if hasNextSource { return "Next: recipe websites" }
        if let nextTitle { return nextTitle }
        guard context.endsWithRealImport else { return "Continue" }
        return "Try it on \(source.name)"
    }

    enum Step: Int {
        /// The social post, or the recipe website
        case post
        /// The social app's share sheet, or Safari's ••• menu
        case appShareSheet
        case systemShareSheet
        case appsList
        case importing
        case imported

        /// Name sent with the skipped event, to see where people drop off
        var analyticsName: String {
            switch self {
            case .post: "post"
            case .appShareSheet: "app_share_sheet"
            case .systemShareSheet: "system_share_sheet"
            case .appsList: "apps_list"
            case .importing: "importing"
            case .imported: "imported"
            }
        }
    }

    var body: some View {
        ZStack {
            switch step {
            case .post, .appShareSheet, .systemShareSheet, .appsList:
                appScreen
                    .transition(.opacity)
            case .importing:
                // The same loading screen as a real import
                ImportProgressView(kind: .link, onCancel: nil)
                    .padding(.top, progress != nil ? 48 : 0)
                    .background(Color(.systemBackground).ignoresSafeArea())
                    .transition(.opacity)
            case .imported:
                TutorialImportedView(
                    recipe: recipe,
                    context: context,
                    primaryTitle: primaryTitle,
                    hasProgress: progress != nil,
                    showsMaybeLater: showsRealImportChoices,
                    // Social walkthroughs only; the website one is what "See how" plays
                    showsWebsiteHint: showsRealImportChoices && source.isSocial,
                    onPrimary: finishPrimary,
                    onMaybeLater: { finish(.completed) },
                    onSeeWebsites: playWebsiteWalkthrough
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if let progress {
                OnboardingDemoProgressBar(progress: progress, onDark: step != .importing && step != .imported)
                    .padding(.horizontal, SaltSpacing.screenMargin)
                    .padding(.top, step == .imported || step == .importing ? 8 : 52)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            // "Show me how": a way out on the last screen without trying it for real
            if step == .imported && context.endsWithRealImport && progress == nil {
                Button {
                    finish(.completed)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SaltColor.iconDefault)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
                // The glyph lines up with the screen margin; level with the "Saved to My Recipes" pill
                .padding(.trailing, SaltSpacing.screenMargin - 14)
                .padding(.top, 17)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Not over the short transformation, where it would cover the progress line
            if step != .imported && step != .importing {
                Button("Skip") { finish(.skipped) }
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(.trailing, 16)
                    .padding(.top, 8)
            }
        }
        .environment(\.tutorialStepCount, sharesToSaltDirectly ? 3 : 5)
        .sensoryFeedback(.impact(weight: .light), trigger: step)
        .sensoryFeedback(.warning, trigger: missedTaps)
        .onAppear {
            logStarted()
        }
        .task(id: step) {
            // Shows the import running for a moment, like the real share extension.
            // Cancelled if the tutorial is skipped or closed meanwhile.
            guard step == .importing else { return }
            try? await Task.sleep(for: .seconds(reduceMotion ? 1.2 : 2.8))
            guard !Task.isCancelled else { return }
            advance(to: .imported)
            Analytics.log(.importTutorialCompleted, ["context": context.rawValue, "source": source.rawValue])
        }
    }

    // MARK: - Mock App

    /// A recipe post in a social app (or a recipe website in Safari), with the app's
    /// and the iOS share sheets on top
    private var appScreen: some View {
        ZStack(alignment: .bottom) {
            Group {
                if source.isSocial {
                    TutorialPostView(recipe: recipe, source: source, isDimmed: step != .post, missedTaps: missedTaps, onShare: { advance(to: .appShareSheet) })
                } else {
                    TutorialWebsiteView(recipe: recipe, isDimmed: step != .post, missedTaps: missedTaps, onMenu: { advance(to: .appShareSheet) })
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { missedTap() }

            if step == .appShareSheet {
                if source.isSocial {
                    TutorialAppShareSheet(source: source, missedTaps: missedTaps, onShareTo: { advance(to: .systemShareSheet) })
                        .transition(.move(edge: .bottom))
                } else {
                    TutorialSafariMenu(missedTaps: missedTaps, onShare: { advance(to: .systemShareSheet) })
                        .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }

            if step == .systemShareSheet {
                TutorialSystemShareSheet(
                    recipe: recipe,
                    source: source,
                    missedTaps: missedTaps,
                    showsSalt: sharesToSaltDirectly,
                    onMore: { advance(to: .appsList) },
                    onSalt: { advance(to: .importing) }
                )
                    .transition(.move(edge: .bottom))
            }

            if step == .appsList {
                TutorialAppsListSheet(missedTaps: missedTaps, onSalt: { advance(to: .importing) })
                    .transition(.move(edge: .bottom))
            }
        }
    }

    // MARK: - Steps

    private func advance(to next: Step) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.4)) {
            step = next
        }
    }

    private func missedTap() {
        missedTaps += 1
    }

    private func logStarted() {
        Analytics.log(.importTutorialStarted, ["context": context.rawValue, "source": source.rawValue])
    }

    private func finishPrimary() {
        if hasNextSource {
            // On to the next walkthrough, e.g. websites after social media
            sourceIndex += 1
            logStarted()
            advance(to: .post)
            return
        }
        if context.endsWithRealImport {
            // The real thing: open the app to share a recipe from it.
            // Without the app installed, its website (sharing from Safari works too).
            let source = source
            openURL(source.appURL) { opened in
                if opened {
                    finish(.completed)
                } else {
                    openURL(source.webURL) { _ in finish(.completed) }
                }
            }
        } else {
            finish(.completed)
        }
    }

    /// "Works the same on websites. See how": the same walkthrough in Safari
    private func playWebsiteWalkthrough() {
        sources.append(.website)
        sourceIndex = sources.count - 1
        logStarted()
        advance(to: .post)
    }

    private func finish(_ outcome: Outcome) {
        if outcome == .skipped {
            Analytics.log(.importTutorialSkipped, ["context": context.rawValue, "source": source.rawValue, "step": step.analyticsName])
        }
        onFinish(outcome)
    }
}

// MARK: - Sample Recipe

/// Recipe shown in the tutorial, taken from the bundled curated recipes so it has a real photo
struct TutorialSampleRecipe {
    let title: String
    let imageUrl: URL?
    let ingredients: [String]
    let totalTimeMinutes: Int?
    let servings: Int?
    /// Time and ingredient count as the recipe screen shows them
    let detail: RecipeDetail

    /// Quick Chicken Ramen Bowl: short, recognizable, few ingredients
    private static let preferredId = UUID(uuidString: "92f3f1b9-dd2b-4d70-9a0a-0ebd33e8dbd7")

    @MainActor
    static var current: TutorialSampleRecipe {
        let recipes = CuratedRecipesManager.shared.recipes
        guard let recipe = recipes.first(where: { $0.id == preferredId }) ?? recipes.first else {
            return TutorialSampleRecipe(
                title: "Quick Chicken Ramen Bowl",
                imageUrl: nil,
                ingredients: ["Ramen noodles", "Cooked chicken", "Water", "Creole seasoning", "Hot sauce"],
                totalTimeMinutes: 20,
                servings: 1,
                detail: RecipeDetail(
                    title: "Quick Chicken Ramen Bowl",
                    duration: "20 mins",
                    ingredientsCount: "5 ingredients",
                    description: "A quick, cozy bowl of ramen with chicken.",
                    servings: "1 serving",
                    prepTime: "5",
                    cookTime: "15",
                    ingredients: ["Ramen noodles", "Cooked chicken", "Water", "Creole seasoning", "Hot sauce"],
                    instructions: ["Bring the water to a boil.", "Add the noodles and chicken, and cook until tender."],
                    notes: "",
                    images: [],
                    sourceUrl: nil,
                    sourceName: nil
                )
            )
        }
        let detail = recipe.toRecipeDetail()
        return TutorialSampleRecipe(
            title: recipe.title,
            imageUrl: recipe.imageUrl.flatMap(URL.init(string:)),
            ingredients: recipe.ingredients,
            totalTimeMinutes: recipe.totalTimeMinutes,
            servings: recipe.servings,
            detail: detail
        )
    }
}

// MARK: - Recipe Photo

struct TutorialRecipePhoto: View {
    let url: URL?

    var body: some View {
        CachedAsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            ZStack {
                LinearGradient(
                    colors: [Color("PeachCream"), Color("LightGrayishPink")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "fork.knife")
                    .font(.system(size: 36))
                    .foregroundColor(Color("GraniteGray"))
            }
        }
    }
}

// MARK: - Hint

/// Soft coach mark: "1 of 4" in pink over one short instruction, on a white card
private struct TutorialHint: View {
    let step: Int
    let text: String
    let missedTaps: Int
    @Environment(\.tutorialStepCount) private var totalSteps

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(step) of \(totalSteps)")
                .font(SaltFont.bodyStrong)
                .foregroundStyle(SaltColor.iconMeta)
            Text(text)
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 260, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        // Bounces when the user taps somewhere else
        .keyframeAnimator(initialValue: 1.0, trigger: missedTaps) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(1.08, duration: 0.15)
            SpringKeyframe(1.0, duration: 0.3)
        }
        .accessibilityHidden(true)
    }
}

/// Pulsing ring around the element to tap
private struct TutorialPulse: ViewModifier {
    var cornerRadius: CGFloat = 100
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color("Orange"), lineWidth: 3)
                    .padding(-6)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color("Orange").opacity(0.3))
                    .padding(-12)
                    .scaleEffect(isPulsing ? 1.15 : 0.9)
                    .opacity(isPulsing ? 0.2 : 0.8)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

private extension View {
    func tutorialPulse(cornerRadius: CGFloat = 100) -> some View {
        modifier(TutorialPulse(cornerRadius: cornerRadius))
    }
}

// MARK: - Step 1: Post

/// Full-screen recipe video post, like an Instagram Reel or TikTok
private struct TutorialPostView: View {
    let recipe: TutorialSampleRecipe
    let source: ShareTutorialView.Source
    let isDimmed: Bool
    let missedTaps: Int
    let onShare: () -> Void

    var body: some View {
        Color.clear
            .background {
                // In the background so the photo's fill size doesn't widen the layout
                TutorialRecipePhoto(url: recipe.imageUrl)
                    .clipped()
                    .ignoresSafeArea()
            }
            .overlay {
                // Darkens the bottom so the caption and buttons read on any photo
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                    .ignoresSafeArea()
            }
            .overlay(alignment: .topLeading) { appLabel }
            .overlay(alignment: .bottomLeading) { caption }
            .overlay(alignment: .bottomTrailing) { sideActions }
            .overlay(Color.black.opacity(isDimmed ? 0.45 : 0).ignoresSafeArea())
    }

    /// Which app this is, e.g. "Instagram example"
    private var appLabel: some View {
        HStack(spacing: 6) {
            if let logo = source.logo {
                Image(logo)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .padding(4)
                    .background(Circle().fill(Color.white))
            }
            Text("\(source.name) example")
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundColor(.white)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .padding(.leading, 16)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color("PeachCream"))
                    .frame(width: 32, height: 32)
                    .overlay(Image(systemName: "person.fill").foregroundColor(Color("GraniteGray")))
                Text("dinnerin10")
                    .font(.custom("OpenSans-SemiBold", size: 14))
            }
            Text("\(recipe.title) 🍜 Recipe in caption!")
                .font(.custom("OpenSans-Regular", size: 13))
                .lineLimit(2)
        }
        .foregroundColor(.white)
        .padding(.leading, 16)
        .padding(.trailing, 90)
        .padding(.bottom, 16)
    }

    private var sideActions: some View {
        VStack(spacing: 22) {
            postAction("heart", label: "12.4K")
            postAction("bubble.right", label: "318")
            Button(action: onShare) {
                postAction(source.shareIcon, label: "Share")
            }
            .buttonStyle(.plain)
            .disabled(isDimmed)
            .tutorialPulse(cornerRadius: 14)
            .opacity(isDimmed ? 0 : 1)
            // Hint sits just left of the Share button
            .overlay(alignment: .trailing) {
                if !isDimmed {
                    // Ends left of the button: the overlay is wider than the button and
                    // grows leftwards from its trailing edge
                    TutorialHint(step: 1, text: "Tap Share to send this post", missedTaps: missedTaps)
                        .fixedSize()
                        .padding(.trailing, 68)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Share")
            .accessibilityHint("Step 1 of 4")
            postAction("ellipsis", label: "")
        }
        .padding(.trailing, 16)
        .padding(.bottom, 90)
    }

    private func postAction(_ systemName: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 26, weight: .medium))
            if !label.isEmpty {
                Text(label)
                    .font(.custom("OpenSans-SemiBold", size: 11))
            }
        }
        .foregroundColor(.white)
        .shadow(color: .black.opacity(0.3), radius: 3)
        .frame(width: 48)
    }
}

// MARK: - Step 2: Social App's Share Sheet

private struct TutorialAppShareSheet: View {
    let source: ShareTutorialView.Source
    let missedTaps: Int
    let onShareTo: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Search field placeholder
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
                .frame(height: 36)
                .overlay(alignment: .leading) {
                    Label("Search", systemImage: "magnifyingglass")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(Color(.systemGray))
                        .padding(.leading, 12)
                }
                .padding(.horizontal, 16)

            // Friends
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                ForEach(["Alex", "Sam", "Jordan", "Taylor"], id: \.self) { name in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 54, height: 54)
                            .overlay(
                                Text(String(name.prefix(1)))
                                    .font(.custom("OpenSans-SemiBold", size: 18))
                                    .foregroundColor(Color(.systemGray))
                            )
                        Text(name)
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundColor(.black)
                    }
                }
            }
            .padding(.horizontal, 16)

            Divider()

            // Actions
            HStack(alignment: .top, spacing: 0) {
                sheetAction("plus", label: "Add to story")
                sheetAction("link", label: "Copy link")
                Button(action: onShareTo) {
                    sheetAction(source == .instagram ? "square.and.arrow.up" : "ellipsis", label: source.shareToLabel)
                }
                .buttonStyle(.plain)
                .tutorialPulse()
                .accessibilityLabel(source.shareToLabel)
                .accessibilityHint("Step 2 of 4")
                sheetAction("message.fill", label: "Messages", tint: .green)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(Color.white)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .bottom) {
            TutorialHint(step: 2, text: "Tap \u{201C}\(source.shareToLabel)\u{201D} to open your phone\u{2019}s share menu", missedTaps: missedTaps)
                .padding(.bottom, 100)
                .allowsHitTesting(false)
        }
    }

    private func sheetAction(_ systemName: String, label: String, tint: Color? = nil) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 20))
                .foregroundColor(tint == nil ? .black : .white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(tint ?? Color(.systemGray6)))
            Text(label)
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundColor(.black)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Step 3: iOS Share Sheet

/// The iOS share sheet. Salt usually isn't in the app row until it's been used, so the
/// tutorial goes through More, like a first real share would.
private struct TutorialSystemShareSheet: View {
    let recipe: TutorialSampleRecipe
    let source: ShareTutorialView.Source
    let missedTaps: Int
    /// Salt is on the sheet already (onboarding); otherwise it's found under More
    var showsSalt = false
    let onMore: () -> Void
    var onSalt: () -> Void = {}

    var body: some View {
        VStack(spacing: 18) {
            // Shared item
            HStack(spacing: 12) {
                TutorialRecipePhoto(url: recipe.imageUrl)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(source == .website ? recipe.title : "Post from dinnerin10")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    Text(source.domain)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundColor(Color(.systemGray))
                }
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Color(.systemGray3))
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            Divider()

            // Apps
            HStack(alignment: .top, spacing: 0) {
                if showsSalt {
                    Button(action: onSalt) {
                        TutorialSaltAppIcon()
                    }
                    .buttonStyle(.plain)
                    .tutorialPulse(cornerRadius: 16)
                    .accessibilityLabel("Salt")
                    .accessibilityHint("Step 3 of 3")
                }
                TutorialAppIcon(label: "AirDrop", systemImage: "dot.radiowaves.left.and.right", color: .blue)
                TutorialAppIcon(label: "Messages", systemImage: "message.fill", color: .green)
                TutorialAppIcon(label: "Mail", systemImage: "envelope.fill", color: .blue)
                if showsSalt {
                    TutorialAppIcon(label: "More", systemImage: "ellipsis", color: Color(.systemGray4), iconColor: .black)
                        .accessibilityHidden(true)
                } else {
                    TutorialAppIcon(label: "Notes", systemImage: "note.text", color: .yellow)
                    Button(action: onMore) {
                        TutorialAppIcon(label: "More", systemImage: "ellipsis", color: Color(.systemGray4), iconColor: .black)
                    }
                    .buttonStyle(.plain)
                    .tutorialPulse(cornerRadius: 16)
                    .accessibilityLabel("More")
                    .accessibilityHint("Step 3 of 4")
                }
            }
            .padding(.horizontal, 8)

            // Actions list
            TutorialListGroup(rows: ["Copy", "Add to Reading List", "Save to Files"])
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(Color(.systemGray6))
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            TutorialHint(
                step: 3,
                text: showsSalt ? "Tap Salt. That\u{2019}s it, the recipe is saved" : "Tap More: new apps hide here until you find them",
                missedTaps: missedTaps
            )
                .offset(y: -56)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Step 4: iOS Apps List

/// The list iOS shows after More. New apps hide under Suggestions, so the user pins Salt
/// first (Edit → + → Done), then taps it in Favorites, the way it works for real.
private struct TutorialAppsListSheet: View {
    let missedTaps: Int
    let onSalt: () -> Void

    private enum Phase { case tapEdit, tapAdd, tapDone, tapSalt }
    @State private var phase: Phase = .tapEdit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEditing: Bool { phase == .tapAdd || phase == .tapDone }
    private var saltIsFavorite: Bool { phase == .tapDone || phase == .tapSalt }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Text("Apps")
                    .font(.custom("OpenSans-SemiBold", size: 17))
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.blue)
                        .opacity(isEditing ? 0 : 1)
                    Spacer()
                    topButton
                }
            }
            .foregroundColor(.black)
            .padding(.top, 16)
            .padding(.bottom, 6)

            sectionTitle("Favorites")
            VStack(spacing: 0) {
                if saltIsFavorite {
                    saltRow(inFavorites: true)
                    Divider().padding(.leading, 56)
                }
                appRow("AirDrop", systemImage: "dot.radiowaves.left.and.right", color: .blue)
                Divider().padding(.leading, 56)
                appRow("Messages", systemImage: "message.fill", color: .green)
                if !saltIsFavorite {
                    Divider().padding(.leading, 56)
                    appRow("Mail", systemImage: "envelope.fill", color: .blue)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))

            sectionTitle("Suggestions")
                .padding(.top, 8)
            VStack(spacing: 0) {
                if !saltIsFavorite {
                    saltRow(inFavorites: false)
                    Divider().padding(.leading, 56)
                }
                appRow("Reminders", systemImage: "checklist", color: .orange)
                Divider().padding(.leading, 56)
                appRow("Instagram", systemImage: "camera", color: Color(red: 0.84, green: 0.16, blue: 0.46))
                if saltIsFavorite {
                    Divider().padding(.leading, 56)
                    appRow("Mail", systemImage: "envelope.fill", color: .blue)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(Color(.systemGray6))
                .ignoresSafeArea(edges: .bottom)
        )
        // Above the sheet, so it never covers names or buttons
        .overlay(alignment: .top) {
            TutorialHint(step: hintStep, text: hintText, missedTaps: missedTaps)
                .id(phase)
                .transition(.opacity)
                .offset(y: -96)
                .allowsHitTesting(false)
        }
    }

    private var hintStep: Int { phase == .tapSalt ? 5 : 4 }

    private var hintText: String {
        switch phase {
        case .tapEdit: "Pin Salt so it\u{2019}s always there: tap Edit"
        case .tapAdd: "Tap + next to Salt"
        case .tapDone: "Salt is in Favorites now. Tap Done"
        case .tapSalt: "Tap Salt to save the recipe"
        }
    }

    @ViewBuilder private var topButton: some View {
        let title = isEditing ? "Done" : "Edit"
        let button = Button {
            switch phase {
            case .tapEdit: advance(to: .tapAdd)
            case .tapDone: advance(to: .tapSalt)
            default: break
            }
        } label: {
            Text(title)
                .font(.custom(isEditing ? "OpenSans-SemiBold" : "OpenSans-Regular", size: 15))
                .foregroundColor(isEditing ? .blue : .black)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)

        if phase == .tapEdit || phase == .tapDone {
            button.tutorialPulse()
        } else {
            button.allowsHitTesting(false)
        }
    }

    /// Salt in Suggestions (with a green + while editing) or pinned in Favorites
    private func saltRow(inFavorites: Bool) -> some View {
        let row = HStack(spacing: 14) {
            if isEditing && !inFavorites {
                Button { advance(to: .tapDone) } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, .green)
                }
                .buttonStyle(.plain)
                .tutorialPulse()
                .accessibilityLabel("Add Salt to Favorites")
            } else if isEditing {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, .red)
            }
            Image("saltAppIcon")
                .resizable()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text("Salt")
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundColor(.black)
            Spacer()
            if isEditing {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(Color(.systemGray3))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())

        return Group {
            if phase == .tapSalt && inFavorites {
                Button(action: onSalt) { row }
                    .buttonStyle(.plain)
                    .tutorialPulse(cornerRadius: 12)
                    .accessibilityLabel("Salt")
                    .accessibilityHint("Step 5 of 5")
            } else {
                row
            }
        }
    }

    private func advance(to next: Phase) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.4)) { phase = next }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.custom("OpenSans-Regular", size: 14))
            .foregroundColor(Color(.systemGray))
            .padding(.leading, 4)
    }

    private func appRow(_ name: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 14) {
            if isEditing {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, .red)
            }
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(color))
            Text(name)
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundColor(.black)
            Spacer()
            if isEditing {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(Color(.systemGray3))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Website: Recipe Page in Safari

/// A recipe blog post in Safari, with the iOS 26 bottom bar (Share is under •••)
private struct TutorialWebsiteView: View {
    static let domain = "dinnerin10.com"

    let recipe: TutorialSampleRecipe
    let isDimmed: Bool
    let missedTaps: Int
    let onMenu: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // No icons on the right: the Skip button sits there
            Text("Dinner in 10")
                .font(.custom("Playfair9pt-SemiBold", size: 20))
                .foregroundColor(.black)
                .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            TutorialRecipePhoto(url: recipe.imageUrl)
                .frame(height: 230)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 12) {
                Text("DINNER · QUICK MEALS")
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .tracking(1)
                    .foregroundColor(Color("Orange"))
                Text(recipe.title)
                    .font(.custom("Playfair9pt-SemiBold", size: 26))
                    .foregroundColor(.black)
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                    }
                    Text("4.8 (126 reviews)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundColor(Color("GraniteGray"))
                        .padding(.leading, 4)
                }
                .font(.system(size: 11))
                .foregroundColor(Color(red: 1.0, green: 0.76, blue: 0.03))

                Label("Jump to Recipe", systemImage: "arrow.down")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black))

                // Blog text
                VStack(alignment: .leading, spacing: 9) {
                    ForEach([1.0, 0.95, 1.0, 0.8, 1.0, 0.6], id: \.self) { width in
                        Capsule()
                            .fill(Color(.systemGray5))
                            .frame(height: 8)
                            .containerRelativeFrame(.horizontal) { length, _ in (length - 40) * width }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer(minLength: 0)

            toolbar
        }
        .background(Color.white.ignoresSafeArea())
        .overlay(Color.black.opacity(isDimmed ? 0.45 : 0).ignoresSafeArea())
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

            HStack(spacing: 6) {
                Image(systemName: "text.page")
                    .font(.system(size: 13))
                Text(Self.domain)
                    .font(.custom("OpenSans-Regular", size: 15))
                Spacer(minLength: 0)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Capsule().fill(Color.white))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

            Button(action: onMenu) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(isDimmed)
            .tutorialPulse()
            .opacity(isDimmed ? 0 : 1)
            .accessibilityLabel("More")
            .accessibilityHint("Step 1 of 4")
            // Hint above the button, ending at the screen edge
            .overlay(alignment: .bottomTrailing) {
                if !isDimmed {
                    TutorialHint(step: 1, text: "Tap \u{2022}\u{2022}\u{2022} to open the menu", missedTaps: missedTaps)
                        .fixedSize()
                        .padding(.bottom, 64)
                        .allowsHitTesting(false)
                }
            }
        }
        .foregroundColor(.black)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

/// Safari's ••• menu, opening up from the bottom bar
private struct TutorialSafariMenu: View {
    let missedTaps: Int
    let onShare: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onShare) {
                menuRow("Share", systemImage: "square.and.arrow.up")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tutorialPulse(cornerRadius: 12)
            .accessibilityLabel("Share")
            .accessibilityHint("Step 2 of 4")
            Divider()
            menuRow("Add to Bookmarks", systemImage: "book")
            Divider()
            menuRow("Add to Favorites", systemImage: "star")
            Divider()
            menuRow("Find on Page", systemImage: "doc.text.magnifyingglass")
            Divider()
            menuRow("Add to Home Screen", systemImage: "plus.square")
        }
        .frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 6)
        .overlay(alignment: .top) {
            TutorialHint(step: 2, text: "Tap Share to open your phone\u{2019}s share menu", missedTaps: missedTaps)
                .fixedSize()
                .offset(y: -56)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 16)
        .padding(.bottom, 64)
    }

    private func menuRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Text(title)
                .font(.custom("OpenSans-Regular", size: 16))
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 16))
        }
        .foregroundColor(.black)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Sheet Building Blocks

/// Salt on the share sheet's app row
private struct TutorialSaltAppIcon: View {
    var body: some View {
        VStack(spacing: 6) {
            Image("saltAppIcon")
                .resizable()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text("Salt")
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundColor(.black)
        }
        .frame(maxWidth: .infinity)
    }
}

extension EnvironmentValues {
    /// Steps in the walkthrough, for the hints' "2 of 5"
    @Entry var tutorialStepCount = 5
}

private struct TutorialAppIcon: View {
    let label: String
    let systemImage: String
    let color: Color
    var iconColor: Color = .white

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundColor(iconColor)
                .frame(width: 58, height: 58)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(label)
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundColor(.black)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TutorialListGroup: View {
    let rows: [String]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.self) { row in
                HStack {
                    Text(row)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundColor(.black)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                if row != rows.last {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
    }
}

// MARK: - Step 6: Imported

private struct TutorialImportedView: View {
    let recipe: TutorialSampleRecipe
    let context: ShareTutorialView.Context
    let primaryTitle: String
    var hasProgress = false
    let showsMaybeLater: Bool
    let showsWebsiteHint: Bool
    let onPrimary: () -> Void
    let onMaybeLater: () -> Void
    let onSeeWebsites: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SaltColor.iconAccent)
                Text("Saved to My Recipes")
                    .font(SaltFont.bodyStrong)
                    .foregroundStyle(SaltColor.textPrimary)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(SaltColor.surfaceWarmStrong, in: Capsule())
            .padding(.top, hasProgress ? 64 : 24)

            Text("Your first recipe is ready")
                .font(SaltFont.h1)
                .foregroundStyle(SaltColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text("Ingredients and steps, saved in one tap. No more screenshots.")
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            recipeSnippet
                .padding(.top, 20)

            Spacer(minLength: 16)

            VStack(spacing: 8) {
                if showsWebsiteHint {
                    HStack(spacing: 6) {
                        Text("Works the same on websites.")
                            .font(SaltFont.body)
                            .foregroundStyle(SaltColor.textSecondary)
                        Button("See how", action: onSeeWebsites)
                            .font(SaltFont.bodyStrong)
                            .foregroundStyle(SaltColor.textAccent)
                            .frame(minHeight: 44)
                    }
                    .padding(.bottom, -4)
                }
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(.salt())
                if showsMaybeLater {
                    Button("Maybe later", action: onMaybeLater)
                        .buttonStyle(.salt(.text))
                }
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, SaltSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
    }

    /// A small version of Salt's recipe screen: photo, the cream title card over it,
    /// and the first ingredients
    private var recipeSnippet: some View {
        VStack(alignment: .leading, spacing: 0) {
            TutorialRecipePhoto(url: recipe.imageUrl)
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipped()

            // Same card as the recipe screen, overlapping the photo
            RecipeInfoCard(title: recipe.detail.title, duration: recipe.detail.duration, ingredientsCount: recipe.detail.ingredientsCount)
                .scaleEffect(0.92)
                .padding(.top, -44)

            VStack(alignment: .leading, spacing: 8) {
                Text("Ingredients")
                    .font(SaltFont.h3)
                    .padding(.bottom, 2)

                ForEach(recipe.ingredients.prefix(3), id: \.self) { ingredient in
                    Text(ingredient)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .lineLimit(1)
                }
                if recipe.ingredients.count > 3 {
                    Text("+ \(recipe.ingredients.count - 3) more")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundColor(Color("GraniteGray"))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color("GrayButtonBorderColor"), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    ShareTutorialView(context: .onboarding) { _ in }
}

#Preview("App Share Sheet") {
    ShareTutorialView(context: .onboarding, startingAt: .appShareSheet) { _ in }
}

#Preview("iOS Share Sheet") {
    ShareTutorialView(context: .onboarding, startingAt: .systemShareSheet) { _ in }
}

#Preview("Apps List") {
    ShareTutorialView(context: .onboarding, startingAt: .appsList) { _ in }
}

#Preview("Website") {
    ShareTutorialView(context: .onboarding, sources: [.website]) { _ in }
}

#Preview("Safari Menu") {
    ShareTutorialView(context: .onboarding, sources: [.website], startingAt: .appShareSheet) { _ in }
}

#Preview("TikTok") {
    ShareTutorialView(context: .explore, sources: [.tiktok], startingAt: .appShareSheet) { _ in }
}

#Preview("Imported (Explore)") {
    ShareTutorialView(context: .explore, startingAt: .imported) { _ in }
}
