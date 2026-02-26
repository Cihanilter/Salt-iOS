//
//  SaltApp.swift
//  Salt
//

import SwiftUI
import Supabase
import GoogleSignIn

@main
struct SaltApp: App {
    @State private var showSetNewPassword = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    print("Deep link received: \(url)")
                    print("Deep link full URL: \(url.absoluteString)")

                    // Handle Google Sign In callback
                    GIDSignIn.sharedInstance.handle(url)

                    // Handle Supabase auth callback
                    Task {
                        do {
                            let session = try await SupabaseClientManager.shared.client.auth.session(from: url)
                            print("Session restored from deep link")
                            print("Session user ID: \(session.user.id)")
                            print("Session user email: \(session.user.email ?? "nil")")
                            print("Session user recovery sent at: \(String(describing: session.user.recoverySentAt))")

                            // Check if user has a recent recovery request (within last 5 minutes)
                            if let recoverySentAt = session.user.recoverySentAt {
                                let fiveMinutesAgo = Date().addingTimeInterval(-5 * 60)
                                if recoverySentAt > fiveMinutesAgo {
                                    print("Recovery flow detected! Showing password reset screen.")
                                    showSetNewPassword = true
                                }
                            }
                        } catch {
                            print("Failed to handle deep link: \(error)")
                        }
                    }
                }
                .sheet(isPresented: $showSetNewPassword) {
                    SetNewPasswordView(viewModel: SetNewPasswordViewModel()) {
                        showSetNewPassword = false
                    }
                }
        }
    }
}
