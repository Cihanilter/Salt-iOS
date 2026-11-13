//
//  WebBuyerWelcomeView.swift
//  Salt
//
//  Shown once after a web funnel buyer's first login (see WebBuyerWelcome): Premium is
//  active (checked with RevenueCat, since a web purchase can take a moment to arrive) and
//  what it includes, then the import tutorial they missed by skipping the app's onboarding.
//

import SwiftUI

struct WebBuyerWelcomeView: View {
    let firstName: String?
    let onFinish: (ShareTutorialView.Outcome) -> Void

    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingTutorial = false
    @State private var premium = PremiumState.checking

    private enum PremiumState {
        case checking
        case active
        /// RevenueCat hasn't confirmed the web purchase yet
        case activating
    }

    /// What Premium unlocks in the app (import limit, nutrition, swaps and Cooking mode gates)
    private let premiumFeatures: [(icon: String, text: LocalizedStringKey)] = [
        ("infinity", "Unlimited recipe imports"),
        ("chart.pie", "Nutrition for every recipe"),
        ("arrow.triangle.2.circlepath", "Ingredient swaps"),
        ("sun.max", "Cooking mode keeps your screen on")
    ]

    var body: some View {
        if showingTutorial {
            ShareTutorialView(context: .webWelcome, onFinish: onFinish)
        } else {
            welcome
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(spacing: 0) {
                OnboardingLogo()
                    .padding(.top, 8)

                OnboardingTitle(
                    title: firstName.map { "Welcome to Salt, \($0) 🎉" } ?? "Welcome to Salt 🎉",
                    subtitle: subtitle
                )

                premiumStatus
                    .padding(.top, 16)

                ImportSourcesIllustration()
                    .padding(.top, 24)

                featureList
                    .padding(.top, 24)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 14) {
                OnboardingPrimaryButton(title: "Show me how") {
                    showingTutorial = true
                }
                Button("Skip for now") {
                    Analytics.log(.webWelcomeSkipped)
                    onFinish(.skipped)
                }
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundColor(Color("GrayText"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(Color.white)
        }
        .background(Color.white.ignoresSafeArea())
        .task { await checkPremium() }
        // The purchase can also arrive on its own through RevenueCat's customer info updates
        .onChange(of: subscriptionManager.isPremium) { _, isPremium in
            if isPremium { premium = .active }
        }
    }

    private var subtitle: String {
        switch premium {
        case .checking, .active:
            String(localized: "Now let’s save your first recipe. It only takes a tap.")
        case .activating:
            String(localized: "We’re still activating your Premium. It usually takes a minute.")
        }
    }

    @ViewBuilder
    private var premiumStatus: some View {
        switch premium {
        case .checking:
            ProgressView()
                .frame(height: 24)
        case .active:
            HStack(spacing: 6) {
                SaltPremiumBadge()
                Text("is active")
                    .font(SaltFont.bodyStrong)
                    .foregroundStyle(SaltColor.textPrimary)
            }
            .accessibilityElement(children: .combine)
        case .activating:
            Button("Check again") {
                Task { await checkPremium() }
            }
            .font(SaltFont.bodyStrong)
            .foregroundStyle(SaltColor.textAccent)
            .frame(minHeight: 44)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Premium includes")
                .font(SaltFont.bodyLargeStrong)
                .foregroundStyle(SaltColor.textPrimary)
            ForEach(premiumFeatures, id: \.icon) { feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SaltColor.iconAccent)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(feature.text)
                        .font(SaltFont.body)
                        .foregroundStyle(SaltColor.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checkPremium() async {
        premium = .checking
        if await subscriptionManager.recheckPremium() {
            premium = .active
        } else {
            premium = .activating
            Analytics.log(.webWelcomePremiumPending)
        }
    }
}

#Preview {
    WebBuyerWelcomeView(firstName: "Sam") { _ in }
}
