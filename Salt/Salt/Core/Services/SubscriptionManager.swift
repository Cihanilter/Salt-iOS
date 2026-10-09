//
//  SubscriptionManager.swift
//  Salt
//
//  Wraps RevenueCat: configures the SDK, links purchases to the signed-in Supabase user,
//  and decides whether a free user still has recipe imports left.
//

import Foundation
import Combine
import RevenueCat

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    /// True while the user has an active "premium" entitlement (monthly or yearly)
    @Published private(set) var isPremium = false

    private var customerInfoTask: Task<Void, Never>?

    private init() {}

    // MARK: - Setup

    /// Call once at launch, before anything else touches `Purchases.shared`.
    /// Does nothing until `RevenueCatConfig.isEnabled` is turned on.
    func configure() {
        guard RevenueCatConfig.isEnabled, !Purchases.isConfigured else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)

        // Apple Search Ads: sends the install's AdServices token so RevenueCat can tie revenue to campaigns
        Purchases.shared.attribution.enableAdServicesAttributionTokenCollection()

        // Keeps `isPremium` in sync with purchases, renewals, expirations and restores
        customerInfoTask = Task { [weak self] in
            for await customerInfo in Purchases.shared.customerInfoStream {
                self?.update(with: customerInfo)
            }
        }
    }

    // MARK: - User Identity

    /// Ties purchases to the Supabase user ID so Premium follows the account across devices.
    /// Pass nil when the user signs out.
    func setUser(id userId: String?) async {
        // Purchases.shared crashes if the SDK was never configured
        guard Purchases.isConfigured else { return }

        do {
            if let userId {
                let result = try await Purchases.shared.logIn(userId)
                update(with: result.customerInfo)
            } else if !Purchases.shared.isAnonymous {
                // logOut throws if the current user is already anonymous
                let customerInfo = try await Purchases.shared.logOut()
                update(with: customerInfo)
            }
        } catch {
            print("RevenueCat: Failed to update user: \(error)")
        }
    }

    // MARK: - Import Limit

    /// Whether the user can import another recipe. Premium users are unlimited;
    /// free users are limited to `RevenueCatConfig.freeImportLimit` saved imports.
    func canImportRecipe() async -> Bool {
        guard RevenueCatConfig.isEnabled, Purchases.isConfigured else { return true }
        if isPremium { return true }

        do {
            let used = try await RecipeService.shared.getImportedRecipesCount()
            return used < RevenueCatConfig.freeImportLimit
        } catch {
            // Don't block importing if the count can't be loaded (e.g. offline)
            print("Failed to check import limit: \(error)")
            return true
        }
    }

    // MARK: - Customer Info

    /// Updates Premium status right away, e.g. from a paywall purchase result,
    /// without waiting for `customerInfoStream` to deliver it.
    func update(with customerInfo: CustomerInfo) {
        isPremium = customerInfo.entitlements[RevenueCatConfig.premiumEntitlementID]?.isActive == true
        Analytics.setPremium(isPremium)
    }
}
