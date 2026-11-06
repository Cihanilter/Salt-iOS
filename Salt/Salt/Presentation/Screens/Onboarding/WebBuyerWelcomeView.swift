//
//  WebBuyerWelcomeView.swift
//  Salt
//
//  Shown once after a web funnel buyer's first login (see WebBuyerWelcome): Premium is
//  active, then the import tutorial they missed by skipping the app's onboarding.
//

import SwiftUI

struct WebBuyerWelcomeView: View {
    let firstName: String?
    let onFinish: (ShareTutorialView.Outcome) -> Void

    @State private var showingTutorial = false

    var body: some View {
        if showingTutorial {
            ShareTutorialView(context: .webWelcome, onFinish: onFinish)
        } else {
            welcome
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            OnboardingLogo()
                .padding(.top, 8)

            OnboardingTitle(
                title: firstName.map { "Welcome to Salt, \($0) 🎉" } ?? "Welcome to Salt 🎉",
                subtitle: "Your Premium is active. Now let’s save your first recipe. It only takes a tap."
            )

            ImportSourcesIllustration()
                .padding(.top, 32)

            Spacer()

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
            .padding(.bottom, 16)
        }
        .background(Color.white.ignoresSafeArea())
    }
}

#Preview {
    WebBuyerWelcomeView(firstName: "Sam") { _ in }
}
