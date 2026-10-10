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

    init() {
        SubscriptionManager.shared.configure()
        AppsFlyerManager.shared.configure()
        Analytics.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    print("Deep link received: \(url)")
                    print("Deep link full URL: \(url.absoluteString)")

                    // AppsFlyer sorts out universal links (OneLink) and URL schemes itself
                    AppsFlyerManager.shared.handle(url)

                    // Recipe share links and collection invites (universal links can arrive here as well as in onContinueUserActivity)
                    if url.scheme == "https" {
                        _ = SharedRecipeRouter.shared.handle(url) || CollectionInviteRouter.shared.handle(url)
                        return
                    }

                    // Handle recipe links shared from the Share Extension
                    if ShareImportRouter.shared.handle(url) {
                        return
                    }

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
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    // Recipe share links and collection invites (OneLink universal links)
                    AppsFlyerManager.shared.handle(activity)
                    if let url = activity.webpageURL {
                        _ = SharedRecipeRouter.shared.handle(url) || CollectionInviteRouter.shared.handle(url)
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
