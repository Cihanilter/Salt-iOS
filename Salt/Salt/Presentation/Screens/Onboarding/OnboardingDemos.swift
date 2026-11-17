//
//  OnboardingDemos.swift
//  Salt
//
//  The onboarding demo queue (Figma "Onboarding — Final"): up to 2 tap-to-share walkthroughs
//  picked from "Where do you find recipes?" (a social app, then websites in Safari), each
//  with a progress line and Skip, then straight on to Create account.
//

import SwiftUI

// MARK: - Demos

/// One demo in the onboarding queue
enum OnboardingDemo: String, Hashable, Identifiable {
    /// Instagram, TikTok and YouTube share one demo: the share sheet walkthrough
    case social
    /// Sharing a recipe page from Safari
    case website

    var id: String { rawValue }

    /// "Next: websites" on the screen before this demo
    var nextTitle: String {
        switch self {
        case .social: String(localized: "Next: social media")
        case .website: String(localized: "Next: websites")
        }
    }
}

/// "Instagram & TikTok · 1 of 3"
struct OnboardingDemoProgress: Equatable {
    let label: String
    /// 0-based
    let index: Int
    let total: Int
}

/// Label with "· 2 of 3" above one segment per demo; done segments are filled
struct OnboardingDemoProgressBar: View {
    let progress: OnboardingDemoProgress
    /// White on the mock app screens, dark on white pages
    var onDark = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(progress.label) · \(progress.index + 1) of \(progress.total)")
                .font(onDark ? SaltFont.bodyLargeStrong : SaltFont.body)
                .foregroundStyle(onDark ? Color.white : SaltColor.textSecondary)
                .shadow(color: onDark ? .black.opacity(0.35) : .clear, radius: 3)
            HStack(spacing: 6) {
                ForEach(0..<progress.total, id: \.self) { index in
                    Capsule()
                        .fill(index <= progress.index ? filled : empty)
                        .frame(height: 4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress.label), step \(progress.index + 1) of \(progress.total)")
    }

    private var filled: Color { onDark ? .white : SaltColor.textPrimary }
    private var empty: Color { onDark ? Color.white.opacity(0.45) : SaltColor.borderSubtle }
}

// MARK: - Source Row

/// Calm list row: white with a faint warm line and the app's logo (or a gray icon) in a
/// cream circle; selected = light peach row + gray ✓ in a white circle
struct OnboardingSourceRow: View {
    /// Brand logo for social apps; otherwise `systemImage`
    var logo: String? = nil
    let systemImage: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Group {
                    if let logo {
                        Image(logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 16))
                            .foregroundStyle(SaltColor.textSecondary)
                    }
                }
                .frame(width: 38, height: 38)
                .background(isSelected ? Color.white : SaltColor.surfaceWarmSubtle, in: Circle())

                Text(title)
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textPrimary)

                Spacer()

                ZStack {
                    if isSelected {
                        Circle().fill(Color.white)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SaltColor.textSecondary)
                    } else {
                        Circle().stroke(SaltColor.surfaceWarm, lineWidth: 1.5)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(isSelected ? SaltColor.surfaceWarm : Color.white, in: RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous)
                    .stroke(isSelected ? SaltColor.surfaceWarmStrong : SaltColor.surfaceWarm, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
