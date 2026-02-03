//
//  AuthRouter.swift
//  Salt
//

import Foundation
import SwiftUI
import Combine

enum AuthRoute: Hashable {
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
}
