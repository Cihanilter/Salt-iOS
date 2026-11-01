//
//  AuthManager.swift
//  Salt
//

import Foundation
import Combine
import Supabase
import AuthenticationServices

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var currentUser: UserProfile?
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = true

    private let authService: AuthService
    private let client = SupabaseClientManager.shared.client
    private var cancellables = Set<AnyCancellable>()

    private init(authService: AuthService = SupabaseAuthService()) {
        self.authService = authService
        Task {
            await checkCurrentSession()
            await setupAuthStateListener()
        }
    }

    // MARK: - Setup Auth State Listener
    private func setupAuthStateListener() async {
        for await state in client.auth.authStateChanges {
            print("Auth state changed: \(state.event)")
            switch state.event {
            case .signedIn:
                await loadCurrentUser()
            case .signedOut:
                self.currentUser = nil
                self.isAuthenticated = false
            case .userUpdated:
                await loadCurrentUser()
            default:
                break
            }
        }
    }

    // MARK: - Check Current Session
    private func checkCurrentSession() async {
        print("AuthManager: Checking current session...")
        isLoading = true
        defer {
            isLoading = false
            print("AuthManager: Loading complete. isAuthenticated = \(isAuthenticated)")
        }

        do {
            if let user = try await authService.getCurrentUser() {
                print("AuthManager: Found existing user: \(user.email)")
                self.currentUser = user
                self.isAuthenticated = true
            } else {
                print("AuthManager: No existing session found")
                self.currentUser = nil
                self.isAuthenticated = false
            }
        } catch {
            print("AuthManager: Error checking session: \(error)")
            self.currentUser = nil
            self.isAuthenticated = false
        }
    }

    // MARK: - Load Current User
    private func loadCurrentUser() async {
        do {
            if let user = try await authService.getCurrentUser() {
                self.currentUser = user
                self.isAuthenticated = true
            }
        } catch {
            print("Failed to load current user: \(error)")
        }
    }

    // MARK: - Sign Up
    func signUp(email: String, password: String, fullName: String) async throws {
        _ = try await authService.signUp(email: email, password: password, fullName: fullName)
        // Note: User won't be authenticated until email is verified
        // So we don't set currentUser here
    }

    // MARK: - Sign In
    func signIn(email: String, password: String) async throws {
        let user = try await authService.signIn(email: email, password: password)
        self.currentUser = user
        self.isAuthenticated = true
    }

    // MARK: - Sign In with Google
    /// Returns true if this sign-in created the account (a sign-up)
    @discardableResult
    func signInWithGoogle() async throws -> Bool {
        let user = try await authService.signInWithGoogle()
        self.currentUser = user
        self.isAuthenticated = true
        return isNewAccount
    }

    // MARK: - Sign In with Apple
    /// Returns true if this sign-in created the account (a sign-up)
    @discardableResult
    func signInWithApple(credential: Any) async throws -> Bool {
        guard let appleCredential = credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.unknown("Invalid Apple credential")
        }
        let user = try await authService.signInWithApple(credential: appleCredential)
        self.currentUser = user
        self.isAuthenticated = true
        return isNewAccount
    }

    /// Whether a session is saved on the device. Unlike `isAuthenticated`, it's already
    /// known at launch, before the session has been checked.
    var hasStoredSession: Bool {
        client.auth.currentSession != nil
    }

    /// Whether the signed-in Supabase account was created by the sign-in that just happened.
    /// Apple and Google create the account on first sign-in, so the sign-up/sign-in button
    /// doesn't tell them apart; on the first sign-in `last_sign_in_at` equals `created_at`.
    private var isNewAccount: Bool {
        guard let user = client.auth.currentUser else { return false }
        let lastSignInAt = user.lastSignInAt ?? Date()
        return abs(lastSignInAt.timeIntervalSince(user.createdAt)) < 60
    }

    // MARK: - Reset Password
    func resetPassword(email: String) async throws {
        try await authService.resetPassword(email: email)
    }

    // MARK: - Update Password
    func updatePassword(newPassword: String) async throws {
        try await authService.updatePassword(newPassword: newPassword)
    }

    // MARK: - Sign Out
    func signOut() async throws {
        try await authService.signOut()
        Analytics.reset()
        ImportTutorialBanner.resetDismissal()
        self.currentUser = nil
        self.isAuthenticated = false
    }

    // MARK: - Delete Account
    func deleteAccount() async throws {
        try await authService.deleteAccount()
        Analytics.reset()
        ImportTutorialBanner.resetDismissal()
        self.currentUser = nil
        self.isAuthenticated = false
    }

    // MARK: - Resend Verification Email
    func resendVerificationEmail() async throws {
        try await authService.resendVerificationEmail()
    }
}
