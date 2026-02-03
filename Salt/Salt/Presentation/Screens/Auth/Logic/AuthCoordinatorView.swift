//
//  AuthCoordinatorView.swift
//  Salt
//

import SwiftUI

struct AuthCoordinatorView: View {
    @StateObject private var router = AuthRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            LoginView(viewModel: LoginViewModel(), router: router)
                .navigationBarHidden(true)
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .login:
                        LoginView(viewModel: LoginViewModel(), router: router)
                            .navigationBarHidden(true)
                    case .signUp:
                        SignUpView(viewModel: SignUpViewModel(), router: router)
                            .navigationBarHidden(true)
                    case .forgotPassword:
                        ForgotPasswordView(viewModel: ForgotPasswordViewModel(), router: router)
                            .navigationBarHidden(true)
                    }
                }
        }
    }
}

#Preview {
    AuthCoordinatorView()
}
