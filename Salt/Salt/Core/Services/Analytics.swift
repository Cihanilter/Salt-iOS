//
//  Analytics.swift
//  Salt
//
//  Product analytics and session replay (PostHog). The rest of the app only calls
//  `Analytics`, so the provider can be swapped in one place.
//

import Foundation
import SwiftUI
import PostHog

enum Analytics {
    /// Events sent to PostHog. Raw values are the event names shown in the dashboard.
    enum Event: String {
        // Account
        case signedUp = "signed_up"
        case signedIn = "signed_in"
        case authFailed = "auth_failed"

        // Add Recipe
        case importStarted = "import_started"
        case importFailed = "import_failed"
        case recipeImported = "recipe_imported"
        case recipeCreated = "recipe_created"

        // My Recipes
        case recipeEdited = "recipe_edited"
        case recipeDeleted = "recipe_deleted"
        case recipeCustomized = "recipe_customized"
        case recipeBookmarked = "recipe_bookmarked"
        case recipeUnbookmarked = "recipe_unbookmarked"

        // Explore
        case searchFiltered = "search_filtered"

        // Collections
        case collectionCreated = "collection_created"
        case collectionDeleted = "collection_deleted"
        case recipeAddedToCollection = "recipe_added_to_collection"
        case recipeRemovedFromCollection = "recipe_removed_from_collection"
        case collectionInviteCreated = "collection_invite_created"
        case collectionInviteOpened = "collection_invite_opened"
        case collectionJoined = "collection_joined"
        case collectionLeft = "collection_left"
        case collectionMemberRemoved = "collection_member_removed"
        case recipeCopiedFromCollection = "recipe_copied_from_collection"

        // Sharing
        case recipeShared = "recipe_shared"
        case sharedRecipeOpened = "shared_recipe_opened"
        case sharedRecipeSaved = "shared_recipe_saved"

        // Subscription
        case paywallShown = "paywall_shown"
        case subscriptionStarted = "subscription_started"
        case purchasesRestored = "purchases_restored"
    }

    /// Call once at launch
    static func configure() {
        guard AnalyticsConfig.isConfigured else { return }

        let config = PostHogConfig(projectToken: AnalyticsConfig.postHogAPIKey, host: AnalyticsConfig.postHogHost)
        config.captureApplicationLifecycleEvents = true  // App Installed / Opened / Backgrounded
        config.captureScreenViews = false                 // SwiftUI screens are sent with `screen(_:)`
        config.personProfiles = .identifiedOnly

        // Session replay: SwiftUI needs screenshot mode. Typed text is masked; recipe photos aren't.
        config.sessionReplay = true
        config.sessionReplayConfig.screenshotMode = true
        config.sessionReplayConfig.maskAllTextInputs = true
        config.sessionReplayConfig.maskAllImages = false
        config.sessionReplayConfig.sampleRate = NSNumber(value: AnalyticsConfig.sessionReplaySampleRate)

        PostHogSDK.shared.setup(config)
    }

    /// Ties events to the signed-in Supabase user, or starts a new anonymous user on sign out
    static func setUser(id userId: String?) {
        guard AnalyticsConfig.isConfigured else { return }
        if let userId {
            PostHogSDK.shared.identify(userId)
        } else {
            PostHogSDK.shared.reset()
        }
    }

    /// Keeps the Premium status on the user's profile, for comparing free and Premium users
    static func setPremium(_ isPremium: Bool) {
        guard AnalyticsConfig.isConfigured else { return }
        PostHogSDK.shared.capture("$set", userProperties: ["is_premium": isPremium])
    }

    static func log(_ event: Event, _ properties: [String: Any] = [:]) {
        guard AnalyticsConfig.isConfigured else { return }
        PostHogSDK.shared.capture(event.rawValue, properties: properties)
    }

    /// Screen view, for user paths and funnels
    static func screen(_ name: String) {
        guard AnalyticsConfig.isConfigured else { return }
        PostHogSDK.shared.screen(name)
    }

    /// Where an imported recipe came from, from its link
    static func importSource(for url: String?) -> String {
        let url = url?.lowercased() ?? ""
        if url.contains("instagram") { return "instagram" }
        if url.contains("tiktok") { return "tiktok" }
        if url.contains("youtube") || url.contains("youtu.be") { return "youtube" }
        return "web"
    }
}

// MARK: - Session Replay Masking

extension View {
    /// Hides this view in session recordings (personal info like name and email)
    func analyticsMasked() -> some View {
        postHogMask()
    }
}
