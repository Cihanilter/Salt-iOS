//
//  OnboardingDemos.swift
//  Salt
//
//  The onboarding demo queue (Figma "Onboarding — Final"): up to 3 short demos picked from
//  "Where do you find recipes?" (social share sheet, a sample link, a sample photo), each
//  with a progress line and Skip, then straight on to Create account.
//

import SwiftUI

// MARK: - Demos

/// One demo in the onboarding queue
enum OnboardingDemo: String, Hashable, Identifiable {
    /// Instagram, TikTok and YouTube share one demo: the share sheet walkthrough
    case social
    case website
    /// Cookbooks and handwritten cards share the photo demo
    case photo

    var id: String { rawValue }

    /// "Next: websites" on the screen before this demo
    var nextTitle: String {
        switch self {
        case .social: String(localized: "Next: social media")
        case .website: String(localized: "Next: websites")
        case .photo: String(localized: "Next: cookbooks")
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

// MARK: - Sample Link / Photo Demo

/// One-screen demo: what it does, an illustration, and "Try it with a sample link/photo",
/// which plays the transformation and moves on
struct OnboardingSampleDemoView: View {
    let demo: OnboardingDemo
    /// Nil when replayed outside onboarding (no progress line)
    let progress: OnboardingDemoProgress?
    let onDone: () -> Void
    let onSkip: () -> Void

    @State private var phase: Phase = .ready
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase { case ready, reading, saved }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                if let progress {
                    OnboardingDemoProgressBar(progress: progress)
                        .frame(maxWidth: .infinity)
                }
                Spacer(minLength: 16)
                Button("Skip", action: onSkip)
                    .font(SaltFont.bodyLarge)
                    .foregroundStyle(SaltColor.textSecondary)
                    .disabled(phase != .ready)
            }
            .padding(.top, 8)

            Text(title)
                .font(SaltFont.h1)
                .foregroundStyle(SaltColor.textPrimary)
                .padding(.top, 40)

            Text(message)
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            illustration
                .padding(.top, 24)

            Spacer(minLength: 16)

            Button(action: tryIt) {
                SaltButtonLabel(title: buttonTitle, isLoading: phase == .reading)
            }
            .buttonStyle(.salt())
            .allowsHitTesting(phase == .ready)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, SaltSpacing.screenMargin)
        .background(SaltColor.surfaceScreen.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: phase == .saved)
    }

    private var title: String {
        demo == .website ? String(localized: "Got a recipe link?") : String(localized: "Snap a page")
    }

    private var message: String {
        demo == .website
            ? String(localized: "Copy the link from any site. Salt keeps the recipe and leaves out the ads and life stories.")
            : String(localized: "Take a photo of a cookbook page or a handwritten card. Salt types it out for you.")
    }

    private var buttonTitle: String {
        switch phase {
        case .ready: demo == .website ? String(localized: "Try it with a sample link") : String(localized: "Try it with a sample photo")
        case .reading: demo == .website ? String(localized: "Reading the page…") : String(localized: "Reading the photo…")
        case .saved: String(localized: "Saved to My Recipes")
        }
    }

    // MARK: Illustration

    private var illustration: some View {
        VStack(spacing: 16) {
            source
                .opacity(phase == .saved ? 0.5 : 1)

            Image(systemName: "arrow.down")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(SaltColor.iconAccent)
                .symbolEffect(.bounce, value: phase == .reading)

            ZStack(alignment: .topTrailing) {
                RecipeInfoCard(
                    title: demo == .website ? "Lemon Layer Cake" : "Grandma\u{2019}s Meatballs",
                    duration: "35 min",
                    ingredientsCount: "6 ingredients",
                    sourceUrl: demo == .website ? "https://lemonblog.com/lemon-layer-cake" : nil
                )
                .allowsHitTesting(false)
                .scaleEffect(phase == .ready ? 0.96 : 1)

                if phase == .saved {
                    SaltSuccessBadge(size: 30)
                        .offset(x: 8, y: -10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(SaltColor.surfaceWarmSubtle, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder private var source: some View {
        if demo == .website {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                    Text("lemonblog.com/lemon-layer-cake")
                        .font(SaltFont.body)
                        .lineLimit(1)
                }
                .foregroundStyle(SaltColor.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SaltColor.surfaceControl, in: RoundedRectangle(cornerRadius: 8))
                ForEach([1.0, 0.7, 0.85, 0.5], id: \.self) { width in
                    Capsule().fill(SaltColor.surfaceControl)
                        .frame(height: 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: width, anchor: .leading)
                }
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(SaltColor.borderSubtle, lineWidth: 1))
            .padding(.horizontal, 44)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Grandma\u{2019}s Meatballs")
                    .font(SaltFont.h3)
                    .foregroundStyle(SaltColor.textPrimary)
                ForEach([0.9, 0.7, 0.85, 0.5, 0.75], id: \.self) { width in
                    Capsule().fill(SaltColor.borderSubtle)
                        .frame(height: 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: width, anchor: .leading)
                }
            }
            .padding(18)
            .background(Color(hex: 0xFFFDF8), in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            .rotationEffect(.degrees(2))
            .padding(.horizontal, 64)
        }
    }

    /// Plays the sample import: reading, then saved, then on to the next demo
    private func tryIt() {
        withAnimation(.easeInOut(duration: 0.25)) { phase = .reading }
        Task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.8 : 1.6))
            withAnimation(.spring(duration: 0.4)) { phase = .saved }
            try? await Task.sleep(for: .seconds(1.1))
            onDone()
        }
    }
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

// MARK: - Previews

#Preview("Website demo") {
    OnboardingSampleDemoView(demo: .website, progress: .init(label: "Websites & food blogs", index: 1, total: 3), onDone: {}, onSkip: {})
}
