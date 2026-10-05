//
//  RevenueCatConfig.swift
//  Salt
//

import Foundation

enum RevenueCatConfig {
    /// Off until the subscription products are live on the App Store.
    /// When false, the SDK is never configured and no subscription UI or limits are shown.
    static let isEnabled = false

    /// Public Apple API key from RevenueCat > Project Settings > API keys (starts with "appl_")
    static let apiKey = "appl_ITxowMOOtgljhaIzPuBINmlALfz"

    /// Entitlement identifier set up in the RevenueCat dashboard, attached to the monthly and yearly products
    static let premiumEntitlementID = "premium"

    /// Number of recipe imports a free user can save, counted from the `recipe_imports` log
    static let freeImportLimit = 3
}
