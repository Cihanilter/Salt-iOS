//
//  PremiumFeatureSheet.swift
//  Salt
//
//  Premium sheet template (decision log): no icon; Premium badge, Playfair title,
//  two short lines, "Try Premium free" (opens the RevenueCat paywall) and "Not now".
//  Used for the import limit and Cooking mode; other Premium features can reuse it.
//

import SwiftUI

struct PremiumFeatureSheet: View {
    let title: String
    let message: String
    let onTryPremium: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SaltPremiumBadge()
                .padding(.bottom, 16)

            Text(title)
                .font(SaltFont.h2)
                .foregroundStyle(SaltColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            Text(message)
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            Button("Try Premium free", action: onTryPremium)
                .buttonStyle(.salt())

            Button("Not now", action: onNotNow)
                .buttonStyle(.salt(.text))
                .padding(.top, 8)
        }
        .padding(.horizontal, SaltSpacing.screenMargin)
        .padding(.top, 32)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(SaltRadius.sheet)
        .presentationBackground(SaltColor.surfaceScreen)
    }
}

#Preview {
    Color.gray.sheet(isPresented: .constant(true)) {
        PremiumFeatureSheet(
            title: "You've used your 3 free imports",
            message: "Go Premium for unlimited imports.\nYour link is saved.",
            onTryPremium: {},
            onNotNow: {}
        )
    }
}
