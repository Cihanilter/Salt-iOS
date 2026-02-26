//
//  SetNewPasswordViewModel.swift
//  Salt
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class SetNewPasswordViewModel: ObservableObject {
    @Published var password = GenericInputProperties.initial {
        didSet {
            handlePassword()
        }
    }

    @Published var confirmPassword = GenericInputProperties.initial {
        didSet {
            handleConfirmPassword()
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

    func handlePassword() {
        // Only clear error if field is now valid
        if password.errorText != nil && ValidationHelper.isValidPassword(password.inputText) {
            var updated = password
            updated.errorText = nil
            password = updated
        }
    }

    func handleConfirmPassword() {
        // Only clear error if passwords now match
        if confirmPassword.errorText != nil && password.inputText == confirmPassword.inputText {
            var updated = confirmPassword
            updated.errorText = nil
            confirmPassword = updated
        }
    }

    // MARK: - Update Password
    func updatePassword() async {
        print("SetNewPasswordViewModel: updatePassword called")
        print("SetNewPasswordViewModel: password = '\(password.inputText)'")
        print("SetNewPasswordViewModel: confirmPassword = '\(confirmPassword.inputText)'")

        // Clear previous errors
        var updatedPassword = password
        updatedPassword.errorText = nil
        password = updatedPassword

        var updatedConfirmPassword = confirmPassword
        updatedConfirmPassword.errorText = nil
        confirmPassword = updatedConfirmPassword

        // Validate password
        guard ValidationHelper.isValidPassword(password.inputText) else {
            print("SetNewPasswordViewModel: Password validation failed")
            var updated = password
            updated.errorText = "Password must be at least 10 characters with numbers and special characters."
            password = updated
            print("SetNewPasswordViewModel: errorText set to: \(password.errorText ?? "nil")")
            return
        }

        // Validate passwords match
        guard password.inputText == confirmPassword.inputText else {
            print("SetNewPasswordViewModel: Passwords don't match")
            var updated = confirmPassword
            updated.errorText = "Passwords do not match."
            confirmPassword = updated
            return
        }

        print("SetNewPasswordViewModel: Validation passed, updating password...")
        isLoading = true

        do {
            try await authManager.updatePassword(newPassword: password.inputText)
            print("SetNewPasswordViewModel: Password updated successfully")

            // Show success message
            showSuccessMessage = true
            alertMessage = "Your password has been updated successfully. Please sign in with your new password."
            showAlert = true
        } catch let error as AuthError {
            print("SetNewPasswordViewModel: AuthError - \(error)")
            handleAuthError(error)
        } catch {
            print("SetNewPasswordViewModel: Unknown error - \(error)")
            showAlertMessage("An unexpected error occurred. Please try again.")
        }

        isLoading = false
    }

    // MARK: - Error Handling
    private func handleAuthError(_ error: AuthError) {
        switch error {
        case .weakPassword:
            var updated = password
            updated.errorText = error.errorDescription
            password = updated
        default:
            showAlertMessage(error.errorDescription ?? "An error occurred")
        }
    }

    private func showAlertMessage(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    func configureInputProperties() {
        password = .init(
            title: "New Password",
            placeholder: "Enter new password",
            isSecure: true,
            actionInfo: nil,
            keyboardType: .default,
            errorText: nil,
            submitLabel: .next,
            onSubmit: nil,
            inputText: ""
        )

        confirmPassword = .init(
            title: "Confirm Password",
            placeholder: "Confirm new password",
            isSecure: true,
            actionInfo: nil,
            keyboardType: .default,
            errorText: nil,
            submitLabel: .done,
            onSubmit: nil,
            inputText: ""
        )
    }
}
