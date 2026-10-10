//
//  MainTabView.swift
//  Salt
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var exploreScrollToTop = UUID()
    @ObservedObject private var shareImportRouter = ShareImportRouter.shared
    @ObservedObject private var sharedRecipeRouter = SharedRecipeRouter.shared
    @ObservedObject private var collectionInviteRouter = CollectionInviteRouter.shared

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
                ExploreRecipesView(scrollToTopTrigger: exploreScrollToTop)
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
                AddNewRecipeView(switchToMyRecipes: { selectedTab = 2 })
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
        }
        .onChange(of: shareImportRouter.pendingUrl) { _, url in
            // Link shared from the Share Extension - go to Add Recipe to import it
            if url != nil {
                selectedTab = 1
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

/// Code of a recipe share link or collection invite, as the item of its screen
private struct LinkCode: Identifiable {
    let id: String
}

#Preview {
    MainTabView()
}
