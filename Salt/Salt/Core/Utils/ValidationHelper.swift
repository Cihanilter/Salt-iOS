//
//  ValidationHelper.swift
//  Salt
//

import Foundation

struct ValidationHelper {
    // Email validation
    static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    // Password validation: minimum 10 characters, must contain numbers and special characters
    static func isValidPassword(_ password: String) -> Bool {
        // Check minimum length
        guard password.count >= 10 else { return false }

        // Check for at least one number
        let numberRegex = ".*[0-9]+.*"
        let hasNumber = NSPredicate(format: "SELF MATCHES %@", numberRegex).evaluate(with: password)

        // Check for at least one special character
        let specialCharacterRegex = ".*[!@#$%^&*(),.?\":{}|<>]+.*"
        let hasSpecialCharacter = NSPredicate(format: "SELF MATCHES %@", specialCharacterRegex).evaluate(with: password)

        return hasNumber && hasSpecialCharacter
    }

    // Validate full name (not empty, at least 2 characters)
    static func isValidFullName(_ name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.count >= 2
    }
}
