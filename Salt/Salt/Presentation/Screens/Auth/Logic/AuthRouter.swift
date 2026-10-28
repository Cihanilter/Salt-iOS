//
//  AuthRouter.swift
//  Salt
//

import Foundation
import SwiftUI
import Combine

enum AuthRoute: Hashable {
    case onboarding
    case login
    case signUp
    case forgotPassword
}

final class AuthRouter: ObservableObject {
    @Published var path = NavigationPath()

    func navigate(to route: AuthRoute) {
        path.append(route)
    }

    func navigateBack() {
        path.removeLast()
    }

    func navigateToRoot() {
        path.removeLast(path.count)
    }

    /// Shows `route` directly above the Welcome screen, so going back always returns there
    /// (switching between Log in and Sign up doesn't stack screens)
    func replace(with route: AuthRoute) {
        path = NavigationPath([route])
    }
}
