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
            return "Please enter a valid email address."
        case .weakPassword:
            return "Password must be at least 10 characters with numbers and special characters."
        case .passwordsDoNotMatch:
            return "Passwords do not match."
        case .emailAlreadyInUse:
            return "This email is already registered."
        case .invalidCredentials:
            return "Invalid email or password."
        case .userNotFound:
            return "No account found with this email."
        case .emailNotVerified:
            return "Please verify your email address first."
        case .networkError:
            return "Network error. Please check your connection."
        case .unknown(let message):
            return message
        }
    }
}
