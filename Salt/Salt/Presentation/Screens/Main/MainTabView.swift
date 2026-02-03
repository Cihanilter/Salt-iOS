//
//  MainTabView.swift
//  Salt
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var exploreScrollToTop = UUID()

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
        .task {
            // Prefetch My Recipes data in background while user is on Explore
            await MyRecipesViewModel.shared.prefetch()
        }
    }
}

#Preview {
    MainTabView()
}
