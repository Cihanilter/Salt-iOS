//
//  WebBuyerLinkRouter.swift
//  Salt
//
//  The Download Salt button on the web funnel's success page is a OneLink with
//  `deep_link_value=web_buyer`. Opened before install (deferred) or with Salt installed,
//  it takes the buyer straight to Log in: their account already exists, and Get started
//  would lead them to make a second one without Premium.
//

import Foundation
import Combine

@MainActor
final class WebBuyerLinkRouter: ObservableObject {
    static let shared = WebBuyerLinkRouter()
    static let deepLinkValue = "web_buyer"

    /// Set until the signed-out screens open Log in
    @Published private(set) var opensLogin = false

    private init() {}

    /// Returns true if the URL is a web buyer link (a long OneLink with its parameters)
    func handle(_ url: URL) -> Bool {
        guard url.host?.lowercased() == AppsFlyerConfig.oneLinkDomain.lowercased() else { return false }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard queryItems.first(where: { $0.name == "deep_link_value" })?.value == Self.deepLinkValue else { return false }
        receive()
        return true
    }

    /// Also called for the deferred link after a fresh install
    func receive() {
        // Already signed in: nothing to log in to
        guard !AuthManager.shared.isAuthenticated else { return }
        Analytics.log(.webBuyerLinkOpened)
        opensLogin = true
    }

    func clear() {
        opensLogin = false
    }
}
