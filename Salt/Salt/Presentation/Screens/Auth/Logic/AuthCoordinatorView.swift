//
//  AuthCoordinatorView.swift
//  Salt
//

import SwiftUI

struct AuthCoordinatorView: View {
    @StateObject private var router = AuthRouter()
    @ObservedObject private var webBuyerLink = WebBuyerLinkRouter.shared

    var body: some View {
        NavigationStack(path: $router.path) {
            WelcomeView(router: router)
                .navigationBarHidden(true)
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .onboarding:
                        OnboardingFlowView(router: router)
                            .navigationBarHidden(true)
                    case .createAccount:
                        OnboardingAccountView(router: router)
                            .navigationBarHidden(true)
                    case .login:
                        LoginView(viewModel: LoginViewModel(email: router.loginEmail), router: router)
                            .navigationBarHidden(true)
                            .overlay(alignment: .topLeading) { backButton }
                    case .signUp:
                        SignUpView(viewModel: SignUpViewModel(), router: router)
                            .navigationBarHidden(true)
                            .overlay(alignment: .topLeading) { backButton }
                    case .forgotPassword:
                        ForgotPasswordView(viewModel: ForgotPasswordViewModel(), router: router)
                            .navigationBarHidden(true)
                    }
                }
        }
        // Opened from the web funnel's Download Salt link: their account exists, so Log in.
        // Only from Welcome; someone already on another screen isn't moved
        .onChange(of: webBuyerLink.opensLogin, initial: true) { _, opensLogin in
            guard opensLogin else { return }
            webBuyerLink.clear()
            if router.path.isEmpty {
                router.replace(with: .login)
            }
        }
    }

    /// Back one screen: to Welcome, or to Create account from the email form
    /// (Login and Sign up have no back button of their own)
    private var backButton: some View {
        Button {
            router.navigateBack()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 44, height: 44)
        }
        .padding(.leading, 6)
        .accessibilityLabel("Back")
    }
}

#Preview {
    AuthCoordinatorView()
}
