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
        #if DEBUG
        appsFlyer.isDebug = true
        #endif

        appsFlyer.registerSessionReadyListener {
            AppsFlyerLib.shared().start()
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
