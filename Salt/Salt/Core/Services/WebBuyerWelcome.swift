//
//  WebBuyerWelcome.swift
//  Salt
//
//  When to welcome a web funnel buyer (quiz.saltrecipes.app) after they log in: they
//  bought Premium on the web and log in to an account made there, so they skip the app's
//  onboarding and its import tutorial. Shown once per account on a device.
//

import Foundation
import Supabase

@MainActor
enum WebBuyerWelcome {
    /// Whether to show the welcome to this user now
    static func shouldShow(for user: UserProfile) async -> Bool {
        guard !wasShown(for: user), isWebFunnelAccount else { return false }

        // Went through Get started (and its tutorial) on this device before logging in
        if UserDefaults.standard.bool(forKey: OnboardingStorage.tutorialSeenKey) {
            markShown(for: user)
            return false
        }

        // Already imported a recipe (e.g. reinstalled the app): they know how it works.
        // When the count can't be loaded, not showing beats showing it to someone who has
        guard let count = try? await RecipeService.shared.getImportedRecipesCount(), count == 0 else {
            return false
        }
        return true
    }

    static func markShown(for user: UserProfile) {
        UserDefaults.standard.set(true, forKey: key(for: user.id))
    }

    /// The funnel creates accounts with `user_metadata.source = "web_funnel"`
    /// (Salt-backend `api/funnel-account.js`). Accounts made in the app and only paid on the
    /// web don't have it; they've been through the app's onboarding already.
    private static var isWebFunnelAccount: Bool {
        SupabaseClientManager.shared.client.auth.currentUser?.userMetadata["source"]?.value as? String == "web_funnel"
    }

    private static func wasShown(for user: UserProfile) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: user.id))
    }

    /// Per account, so another web buyer signing in on the same phone still gets it
    private static func key(for userId: String) -> String {
        "webBuyerWelcomeShown.\(userId)"
    }
}
