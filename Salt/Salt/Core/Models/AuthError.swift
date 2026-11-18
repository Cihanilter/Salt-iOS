//
//  AuthError.swift
//  Salt
//

import Foundation

enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case passwordsDoNotMatch
    case emailAlreadyInUse
    case invalidCredentials
    case userNotFound
    case emailNotVerified
    case networkError
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return String(localized: "Please enter a valid email address.")
        case .weakPassword:
            return String(localized: "Password must be at least 10 characters with numbers and special characters.")
        case .passwordsDoNotMatch:
            return String(localized: "Passwords do not match.")
        case .emailAlreadyInUse:
            return String(localized: "This email is already registered.")
        case .invalidCredentials:
            return String(localized: "Invalid email or password.")
        case .userNotFound:
            return String(localized: "No account found with this email.")
        case .emailNotVerified:
            return String(localized: "Please verify your email address first.")
        case .networkError:
            return String(localized: "Network error. Please check your connection.")
        case .unknown(let message):
            return message
        }
    }
}
