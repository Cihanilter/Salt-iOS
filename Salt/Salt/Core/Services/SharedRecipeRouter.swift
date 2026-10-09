//
//  SharedRecipeRouter.swift
//  Salt
//
//  Holds the code of a shared recipe link (OneLink) until the main screen is up to show it.
//

import Foundation
import Combine

@MainActor
final class SharedRecipeRouter: ObservableObject {
    static let shared = SharedRecipeRouter()

    /// `deep_link_value` of recipe share links
    static let deepLinkValue = "recipe"
    /// Link parameter holding the shared_recipes code
    static let codeParameter = "deep_link_sub1"

    /// Code waiting to be shown. Stays set while logged out, so the recipe opens right after login.
    @Published private(set) var pendingCode: String?

    /// The same open is reported twice (by the link itself and by the AppsFlyer SDK),
    /// so a code received again shortly after is ignored
    private var lastReceived: (code: String, date: Date)?

    private init() {}

    /// Returns true if the URL is a recipe share link and its code has been queued.
    func handle(_ url: URL) -> Bool {
        guard url.host?.lowercased() == AppsFlyerConfig.oneLinkDomain.lowercased() else { return false }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard queryItems.first(where: { $0.name == "deep_link_value" })?.value == Self.deepLinkValue,
              let code = queryItems.first(where: { $0.name == Self.codeParameter })?.value else {
            // A OneLink without the parameters (e.g. a short link): the SDK resolves it
            return false
        }
        receive(code: code)
        return true
    }

    /// Queues a code resolved from a link (also for deferred links after a fresh install)
    func receive(code: String) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        if let lastReceived, lastReceived.code == code, Date().timeIntervalSince(lastReceived.date) < 10 {
            return
        }
        lastReceived = (code, Date())
        pendingCode = code
    }

    /// Clears the code once its recipe screen is closed
    func clear() {
        pendingCode = nil
    }
}
