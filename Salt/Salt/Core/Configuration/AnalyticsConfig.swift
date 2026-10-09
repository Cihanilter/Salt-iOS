//
//  AnalyticsConfig.swift
//  Salt
//

import Foundation

enum AnalyticsConfig {
    /// PostHog project API key (Project settings > Project API key, starts with "phc_").
    /// Analytics stay off while it's empty.
    static let postHogAPIKey = "phc_kPyXoZDJY3f5copY6P8C9fmJ6Q4pVypXUc5ZZkMtWFYb"

    /// PostHog region: "https://us.i.posthog.com" or "https://eu.i.posthog.com"
    static let postHogHost = "https://us.i.posthog.com"

    /// Share of sessions recorded for session replay (0.0–1.0)
    static let sessionReplaySampleRate = 1.0

    static var isConfigured: Bool {
        !postHogAPIKey.isEmpty
    }
}
