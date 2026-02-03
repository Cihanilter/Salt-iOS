//
//  AuthService.swift
//  Salt
//

import Foundation
import Supabase
import AuthenticationServices

protocol AuthService {
    func signUp(email: String, password: String, fullName: String) async throws -> UserProfile
    func signIn(email: String, password: String) async throws -> UserProfile
    func signInWithGoogle() async throws -> UserProfile
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws -> UserProfile
    func resetPassword(email: String) async throws
    func signOut() async throws
    func getCurrentUser() async throws -> UserProfile?
    func resendVerificationEmail() async throws
}

final class SupabaseAuthService: AuthService {
    private let client = SupabaseClientManager.shared.client

    // MARK: - Sign Up
    func signUp(email: String, password: String, fullName: String) async throws -> UserProfile {
        // Validate inputs
        guard ValidationHelper.isValidEmail(email) else {
            throw AuthError.invalidEmail
        }

        guard ValidationHelper.isValidPassword(password) else {
            throw AuthError.weakPassword
        }

        guard ValidationHelper.isValidFullName(fullName) else {
            throw AuthError.unknown("Please enter a valid full name.")
        }

        do {
            // Sign up with Supabase Auth and store full_name in metadata
            let authResponse = try await client.auth.signUp(
                email: email,
                password: password,
                data: ["full_name": .string(fullName)]
            )

            let userId = authResponse.user.id.uuidString

            // Profile will be created automatically by database trigger after email confirmation
            // For now, return a temporary profile
            let profile = UserProfile(
                id: userId,
                fullName: fullName,
                email: email,
                createdAt: Date(),
                updatedAt: Date()
            )

            return profile
        } catch let error as AuthError {
            throw error
        } catch {
            // Map Supabase errors
            throw mapSupabaseError(error)
        }
    }

    // MARK: - Sign In
    func signIn(email: String, password: String) async throws -> UserProfile {
        guard ValidationHelper.isValidEmail(email) else {
            throw AuthError.invalidEmail
        }

        do {
            let session = try await client.auth.signIn(
                email: email,
                password: password
            )

            let userId = session.user.id.uuidString

            // Fetch profile from database
            let profile: UserProfile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            return profile
        } catch {
            throw mapSupabaseError(error)
        }
    }

    // MARK: - Sign In with Google
    func signInWithGoogle() async throws -> UserProfile {
        do {
            // Get Google tokens from GoogleSignInHelper
            let helper = GoogleSignInHelper()
            let result = try await helper.signIn()

            // Sign in with Google tokens through Supabase
            // Note: We pass nonce as nil because Google SDK handles nonce internally
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: result.idToken,
                    accessToken: result.accessToken,
                    nonce: nil
                )
            )

            let userId = session.user.id.uuidString

            // Try to fetch existing profile
            do {
                let profile: UserProfile = try await client
                    .from("profiles")
                    .select()
                    .eq("id", value: userId)
                    .single()
                    .execute()
                    .value

                return profile
            } catch {
                // Profile doesn't exist, create it
                let fullName = session.user.userMetadata["full_name"]?.value as? String ?? "Google User"
                let email = session.user.email ?? ""

                let profile = UserProfile(
                    id: userId,
                    fullName: fullName,
                    email: email,
                    createdAt: Date(),
                    updatedAt: Date()
                )

                try await client
                    .from("profiles")
                    .insert(profile)
                    .execute()

                return profile
            }
        } catch {
            throw mapSupabaseError(error)
        }
    }

    // MARK: - Sign In with Apple
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws -> UserProfile {
        do {
            // Get the identity token from Apple
            guard let identityToken = credential.identityToken,
                  let idTokenString = String(data: identityToken, encoding: .utf8) else {
                throw AuthError.unknown("Failed to get identity token from Apple")
            }

            // Extract user info from Apple credential
            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")

            // Sign in with Apple ID token through Supabase
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idTokenString,
                    nonce: nil
                )
            )

            let userId = session.user.id.uuidString

            // Try to fetch existing profile
            do {
                let profile: UserProfile = try await client
                    .from("profiles")
                    .select()
                    .eq("id", value: userId)
                    .single()
                    .execute()
                    .value

                return profile
            } catch {
                // Profile doesn't exist, create it using trigger
                // The trigger will create the profile automatically
                // But we need to wait a moment for it to be created
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                // Try to fetch again
                let profile: UserProfile = try await client
                    .from("profiles")
                    .select()
                    .eq("id", value: userId)
                    .single()
                    .execute()
                    .value

                return profile
            }
        } catch {
            throw mapSupabaseError(error)
        }
    }

    // MARK: - Reset Password
    func resetPassword(email: String) async throws {
        guard ValidationHelper.isValidEmail(email) else {
            throw AuthError.invalidEmail
        }

        do {
            try await client.auth.resetPasswordForEmail(email)
        } catch {
            throw mapSupabaseError(error)
        }
    }

    // MARK: - Sign Out
    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            throw mapSupabaseError(error)
        }
    }

    // MARK: - Get Current User
    func getCurrentUser() async throws -> UserProfile? {
        do {
            let session = try client.auth.session
            let userId = session.user.id.uuidString

            let profile: UserProfile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            return profile
        } catch {
            return nil
        }
    }

    // MARK: - Resend Verification Email
    func resendVerificationEmail() async throws {
        do {
            guard let session = try? client.auth.session else {
                throw AuthError.unknown("No active session")
            }

            // TODO: Fix resend API call according to Supabase Auth SDK
            throw AuthError.unknown("Resend email not yet implemented")
        } catch {
            throw mapSupabaseError(error)
        }
    }

    // MARK: - Error Mapping
    private func mapSupabaseError(_ error: Error) -> AuthError {
        let errorMessage = error.localizedDescription.lowercased()

        if errorMessage.contains("email") && errorMessage.contains("already") {
            return .emailAlreadyInUse
        } else if errorMessage.contains("invalid") && errorMessage.contains("credentials") {
            return .invalidCredentials
        } else if errorMessage.contains("user") && errorMessage.contains("not found") {
            return .userNotFound
        } else if errorMessage.contains("email") && errorMessage.contains("not") && errorMessage.contains("confirmed") {
            return .emailNotVerified
        } else if errorMessage.contains("network") {
            return .networkError
        } else {
            return .unknown(error.localizedDescription)
        }
    }
}
