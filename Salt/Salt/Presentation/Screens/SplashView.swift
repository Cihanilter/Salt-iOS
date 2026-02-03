//
//  SplashView.swift
//  Salt
//
//  Splash screen matching LaunchScreen.storyboard
//

import SwiftUI

struct SplashView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background color to fill any gaps
                Color("MangoColor")

                // Gradient background image (full screen)
                Image("gradientIcon")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // Center logo - absolute center of screen (matching LaunchScreen)
                Image("large_icon")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 176, height: 192)
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    SplashView()
}
