//
//  RootView.swift
//  Salt
//

import SwiftUI

struct RootView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var showSplash = true

    var body: some View {
        ZStack {
            // Main content
            Group {
                if authManager.isLoading {
                    // Show loading screen while checking auth state
                    SplashView()
                } else if authManager.isAuthenticated {
                    // User is authenticated, show main app
                    MainTabView()
                } else {
                    // User is not authenticated, show auth flow
                    AuthCoordinatorView()
                }
            }

            // Splash overlay (shows for ~1 second after launch)
            if showSplash {
                SplashView()
//                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            // Keep splash visible for 1 second, then fade out
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showSplash = false
                }
            }
        }
    }
}

#Preview {
    RootView()
}
