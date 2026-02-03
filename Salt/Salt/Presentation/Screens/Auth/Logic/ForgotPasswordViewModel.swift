//
//  ForgotPasswordViewModel.swift
//  Salt
//

import Foundation
import Combine
import UIKit
import SwiftUI

@MainActor
final class ForgotPasswordViewModel: ObservableObject {
    @Published var email = GenericInputProperties.initial {
        didSet {
            handleEmail()
        }
    }

    @Published var isLoading: Bool = false
    @Published var alertMessage: String?
    @Published var showAlert: Bool = false
    @Published var showSuccessMessage: Bool = false

    private let authManager = AuthManager.shared

    init() {
        configureInputProperties()
    }

    func handleEmail() {
        if !email.inputText.isEmpty, email.errorText != nil {
            self.email.errorText = nil
        }
    }

    // MARK: - Reset Password
    func resetPassword() async {
        // Clear previous errors
        var updatedEmail = email
        updatedEmail.errorText = nil
        email = updatedEmail

        // Validate email
        guard ValidationHelper.isValidEmail(email.inputText) else {
            var updated = email
            updated.errorText = "Please enter a valid email address."
            email = updated
            return
        }

        isLoading = true

        do {
            try await authManager.resetPassword(email: email.inputText)

            // Show success message
            showSuccessMessage = true
            alertMessage = "Password reset link has been sent to your email. Please check your inbox."
            showAlert = true
        } catch let error as AuthError {
            handleAuthError(error)
        } catch {
            showAlertMessage("An unexpected error occurred. Please try again.")
        }

        isLoading = false
    }

    // MARK: - Error Handling
    private func handleAuthError(_ error: AuthError) {
        switch error {
        case .invalidEmail:
            var updated = email
            updated.errorText = error.errorDescription
            email = updated
        case .userNotFound:
            showAlertMessage(error.errorDescription ?? "User not found")
        default:
            showAlertMessage(error.errorDescription ?? "An error occurred")
        }
    }

    private func showAlertMessage(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    func configureInputProperties() {
        email = .init(
            title: "Email Address",
            placeholder: "your.email@example.com",
            isSecure: false,
            actionInfo: .init(image: nil, tapAction: {
                print("email...")
            }),
            keyboardType: .emailAddress,
            errorText: nil,
            submitLabel: .done,
            onSubmit: nil,
            inputText: ""
        )
    }
}
