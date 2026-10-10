//
//  SharedRecipeRouter.swift
//  Salt
//
//  Holds the code of a OneLink (shared recipe or collection invite) until the main screen
//  is up to show it.
//

import Foundation
import Combine

/// Queues the code of one kind of OneLink, told apart by its `deep_link_value`
@MainActor
class OneLinkCodeRouter: ObservableObject {
    /// Link parameter holding the code
    static let codeParameter = "deep_link_sub1"

    let deepLinkValue: String

    /// Code waiting to be shown. Stays set while logged out, so it opens right after login.
    @Published private(set) var pendingCode: String?

    /// The same open is reported twice (by the link itself and by the AppsFlyer SDK),
    /// so a code received again shortly after is ignored
    private var lastReceived: (code: String, date: Date)?

    init(deepLinkValue: String) {
        self.deepLinkValue = deepLinkValue
    }

    /// Returns true if the URL is this kind of link and its code has been queued.
    func handle(_ url: URL) -> Bool {
        guard url.host?.lowercased() == AppsFlyerConfig.oneLinkDomain.lowercased() else { return false }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard queryItems.first(where: { $0.name == "deep_link_value" })?.value == deepLinkValue,
              let code = queryItems.first(where: { $0.name == Self.codeParameter })?.value else {
            // Another kind of link, or a short link without the parameters: the SDK resolves it
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

    /// Clears the code once its screen is closed
    func clear() {
        pendingCode = nil
    }
}

/// Shared recipe links (shared_recipes code)
@MainActor
final class SharedRecipeRouter: OneLinkCodeRouter {
    static let shared = SharedRecipeRouter()
    static let deepLinkValue = "recipe"

    private init() {
        super.init(deepLinkValue: Self.deepLinkValue)
    }
}

/// Collection invite links (collections.invite_code)
@MainActor
final class CollectionInviteRouter: OneLinkCodeRouter {
    static let shared = CollectionInviteRouter()
    static let deepLinkValue = "collection"

    private init() {
        super.init(deepLinkValue: Self.deepLinkValue)
    }
}
