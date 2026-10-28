//
//  ShareTutorialView.swift
//  Salt
//
//  Interactive walkthrough of importing a recipe from social media: the user taps
//  Share > Share to... > Salt on a mock post and sees the recipe land in Salt.
//  Used at the end of onboarding and from the Explore banner.
//

import SwiftUI

struct ShareTutorialView: View {
    /// Where the tutorial was opened from; changes the final call to action
    enum Context: String {
        case onboarding
        case explore
    }

    /// How the tutorial ended
    enum Outcome {
        /// Finished the walkthrough and tapped the main button
        case completed
        /// Finished and chose to paste a link instead (Explore only)
        case pasteLink
        case skipped
    }

    let context: Context
    let onFinish: (Outcome) -> Void

    @State private var step: Step
    /// Bumped when the user taps outside the highlighted target, to bounce the hint
    @State private var missedTaps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private let recipe = TutorialSampleRecipe.current

    /// `step` is only for previews; the tutorial always starts on the post
    init(context: Context, startingAt step: Step = .post, onFinish: @escaping (Outcome) -> Void) {
        self.context = context
        self.onFinish = onFinish
        _step = State(initialValue: step)
    }

    enum Step: Int {
        case post
        case appShareSheet
        case systemShareSheet
        case importing
        case imported

        /// Name sent with the skipped event, to see where people drop off
        var analyticsName: String {
            switch self {
            case .post: "post"
            case .appShareSheet: "app_share_sheet"
            case .systemShareSheet: "system_share_sheet"
            case .importing: "importing"
            case .imported: "imported"
            }
        }
    }

    var body: some View {
        ZStack {
            switch step {
            case .post, .appShareSheet, .systemShareSheet:
                socialAppScreen
                    .transition(.opacity)
            case .importing:
                TutorialImportingView()
                    .transition(.opacity)
            case .imported:
                TutorialImportedView(recipe: recipe, context: context, onPrimary: finishPrimary, onPasteLink: {
                    finish(.pasteLink)
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            if step != .imported {
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
        .sensoryFeedback(.impact(weight: .light), trigger: step)
        .sensoryFeedback(.warning, trigger: missedTaps)
        .onAppear {
            Analytics.log(.importTutorialStarted, ["context": context.rawValue])
        }
        .task(id: step) {
            // Shows the import running for a moment, like the real share extension.
            // Cancelled if the tutorial is skipped or closed meanwhile.
            guard step == .importing else { return }
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            advance(to: .imported)
            Analytics.log(.importTutorialCompleted, ["context": context.rawValue])
        }
    }

    // MARK: - Mock Social App

    /// A recipe post in a social app, with the app's and the iOS share sheets on top
    private var socialAppScreen: some View {
        ZStack(alignment: .bottom) {
            TutorialPostView(recipe: recipe, isDimmed: step != .post, missedTaps: missedTaps, onShare: { advance(to: .appShareSheet) })
                .contentShape(Rectangle())
                .onTapGesture { missedTap() }

            if step == .appShareSheet {
                TutorialAppShareSheet(missedTaps: missedTaps, onShareTo: { advance(to: .systemShareSheet) })
                    .transition(.move(edge: .bottom))
            }

            if step == .systemShareSheet {
                TutorialSystemShareSheet(recipe: recipe, missedTaps: missedTaps, onSalt: { advance(to: .importing) })
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

    private func finishPrimary() {
        if context == .explore {
            // The real thing: open Instagram to share a recipe; without Instagram, paste a link
            openURL(URL(string: "instagram://app")!) { opened in
                finish(opened ? .completed : .pasteLink)
            }
        } else {
            finish(.completed)
        }
    }

    private func finish(_ outcome: Outcome) {
        if outcome == .skipped {
            Analytics.log(.importTutorialSkipped, ["context": context.rawValue, "step": step.analyticsName])
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

    /// No-Cook Chicken and Avocado Bowls: short, photogenic, few ingredients
    private static let preferredId = UUID(uuidString: "03923292-775d-4833-b071-59483cb0122f")

    @MainActor
    static var current: TutorialSampleRecipe {
        let recipes = CuratedRecipesManager.shared.recipes
        guard let recipe = recipes.first(where: { $0.id == preferredId }) ?? recipes.first else {
            return TutorialSampleRecipe(
                title: "Chicken and Avocado Bowls",
                imageUrl: nil,
                ingredients: ["Chicken", "Avocados", "Cilantro", "Chili powder", "Lime juice"],
                totalTimeMinutes: 10,
                servings: 3
            )
        }
        return TutorialSampleRecipe(
            title: recipe.title,
            imageUrl: recipe.imageUrl.flatMap(URL.init(string:)),
            ingredients: recipe.ingredients,
            totalTimeMinutes: recipe.totalTimeMinutes,
            servings: recipe.servings
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

/// "TAP SHARE"-style label pointing at the element to tap
private struct TutorialHint: View {
    let text: String
    let missedTaps: Int

    var body: some View {
        Text(text)
            .font(.custom("OpenSans-SemiBold", size: 18))
            .tracking(0.5)
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color("Orange")))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            // Bounces when the user taps somewhere else
            .keyframeAnimator(initialValue: 1.0, trigger: missedTaps) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.15, duration: 0.15)
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
            .overlay(alignment: .bottomLeading) { caption }
            .overlay(alignment: .bottomTrailing) { sideActions }
            .overlay(Color.black.opacity(isDimmed ? 0.45 : 0).ignoresSafeArea())
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
            Text("\(recipe.title) 🥑 Recipe in caption!")
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
                postAction("paperplane", label: "Share")
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
                    TutorialHint(text: "TAP SHARE", missedTaps: missedTaps)
                        .fixedSize()
                        .padding(.trailing, 68)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Share")
            .accessibilityHint("Step 1 of 3")
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
                    sheetAction("square.and.arrow.up", label: "Share to...")
                }
                .buttonStyle(.plain)
                .tutorialPulse()
                .accessibilityLabel("Share to")
                .accessibilityHint("Step 2 of 3")
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
            TutorialHint(text: "TAP SHARE TO...", missedTaps: missedTaps)
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

private struct TutorialSystemShareSheet: View {
    let recipe: TutorialSampleRecipe
    let missedTaps: Int
    let onSalt: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            // Shared item
            HStack(spacing: 12) {
                TutorialRecipePhoto(url: recipe.imageUrl)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Post from dinnerin10")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundColor(.black)
                    Text("instagram.com")
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
                appIcon(label: "AirDrop") {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 58, height: 58)
                        .background(Color.blue)
                }
                appIcon(label: "Messages") {
                    Image(systemName: "message.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 58, height: 58)
                        .background(Color.green)
                }
                Button(action: onSalt) {
                    appIcon(label: "Salt") {
                        Image("saltAppIcon")
                            .resizable()
                            .frame(width: 58, height: 58)
                    }
                }
                .buttonStyle(.plain)
                .tutorialPulse(cornerRadius: 16)
                .accessibilityLabel("Salt")
                .accessibilityHint("Step 3 of 3")
                appIcon(label: "Mail") {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 58, height: 58)
                        .background(Color.blue)
                }
            }
            .padding(.horizontal, 12)

            // Actions list
            VStack(spacing: 0) {
                ForEach(["Copy", "Add to Reading List", "Save to Files"], id: \.self) { action in
                    HStack {
                        Text(action)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundColor(.black)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    if action != "Save to Files" {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(Color(.systemGray6))
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            TutorialHint(text: "TAP SALT", missedTaps: missedTaps)
                .offset(y: -56)
                .allowsHitTesting(false)
        }
    }

    private func appIcon<Icon: View>(label: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 6) {
            icon()
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(label)
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundColor(.black)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Step 4: Importing

private struct TutorialImportingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image("saltAppIcon")
                .resizable()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            ProgressView()
                .tint(Color("Orange"))
            Text("Importing your recipe...")
                .font(.custom("Playfair9pt-Regular", size: 22))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("PeachCream").ignoresSafeArea())
    }
}

// MARK: - Step 5: Imported

private struct TutorialImportedView: View {
    let recipe: TutorialSampleRecipe
    let context: ShareTutorialView.Context
    let onPrimary: () -> Void
    let onPasteLink: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Recipe imported\nsuccessfully! 🎉")
                    .font(.custom("Playfair9pt-SemiBold", size: 28))
                    .multilineTextAlignment(.center)
                Text("Ingredients and steps, saved in one tap.\nNo more screenshots.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("GraniteGray"))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)

            recipeCard
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Spacer(minLength: 16)

            VStack(spacing: 12) {
                Button(action: onPrimary) {
                    Text(context == .explore ? "Try it on Instagram" : "Create my account")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color("Orange")))
                }
                if context == .explore {
                    Button("Paste a link instead", action: onPasteLink)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundColor(Color("OrangeRed"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("PeachCream").opacity(0.5).ignoresSafeArea())
    }

    private var recipeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TutorialRecipePhoto(url: recipe.imageUrl)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 10) {
                Text(recipe.title)
                    .font(.custom("Playfair9pt-SemiBold", size: 20))

                HStack(spacing: 14) {
                    if let minutes = recipe.totalTimeMinutes {
                        Label("\(minutes) min", systemImage: "clock")
                    }
                    if let servings = recipe.servings {
                        Label("\(servings) servings", systemImage: "person.2")
                    }
                }
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundColor(Color("GraniteGray"))

                Text("INGREDIENTS")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundColor(Color("Orange"))
                    .padding(.top, 4)

                ForEach(recipe.ingredients.prefix(4), id: \.self) { ingredient in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color("Orange"))
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(ingredient)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .lineLimit(1)
                    }
                }
                if recipe.ingredients.count > 4 {
                    Text("+ \(recipe.ingredients.count - 4) more")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundColor(Color("GraniteGray"))
                }
            }
            .padding(16)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
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

#Preview("Imported (Explore)") {
    ShareTutorialView(context: .explore, startingAt: .imported) { _ in }
}
