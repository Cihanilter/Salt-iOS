//
//  SaltApp.swift
//  Salt
//

import SwiftUI
import Supabase
import GoogleSignIn

@main
struct SaltApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    print("Deep link received: \(url)")

                    // Handle Google Sign In callback
                    GIDSignIn.sharedInstance.handle(url)

                    // Handle Supabase auth callback
                    Task {
                        do {
                            try await SupabaseClientManager.shared.client.auth.session(from: url)
                            print("Session restored from deep link")
                        } catch {
                            print("Failed to handle deep link: \(error)")
                        }
                    }
                }
        }
    }
}
