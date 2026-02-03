//
//  LoginViewModel.swift
//  Salt
//

import Foundation
import Combine
import UIKit
import SwiftUI

@MainActor
final class LoginViewModel: ObservableObject {
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

    @Published var isLoading: Bool = false
    @Published var alertMessage: String?
    @Published var showAlert: Bool = false

    private let authManager = AuthManager.shared

    init() {
        configureInputProperties()
    }

    func handleEmail() {
        if !email.inputText.isEmpty, email.errorText != nil {
            self.email.errorText = nil
        }
    }

    func handlePassword() {
        if !password.inputText.isEmpty, password.errorText != nil {
            self.password.errorText = nil
        }
    }

    // MARK: - Sign In
    func signIn() async {
        // Clear previous errors
        var updatedEmail = email
        updatedEmail.errorText = nil
        email = updatedEmail

        var updatedPassword = password
        updatedPassword.errorText = nil
        password = updatedPassword

        // Validate email
        guard ValidationHelper.isValidEmail(email.inputText) else {
            var updated = email
            updated.errorText = "Please enter a valid email address."
            email = updated
            return
        }

        // Check password not empty
        guard !password.inputText.isEmpty else {
            var updated = password
            updated.errorText = "Please enter your password."
            password = updated
            return
        }

        isLoading = true

        do {
            try await authManager.signIn(email: email.inputText, password: password.inputText)
            // Navigation will be handled by AuthManager state change
        } catch let error as AuthError {
            handleAuthError(error)
        } catch {
            showAlertMessage("An unexpected error occurred. Please try again.")
        }

        isLoading = false
    }

    // MARK: - Sign In with Google
    func signInWithGoogle() async {
        isLoading = true

        do {
            try await authManager.signInWithGoogle()
        } catch let error as AuthError {
            handleAuthError(error)
        } catch {
            showAlertMessage("Failed to sign in with Google. Please try again.")
        }

        isLoading = false
    }

    // MARK: - Sign In with Apple
    func signInWithApple() async {
        isLoading = true

        do {
            let helper = AppleSignInHelper()
            let credential = try await helper.signIn()
            try await authManager.signInWithApple(credential: credential)
        } catch let error as AuthError {
            handleAuthError(error)
        } catch {
            showAlertMessage("Failed to sign in with Apple. Please try again.")
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
        case .invalidCredentials, .userNotFound:
            showAlertMessage(error.errorDescription ?? "Invalid credentials")
        case .emailNotVerified:
            showAlertMessage(error.errorDescription ?? "Please verify your email")
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
            title: "Email",
            placeholder: "your.email@example.com",
            isSecure: false,
            actionInfo: .init(image: nil, tapAction: {
                print("email...")
            }),
            keyboardType: .emailAddress,
            errorText: nil,
            submitLabel: .next,
            onSubmit: nil, // Will be set in the view
            inputText: ""
        )

        password = .init(
            title: "Password",
            placeholder: "Enter your password",
            isSecure: true,
            actionInfo: .init(image: .init(named: "eye")!, tapAction: { [weak self] in
                print("password...")
                self?.password.isSecure.toggle()
            }),
            keyboardType: .default,
            errorText: nil,
            submitLabel: .go,
            onSubmit: nil, // Will be set in the view
            inputText: ""
        )
//        lastName = .init(title: "Last Name", unitsTitle: nil, actionInfo: .init(image: nil, tapAction: dismissPickers), keyboardType: .alphabet, errorText: nil, inputText: patientData.lastName)
//        gender = .init(title: "Gender", unitsTitle: nil, actionInfo: .init(image: UIImage(named: "downArrow_icon")!, tapAction: { [ weak self] in
//            self?.showEthnicities = false
//            self?.showCalendar = false
//
//            UIApplication.shared.endEditing()
//            
//            self?.showGenders.toggle()
//        }), keyboardType: nil, errorText: nil, inputText: patientData.gender, isPicker: true)
//        ethnicity = .init(title: "Ethnicity", unitsTitle: nil, actionInfo: .init(image: UIImage(named: "downArrow_icon")!, tapAction: { [weak self] in
//            self?.showGenders = false
//            self?.showCalendar = false
//
//            UIApplication.shared.endEditing()
//            
//            self?.showEthnicities.toggle()
//        }), keyboardType: nil, errorText: nil, inputText: patientData.ethnicity ?? "", isPicker: true)
//        if MeasurementsService.isMetricSystem {
//            height = .init(title: "Height", unitsTitle: MeasurementsService.heightUnitsTitle, actionInfo: .init(image: nil, tapAction: dismissPickers), keyboardType: .numberPad, errorText: nil, inputText: "\(MeasurementsService.heightValueFromMetricInt(patientData.height))")
//        } else {
//            let cmValue = patientData.height
//            let (feet, inches) = MeasurementsService.convertCentimetersToFeetAndInches(Double(cmValue))
//            let subTitle = "\(feet)′\(inches)″"
//            height = .init(title: "Height", unitsTitle: MeasurementsService.heightUnitsTitle, actionInfo: .init(image: nil, tapAction: dismissPickers), keyboardType: .numberPad, errorText: nil, inputText: subTitle)
//        }
//        weight = .init(title: "Weight", unitsTitle: MeasurementsService.weightUnitsTitle, actionInfo: .init(image: nil, tapAction: dismissPickers), keyboardType: .numberPad, errorText: nil, inputText: "\(MeasurementsService.weightValueFromMetricInt(patientData.weight))")
//        dateOfBirth = .init(title: "Date of Birth", unitsTitle: nil, actionInfo: .init(image: UIImage(named: "calendar_icon")!, tapAction: { [weak self] in
//            self?.showGenders = false
//            self?.showEthnicities = false
//
//            UIApplication.shared.endEditing()
//            
//            self?.showCalendar.toggle()
//        }), keyboardType: nil, errorText: nil, inputText:patientData.birthDateFormated ?? "", isPicker: true)
//        selectedDate = patientData.birthDate ?? .now
//        email = .init(title: "Email", unitsTitle: nil, actionInfo: .init(image: nil, tapAction: dismissPickers), keyboardType: .emailAddress, errorText: nil, inputText:patientData.email)
    }
}
