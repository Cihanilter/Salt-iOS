//
//  AppsFlyerManager.swift
//  Salt
//
//  Starts the AppsFlyer SDK and passes recipe share links it resolves (OneLink),
//  including deferred ones after a fresh install, to SharedRecipeRouter.
//

import Foundation
import AppsFlyerLib

final class AppsFlyerManager: NSObject {
    static let shared = AppsFlyerManager()

    private override init() {}

    /// Call once at launch. The SDK then starts a session each time the app comes to the foreground.
    func configure() {
        guard AppsFlyerConfig.isConfigured else { return }

        let appsFlyer = AppsFlyerLib.shared()
        appsFlyer.initialize(devKey: AppsFlyerConfig.devKey, appId: AppsFlyerConfig.appleAppID)
        appsFlyer.deepLinkDelegate = self
        // OneLink template used for short share links
        appsFlyer.appInviteOneLinkID = AppsFlyerConfig.oneLinkTemplateID
        #if DEBUG
        appsFlyer.isDebug = true
        #endif

        appsFlyer.registerSessionReadyListener {
            AppsFlyerLib.shared().start()
        }
    }

    /// Short OneLink (e.g. saltrecipes.onelink.me/ked7/ab12cd34) whose parameters are stored
    /// by AppsFlyer. Nil if it couldn't be created in time; callers then use the long link.
    func shortLink(parameters: [String: String], campaign: String, timeout: Duration = .seconds(5)) async -> URL? {
        guard AppsFlyerConfig.isConfigured, !AppsFlyerConfig.oneLinkTemplateID.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            // Resumes once: with the link, or with nil on error or timeout
            let once = ResumeOnce(continuation)

            AppsFlyerShareInviteHelper.generateInviteLink(linkGenerator: { generator in
                generator.setCampaign(campaign)
                for (key, value) in parameters {
                    generator.addParameterValue(value, forKey: key)
                }
                return generator
            }, completionHandler: { url, error in
                if let error {
                    print("⚠️ AppsFlyer short link failed: \(error)")
                }
                once.resume(with: error == nil ? url : nil)
            })

            Task {
                try? await Task.sleep(for: timeout)
                once.resume(with: nil)
            }
        }
    }

    /// Universal links delivered as a user activity
    func handle(_ userActivity: NSUserActivity) {
        guard AppsFlyerConfig.isConfigured else { return }
        AppsFlyerLib.shared().continue(userActivity, restorationHandler: nil)
    }

    /// Any URL from SwiftUI's onOpenURL (universal links and URL schemes)
    func handle(_ url: URL) {
        guard AppsFlyerConfig.isConfigured else { return }
        AppsFlyerLib.shared().handleUniversalLink(url)
    }
}

/// Resumes a continuation only the first time, so a late callback after a timeout is ignored
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL?, Never>?

    init(_ continuation: CheckedContinuation<URL?, Never>) {
        self.continuation = continuation
    }

    func resume(with url: URL?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: url)
    }
}

// MARK: - Deep Linking

extension AppsFlyerManager: AppsFlyerDeepLinkDelegate {
    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard result.status == .found, let deepLink = result.deepLink else {
            if let error = result.error {
                print("⚠️ AppsFlyer deep link failed: \(error)")
            }
            return
        }

        guard deepLink.deeplinkValue == SharedRecipeRouter.deepLinkValue,
              let code = deepLink.clickEvent[SharedRecipeRouter.codeParameter] as? String else {
            return
        }

        Task { @MainActor in
            SharedRecipeRouter.shared.receive(code: code)
        }
    }
}
