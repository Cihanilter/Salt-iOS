//
//  SignUpViewModel.swift
//  Salt
//

import Foundation
import Combine
import UIKit
import SwiftUI

@MainActor
final class SignUpViewModel: ObservableObject {
    @Published var fullName = GenericInputProperties.initial {
        didSet {
            handleFullName()
        }
    }

    @Published var email = GenericInputProperties.initial {
        didSet {
            handleEmail()
        }
    }

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

    @Published var agreeToTerms: Bool = false
    @Published var isLoading: Bool = false
    @Published var alertMessage: String?
    @Published var showAlert: Bool = false
    @Published var showSuccessMessage: Bool = false

    private let authManager = AuthManager.shared

    var isFormValid: Bool {
        return ValidationHelper.isValidFullName(fullName.inputText) &&
               ValidationHelper.isValidEmail(email.inputText) &&
               ValidationHelper.isValidPassword(password.inputText) &&
               password.inputText == confirmPassword.inputText &&
               !password.inputText.isEmpty &&
               !confirmPassword.inputText.isEmpty &&
               agreeToTerms
    }

    init() {
        configureInputProperties()
    }

    func handleFullName() {
        // Only clear error if field is now valid
        if fullName.errorText != nil && ValidationHelper.isValidFullName(fullName.inputText) {
            var updated = fullName
            updated.errorText = nil
            self.fullName = updated
        }
    }

    func handleEmail() {
        // Only clear error if field is now valid
        if email.errorText != nil && ValidationHelper.isValidEmail(email.inputText) {
            var updated = email
            updated.errorText = nil
            self.email = updated
        }
    }

    func handlePassword() {
        // Only clear error if field is now valid
        if password.errorText != nil && ValidationHelper.isValidPassword(password.inputText) {
            var updated = password
            updated.errorText = nil
            self.password = updated
        }
    }

    func handleConfirmPassword() {
        // Only clear error if passwords match
        if confirmPassword.errorText != nil && password.inputText == confirmPassword.inputText {
            var updated = confirmPassword
            updated.errorText = nil
            self.confirmPassword = updated
        }
    }

    // MARK: - Sign Up
    func signUp() async {
        print("SignUpViewModel: signUp() called")

        // Clear previous errors
        var updatedFullName = fullName
        updatedFullName.errorText = nil
        fullName = updatedFullName

        var updatedEmail = email
        updatedEmail.errorText = nil
        email = updatedEmail

        var updatedPassword = password
        updatedPassword.errorText = nil
        password = updatedPassword

        var updatedConfirmPassword = confirmPassword
        updatedConfirmPassword.errorText = nil
        confirmPassword = updatedConfirmPassword

        // Validate full name
        guard ValidationHelper.isValidFullName(fullName.inputText) else {
            print("SignUpViewModel: Invalid full name")
            var updated = fullName
            updated.errorText = "Please enter your full name (at least 2 characters)."
            fullName = updated
            return
        }

        // Validate email
        guard ValidationHelper.isValidEmail(email.inputText) else {
            print("SignUpViewModel: Invalid email")
            var updated = email
            updated.errorText = "Please enter a valid email address."
            email = updated
            return
        }

        // Validate password
        guard ValidationHelper.isValidPassword(password.inputText) else {
            print("SignUpViewModel: Invalid password")
            var updated = password
            updated.errorText = "Password must be at least 10 characters with numbers and special characters."
            password = updated
            return
        }

        // Validate confirm password
        guard password.inputText == confirmPassword.inputText else {
            print("SignUpViewModel: Passwords do not match")
            var updated = confirmPassword
            updated.errorText = "Passwords do not match."
            confirmPassword = updated
            return
        }

        // Check terms agreement
        guard agreeToTerms else {
            print("SignUpViewModel: Terms not agreed")
            showAlertMessage("Please agree to the Terms and Conditions and Privacy Policy.")
            return
        }

        print("SignUpViewModel: All validation passed, starting sign up...")
        isLoading = true

        do {
            print("SignUpViewModel: Calling authManager.signUp...")
            try await authManager.signUp(
                email: email.inputText,
                password: password.inputText,
                fullName: fullName.inputText
            )

            print("SignUpViewModel: Sign up successful!")
            // Show success message
            showSuccessMessage = true
            alertMessage = "Account created successfully! Please check your email to verify your account."
            showAlert = true
        } catch let error as AuthError {
            print("SignUpViewModel: AuthError - \(error)")
            handleAuthError(error)
        } catch {
            print("SignUpViewModel: Unknown error - \(error)")
            showAlertMessage("An unexpected error occurred. Please try again.")
        }

        isLoading = false
    }

    // MARK: - Sign Up with Google
    func signUpWithGoogle() async {
        isLoading = true

        do {
            try await authManager.signInWithGoogle()
        } catch let error as AuthError {
            handleAuthError(error)
        } catch {
            showAlertMessage("Failed to sign up with Google. Please try again.")
        }

        isLoading = false
    }

    // MARK: - Sign Up with Apple
    func signUpWithApple() async {
        isLoading = true

        do {
            let helper = AppleSignInHelper()
            let credential = try await helper.signIn()
            try await authManager.signInWithApple(credential: credential)
        } catch let error as AuthError {
            handleAuthError(error)
        } catch {
            showAlertMessage("Failed to sign up with Apple. Please try again.")
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
        case .weakPassword:
            var updated = password
            updated.errorText = error.errorDescription
            password = updated
        case .emailAlreadyInUse:
            showAlertMessage(error.errorDescription ?? "Email already in use")
        default:
            showAlertMessage(error.errorDescription ?? "An error occurred")
        }
    }

    private func showAlertMessage(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    func configureInputProperties() {
        fullName = .init(
            title: "Full Name",
            placeholder: "John Doe",
            isSecure: false,
            actionInfo: .init(image: nil, tapAction: {
                print("full name...")
            }),
            keyboardType: .default,
            errorText: nil,
            submitLabel: .next,
            onSubmit: nil,
            inputText: ""
        )

        email = .init(
            title: "Email",
            placeholder: "your.email@example.com",
            isSecure: false,
            actionInfo: .init(image: nil, tapAction: {
                print("email...")
            }),
            keyboardType: .emailAddress,
            errorText: nil,
            submitLabel: .next,
            onSubmit: nil,
            inputText: ""
        )

        password = .init(
            title: "Password",
            placeholder: "Create a password",
            isSecure: true,
            actionInfo: .init(image: .init(named: "eye")!, tapAction: { [weak self] in
                print("password...")
                self?.password.isSecure.toggle()
            }),
            keyboardType: .default,
            errorText: nil,
            submitLabel: .next,
            onSubmit: nil,
            inputText: ""
        )

        confirmPassword = .init(
            title: "Confirm Password",
            placeholder: "Confirm your password",
            isSecure: true,
            actionInfo: .init(image: .init(named: "eye")!, tapAction: { [weak self] in
                print("confirm password...")
                self?.confirmPassword.isSecure.toggle()
            }),
            keyboardType: .default,
            errorText: nil,
            submitLabel: .done,
            onSubmit: nil,
            inputText: ""
        )
    }
}
