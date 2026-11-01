//
//  ShareImportRouter.swift
//  Salt
//
//  Holds a recipe link received from the Share Extension (`salt://import?url=...`)
//  until the Import screen is on screen to process it.
//

import Foundation
import Combine

@MainActor
final class ShareImportRouter: ObservableObject {
    static let shared = ShareImportRouter()

    /// Recipe URL waiting to be imported. Stays set until the Import screen consumes it,
    /// so links shared while logged out are imported right after login.
    @Published private(set) var pendingUrl: String?

    private init() {}

    /// Returns true if the deep link was a share-import link and has been queued.
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "salt", url.host == "import" else { return false }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let recipeUrl = components?.queryItems?.first(where: { $0.name == "url" })?.value,
              !recipeUrl.isEmpty else {
            return true
        }

        // Start of the share funnel: signed-out users hit sign-in before the import runs
        Analytics.log(.shareLinkReceived, [
            "source": Analytics.importSource(for: recipeUrl),
            "cold_launch": Analytics.isColdLaunch,
            "signed_in": AuthManager.shared.hasStoredSession
        ])

        pendingUrl = recipeUrl
        return true
    }

    /// Hands the pending URL to the caller and clears it so it's imported only once.
    func consume() -> String? {
        defer { pendingUrl = nil }
        return pendingUrl
    }
}
