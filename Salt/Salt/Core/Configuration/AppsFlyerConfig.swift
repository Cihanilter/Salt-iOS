//
//  AppsFlyerConfig.swift
//  Salt
//

import Foundation

enum AppsFlyerConfig {
    /// Dev key from AppsFlyer > Configuration > App settings. The SDK isn't started while it's empty.
    static let devKey = "xcNz9xb7VVDDAkNztNKXPf"

    /// Salt's Apple ID from App Store Connect > App Information (numbers only, without "id")
    static let appleAppID = "6759310927"

    /// OneLink subdomain from the OneLink template. Must also be in the Associated Domains entitlement.
    static let oneLinkDomain = "saltrecipes.onelink.me"

    /// OneLink template ID (the 4 characters after the domain in the template's links)
    static let oneLinkTemplateID = "ked7"

    static var isConfigured: Bool {
        !devKey.isEmpty && !appleAppID.isEmpty
    }
}
