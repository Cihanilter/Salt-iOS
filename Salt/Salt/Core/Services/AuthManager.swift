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
    func signInWithGoogle() async throws {
        let user = try await authService.signInWithGoogle()
        self.currentUser = user
        self.isAuthenticated = true
    }

    // MARK: - Sign In with Apple
    func signInWithApple(credential: Any) async throws {
        guard let appleCredential = credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.unknown("Invalid Apple credential")
        }
        let user = try await authService.signInWithApple(credential: appleCredential)
        self.currentUser = user
        self.isAuthenticated = true
    }

    // MARK: - Reset Password
    func resetPassword(email: String) async throws {
        try await authService.resetPassword(email: email)
    }

    // MARK: - Sign Out
    func signOut() async throws {
        try await authService.signOut()
        self.currentUser = nil
        self.isAuthenticated = false
    }

    // MARK: - Resend Verification Email
    func resendVerificationEmail() async throws {
        try await authService.resendVerificationEmail()
    }
}
