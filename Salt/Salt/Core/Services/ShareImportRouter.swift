//
//  ShareImportRouter.swift
//  Salt
//
//  Holds what the Share Extension sent (a recipe link via `salt://import?url=...`, or
//  photos/text via `salt://import?shared=<id>`) until the Import screen is on screen to process it.
//

import Foundation
import UIKit
import Combine

/// Something shared to Salt to import a recipe from
enum SharedImport: Equatable {
    case link(String)
    /// Screenshots or photos, in the order they were shared
    case photos([UIImage])
    /// A written-out recipe, e.g. a note from the Notes app
    case text(String)
}

@MainActor
final class ShareImportRouter: ObservableObject {
    static let shared = ShareImportRouter()

    /// Import waiting to run. Stays set until the Import screen consumes it,
    /// so things shared while logged out are imported right after login.
    @Published private(set) var pendingImport: SharedImport?

    private init() {}

    /// Returns true if the deep link was a share-import link and has been queued.
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "salt", url.host == "import" else { return false }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if let id = queryItems.first(where: { $0.name == "shared" })?.value {
            takeFromInbox(id: id)
            return true
        }

        guard let recipeUrl = queryItems.first(where: { $0.name == "url" })?.value,
              !recipeUrl.isEmpty else {
            return true
        }

        // Start of the share funnel: signed-out users hit sign-in before the import runs
        Analytics.log(.shareLinkReceived, [
            "source": Analytics.importSource(for: recipeUrl),
            "cold_launch": Analytics.isColdLaunch,
            "signed_in": AuthManager.shared.hasStoredSession
        ])

        pendingImport = .link(recipeUrl)
        return true
    }

    /// Picks up photos or text the Share Extension saved but couldn't open the app for
    /// (e.g. the system refused), so they're imported the next time Salt is opened.
    func checkInbox() {
        guard pendingImport == nil, let id = SharedImportInbox.oldestId() else { return }
        takeFromInbox(id: id)
    }

    /// Hands the pending import to the caller and clears it so it's imported only once.
    func consume() -> SharedImport? {
        defer { pendingImport = nil }
        return pendingImport
    }

    private func takeFromInbox(id: String) {
        guard let sharedImport = SharedImportInbox.take(id: id) else { return }

        Analytics.log(.shareLinkReceived, [
            "source": sharedImport.analyticsSource,
            "cold_launch": Analytics.isColdLaunch,
            "signed_in": AuthManager.shared.hasStoredSession
        ])

        pendingImport = sharedImport
    }
}

private extension SharedImport {
    var analyticsSource: String {
        switch self {
        case .link(let url): return Analytics.importSource(for: url)
        case .photos: return ImportOrigin.photo.rawValue
        case .text: return ImportOrigin.note.rawValue
        }
    }
}

// MARK: - Shared Import Inbox

/// Photos and text the Share Extension saved to the App Group, since they're too big for a deep link.
/// Format, written by the extension's `ShareViewController`:
/// `<App Group>/SharedImports/<id>/` holding either `1.jpg`, `2.jpg`, ... (in order) or `text.txt`
enum SharedImportInbox {
    private static let appGroup = "group.com.salt.recipes"

    private static var inboxFolder: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("SharedImports", isDirectory: true)
    }

    /// Reads the shared photos or text and deletes them, so they're imported only once
    static func take(id: String) -> SharedImport? {
        // The id comes from a deep link; only accept a plain folder name
        guard let inboxFolder, UUID(uuidString: id) != nil else { return nil }
        let folder = inboxFolder.appendingPathComponent(id, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        if let text = try? String(contentsOf: folder.appendingPathComponent("text.txt"), encoding: .utf8) {
            return .text(text)
        }

        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let photos = files
            .filter { $0.pathExtension == "jpg" }
            // 1.jpg, 2.jpg, ... 10.jpg in the order they were shared
            .sorted { Int($0.deletingPathExtension().lastPathComponent) ?? 0 < Int($1.deletingPathExtension().lastPathComponent) ?? 0 }
            .compactMap { UIImage(contentsOfFile: $0.path) }
        return photos.isEmpty ? nil : .photos(photos)
    }

    /// The oldest waiting share, if any
    static func oldestId() -> String? {
        guard let inboxFolder,
              let folders = try? FileManager.default.contentsOfDirectory(
                at: inboxFolder, includingPropertiesForKeys: [.creationDateKey]
              ) else { return nil }

        func created(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        }
        return folders.min { created($0) < created($1) }?.lastPathComponent
    }
}
