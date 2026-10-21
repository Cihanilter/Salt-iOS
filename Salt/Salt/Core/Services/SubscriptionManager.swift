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

    /// Premium features are open when the user has Premium, or when subscriptions are switched off
    var hasPremiumAccess: Bool {
        !RevenueCatConfig.isEnabled || isPremium
    }

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
        if await refreshPremium() { return true }

        do {
            let used = try await RecipeService.shared.getImportedRecipesCount()
            return used < RevenueCatConfig.freeImportLimit
        } catch {
            // Don't block importing if the count can't be loaded (e.g. offline)
            print("Failed to check import limit: \(error)")
            return true
        }
    }

    /// Whether the user has Premium, checked with RevenueCat; nil when it can't be told
    /// (subscriptions off, or RevenueCat unreachable), so nothing is sold to someone who may have it
    func verifiedPremiumStatus() async -> Bool? {
        guard RevenueCatConfig.isEnabled, Purchases.isConfigured else { return nil }
        if await refreshPremium() { return true }
        // refreshPremium falls back to false when RevenueCat couldn't be reached; only trust a real answer
        guard (try? await Purchases.shared.customerInfo()) != nil else { return nil }
        return isPremium
    }

    /// Premium status checked with RevenueCat, for decisions made right after launch. When Salt
    /// is opened from the Share Extension, an import can start before RootView has linked
    /// RevenueCat to the signed-in user, while `isPremium` still has its launch value (false).
    private func refreshPremium() async -> Bool {
        if isPremium { return true }

        // Purchases belong to the Supabase user; until logIn they'd be looked up for an anonymous ID
        if let userId = AuthManager.shared.currentUser?.id, Purchases.shared.appUserID != userId {
            await setUser(id: userId)
            if isPremium { return true }
        }

        do {
            update(with: try await Purchases.shared.customerInfo())
        } catch {
            print("RevenueCat: Failed to refresh customer info: \(error)")
        }
        return isPremium
    }

    // MARK: - Customer Info

    /// Updates Premium status right away, e.g. from a paywall purchase result,
    /// without waiting for `customerInfoStream` to deliver it.
    func update(with customerInfo: CustomerInfo) {
        isPremium = customerInfo.entitlements[RevenueCatConfig.premiumEntitlementID]?.isActive == true
        Analytics.setPremium(isPremium)
    }
}
