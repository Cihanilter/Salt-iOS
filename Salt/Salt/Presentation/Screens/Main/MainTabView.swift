//
//  MainTabView.swift
//  Salt
//

import SwiftUI
import RevenueCat
import RevenueCatUI

struct MainTabView: View {
    @State private var selectedTab = 0
    /// Page to show on the Add Recipe tab when switching to it (Create or Import)
    @State private var addRecipeTabRequest: AddRecipeTab?
    @State private var exploreScrollToTop = UUID()
    @ObservedObject private var shareImportRouter = ShareImportRouter.shared
    @ObservedObject private var sharedRecipeRouter = SharedRecipeRouter.shared
    @ObservedObject private var collectionInviteRouter = CollectionInviteRouter.shared
    @ObservedObject private var authManager = AuthManager.shared
    /// Paywall shown at launch (see LaunchPaywall); nil when it isn't showing
    @State private var launchPaywallTrigger: LaunchPaywall.Trigger?
    /// Salt was opened to do something (a shared link, recipe or invite); no paywall in the way
    @State private var openedFromLink = false
    @Environment(\.scenePhase) private var scenePhase

    /// Collection invite opened from a link; closing the screen clears the link
    private var collectionInviteCode: Binding<LinkCode?> {
        Binding(
            get: { collectionInviteRouter.pendingCode.map(LinkCode.init) },
            set: { if $0 == nil { collectionInviteRouter.clear() } }
        )
    }

    /// Recipe opened from a share link; closing the screen clears the link
    private var sharedRecipeCode: Binding<LinkCode?> {
        Binding(
            get: { sharedRecipeRouter.pendingCode.map(LinkCode.init) },
            set: { if $0 == nil { sharedRecipeRouter.clear() } }
        )
    }

    // Custom binding to detect same-tab taps
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab && newValue == 0 {
                    // Tapped Explore while already on Explore - trigger scroll to top
                    exploreScrollToTop = UUID()
                }
                selectedTab = newValue
            }
        )
    }

    init() {
        // Configure tab bar appearance for iOS 18 compatibility
        if #unavailable(iOS 26.0) {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .systemBackground
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    var body: some View {
        TabView(selection: tabSelection) {
            // Explore Tab
            NavigationStack {
                ExploreRecipesView(
                    scrollToTopTrigger: exploreScrollToTop,
                    switchToAddRecipe: {
                        // Paste a link: the Import page, even if Create was open last
                        addRecipeTabRequest = .import
                        selectedTab = 1
                    },
                    openCreateRecipe: {
                        addRecipeTabRequest = .create
                        selectedTab = 1
                    }
                )
                    .navigationBarHidden(true)
            }
            .tabItem {
                Image("search_icon")
                    .renderingMode(.template)
                Text("Explore")
                    .font(.custom("OpenSans-Regular", size: 10))
            }
            .tag(0)

            // Add Recipe Tab
            NavigationStack {
                AddNewRecipeView(requestedTab: $addRecipeTabRequest, switchToMyRecipes: { selectedTab = 2 })
                    .navigationBarHidden(true)
            }
            .tabItem {
                Image("addIcon")
                    .renderingMode(.template)
                Text("Add Recipe")
                    .font(.custom("OpenSans-Regular", size: 10))
            }
            .tag(1)

            // My Recipes Tab
            MyRecipesView(switchToAddRecipe: { selectedTab = 1 })
                .tabItem {
                    Image("menuIcon")
                        .renderingMode(.template)
                    Text("My Recipes")
                        .font(.custom("OpenSans-Regular", size: 10))
                }
                .tag(2)

            // Profile Tab
            ProfileView()
                .tabItem {
                    Image("accountIcon")
                        .renderingMode(.template)
                    Text("Profile")
                        .font(.custom("OpenSans-Regular", size: 10))
                }
                .tag(3)
        }
        .accentColor(Color("OrangeRed"))
        .onAppear {
            // Link shared before the tabs existed (cold launch or while logged out)
            if shareImportRouter.pendingUrl != nil {
                selectedTab = 1
            }
            if shareImportRouter.pendingUrl != nil || sharedRecipeRouter.pendingCode != nil
                || collectionInviteRouter.pendingCode != nil {
                openedFromLink = true
            }
        }
        .onChange(of: shareImportRouter.pendingUrl) { _, url in
            // Link shared from the Share Extension - go to Add Recipe to import it
            if url != nil {
                selectedTab = 1
                openedFromLink = true
            }
        }
        .onChange(of: sharedRecipeRouter.pendingCode) { _, code in
            if code != nil { openedFromLink = true }
        }
        .onChange(of: collectionInviteRouter.pendingCode) { _, code in
            if code != nil { openedFromLink = true }
        }
        .task {
            await showLaunchPaywallIfNeeded()
        }
        // iOS often keeps Salt suspended for days, so coming back counts as a launch too
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // A new visit starts; a link that opens Salt sets this again
                openedFromLink = false
            case .active where launchPaywallTrigger == nil:
                Task { await showLaunchPaywallIfNeeded() }
            default:
                break
            }
        }
        // On a background view: MainTabView already has a full-screen cover for shared recipes
        .background {
            Color.clear.fullScreenCover(item: $launchPaywallTrigger) { trigger in
                // Remote paywall: shows whatever is attached to the current offering in the RevenueCat dashboard
                PaywallView(displayCloseButton: true)
                    .onAppear {
                        Analytics.log(.paywallShown, ["source": "launch", "trigger": trigger.rawValue])
                    }
                    .onPurchaseCompleted { customerInfo in
                        Analytics.log(.subscriptionStarted, ["source": "launch", "trigger": trigger.rawValue])
                        closeLaunchPaywallIfPremium(customerInfo)
                    }
                    .onRestoreCompleted { customerInfo in
                        Analytics.log(.purchasesRestored, ["source": "launch", "trigger": trigger.rawValue])
                        closeLaunchPaywallIfPremium(customerInfo)
                    }
            }
        }
        .onChange(of: selectedTab, initial: true) { _, tab in
            Analytics.screen(["Explore", "Add Recipe", "My Recipes", "Profile"][tab])
        }
        .fullScreenCover(item: sharedRecipeCode) { sharedCode in
            SharedRecipeView(
                code: sharedCode.id,
                onAddMoreRecipes: {
                    sharedRecipeRouter.clear()
                    selectedTab = 1
                },
                onGoToMyRecipes: {
                    sharedRecipeRouter.clear()
                    selectedTab = 2
                }
            )
        }
        .sheet(item: collectionInviteCode) { invite in
            CollectionInviteView(code: invite.id) {
                collectionInviteRouter.clear()
                selectedTab = 2
            }
        }
        .task {
            // Prefetch My Recipes data in background while user is on Explore
            await MyRecipesViewModel.shared.prefetch()
        }
    }
}

// MARK: - Launch Paywall

extension MainTabView {
    /// Right after signing up, then every other day for free users (LaunchPaywall)
    private func showLaunchPaywallIfNeeded() async {
        guard let user = authManager.currentUser else { return }
        // Shared links and deep links (AppsFlyer resolves them asynchronously) arrive just
        // after launch; give them a moment so the paywall doesn't cover what the user came for
        try? await Task.sleep(for: .seconds(1.5))
        guard !openedFromLink, let trigger = await LaunchPaywall.trigger(for: user),
              !openedFromLink, authManager.currentUser?.id == user.id else { return }
        LaunchPaywall.markShown(for: user)
        launchPaywallTrigger = trigger
    }

    /// A restore without an active subscription leaves the paywall open
    private func closeLaunchPaywallIfPremium(_ customerInfo: CustomerInfo) {
        SubscriptionManager.shared.update(with: customerInfo)
        if SubscriptionManager.shared.isPremium {
            launchPaywallTrigger = nil
        }
    }
}

extension LaunchPaywall.Trigger: Identifiable {
    var id: Self { self }
}

/// Code of a recipe share link or collection invite, as the item of its screen
private struct LinkCode: Identifiable {
    let id: String
}

#Preview {
    MainTabView()
}
