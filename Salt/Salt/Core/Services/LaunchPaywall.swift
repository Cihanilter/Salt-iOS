//
//  LaunchPaywall.swift
//  Salt
//
//  When to show the paywall at launch: right after signing up, then every other day for
//  free users. Premium users never see it.
//

import Foundation

@MainActor
enum LaunchPaywall {
    /// Why the paywall is shown, for analytics
    enum Trigger: String {
        case newAccount = "new_account"
        case returning
    }

    /// The trigger if the paywall should show for this user now, nil otherwise
    static func trigger(for user: UserProfile) async -> Trigger? {
        guard RevenueCatConfig.isEnabled else { return nil }

        let lastShown = UserDefaults.standard.object(forKey: key(for: user.id)) as? Date
        if let lastShown, daysSince(lastShown) < RevenueCatConfig.launchPaywallIntervalDays {
            return nil
        }

        // Checked with RevenueCat: at launch the stored status may not be loaded yet
        guard await SubscriptionManager.shared.verifiedPremiumStatus() == false else { return nil }

        // Accounts made in the last day are new; everyone else has used Salt before
        let isNew = lastShown == nil && Date().timeIntervalSince(user.createdAt) < 24 * 60 * 60

        // A new account that just saw the paywall in onboarding isn't shown it again right away;
        // the every-other-day interval starts from then
        if isNew, let onboardingShown = UserDefaults.standard.object(forKey: OnboardingStorage.paywallShownKey) as? Date,
           Date().timeIntervalSince(onboardingShown) < 24 * 60 * 60 {
            UserDefaults.standard.set(onboardingShown, forKey: key(for: user.id))
            return nil
        }

        return isNew ? .newAccount : .returning
    }

    /// Starts the interval again; called when the paywall appears
    static func markShown(for user: UserProfile) {
        UserDefaults.standard.set(Date(), forKey: key(for: user.id))
    }

    /// Per account, so a new account on a shared phone still gets its first paywall
    private static func key(for userId: String) -> String {
        "launchPaywallLastShown.\(userId)"
    }

    /// Calendar days, so "every other day" doesn't depend on the time it was last shown
    private static func daysSince(_ date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                       to: calendar.startOfDay(for: Date())).day ?? 0
    }
}
