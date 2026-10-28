//
//  AuthCoordinatorView.swift
//  Salt
//

import SwiftUI

struct AuthCoordinatorView: View {
    @StateObject private var router = AuthRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            WelcomeView(router: router)
                .navigationBarHidden(true)
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .onboarding:
                        OnboardingFlowView(router: router)
                            .navigationBarHidden(true)
                    case .login:
                        LoginView(viewModel: LoginViewModel(), router: router)
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
    }

    /// Back to the Welcome screen (Login and Sign up have no back button of their own)
    private var backButton: some View {
        Button {
            router.navigateToRoot()
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
