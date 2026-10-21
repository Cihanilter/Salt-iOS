//
//  RevenueCatConfig.swift
//  Salt
//

import Foundation

enum RevenueCatConfig {
    /// Master switch for subscriptions. When false, the SDK is never configured
    /// and no paywall or import limit is applied.
    static let isEnabled = true

    /// Public Apple API key from RevenueCat > Project Settings > API keys (starts with "appl_")
    static let apiKey = "appl_ITxowMOOtgljhaIzPuBINmlALfz"

    /// Entitlement identifier set up in the RevenueCat dashboard, attached to the monthly and yearly products.
    /// Case-sensitive: must match the dashboard exactly.
    static let premiumEntitlementID = "Premium"

    /// Number of recipe imports a free user can save, counted from the `recipe_imports` log
    static let freeImportLimit = 3

    /// Free users see the paywall on launch at most this often (in calendar days); new accounts
    /// see it right after signing up
    static let launchPaywallIntervalDays = 2
}
