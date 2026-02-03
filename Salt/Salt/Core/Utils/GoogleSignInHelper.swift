//
//  GoogleSignInHelper.swift
//  Salt
//

import Foundation
import GoogleSignIn
import UIKit
import CryptoKit

@MainActor
class GoogleSignInHelper {

    struct GoogleSignInResult {
        let idToken: String
        let accessToken: String
        let serverAuthCode: String?
    }

    func signIn() async throws -> GoogleSignInResult {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw NSError(domain: "GoogleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "No root view controller found"])
        }

        let config = GIDConfiguration(clientID: GoogleConfig.webClientID)
        GIDSignIn.sharedInstance.configuration = config

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

        guard let idToken = result.user.idToken?.tokenString else {
            throw NSError(domain: "GoogleSignIn", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to get ID token"])
        }

        let accessToken = result.user.accessToken.tokenString
        let serverAuthCode = result.serverAuthCode

        return GoogleSignInResult(idToken: idToken, accessToken: accessToken, serverAuthCode: serverAuthCode)
    }

    // Generate a random nonce string for security
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }

        return String(nonce)
    }
}
