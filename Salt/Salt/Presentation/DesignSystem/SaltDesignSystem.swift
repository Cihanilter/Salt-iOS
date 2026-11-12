//
//  SaltDesignSystem.swift
//  Salt
//
//  Tokens and shared components from the "Salt Design System" Figma page.
//  Rules (DESIGN.md): one orange (#FF531E), peach = surfaces/selection,
//  pink = recipe content, no green, no Bold, spacing in steps of 4.
//

import SwiftUI

// MARK: - Colors

enum SaltColor {
    // Text
    static let textPrimary = Color(hex: 0x1A1A1A)
    static let textSecondary = Color(hex: 0x666666)
    static let textDisabled = Color(hex: 0xC5C5C6)
    static let textAccent = Color(hex: 0xFF531E)
    static let textOnAccent = Color.white
    static let textDestructive = Color(hex: 0xFF3B30)

    // Icons
    static let iconDefault = Color(hex: 0x1A1A1A)
    static let iconAccent = Color(hex: 0xFF531E)
    static let iconMeta = Color(hex: 0xEB5BAC)

    // Actions
    static let actionPrimary = Color(hex: 0xFF531E)

    // Surfaces
    static let surfaceScreen = Color.white
    static let surfaceWarmSubtle = Color(hex: 0xFFF7EC)
    static let surfaceWarm = Color(hex: 0xFFF0DA)
    static let surfaceWarmStrong = Color(hex: 0xFFE1CC)
    static let surfacePink = Color(hex: 0xF0E4EB)
    static let surfaceRecipeCard = Color(hex: 0xEFEDE1)
    static let surfaceControl = Color(hex: 0xEEEEEE)

    // Borders
    static let borderDefault = Color(hex: 0x666666)
    static let borderSubtle = Color(hex: 0xC5C5C6)

    // Brand (logo / splash only)
    static let brandGradient = LinearGradient(
        colors: [Color(hex: 0xFF5D1E), Color(hex: 0xFF8522)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Typography

enum SaltFont {
    private static let playfairRegular = "Playfair9pt-Regular"
    private static let playfairSemiBold = "Playfair9pt-SemiBold"
    private static let openSansRegular = "OpenSans-Regular"
    private static let openSansSemiBold = "OpenSans-SemiBold"

    // Headings (Playfair)
    static let h1 = Font.custom(playfairSemiBold, size: 28)
    static let h2 = Font.custom(playfairSemiBold, size: 22)
    static let h3 = Font.custom(playfairSemiBold, size: 18)
    static let labelControl = Font.custom(playfairRegular, size: 22)
    static let labelMeta = Font.custom(playfairRegular, size: 16)

    // Body (Open Sans)
    static let bodyLarge = Font.custom(openSansRegular, size: 16)
    static let bodyLargeStrong = Font.custom(openSansSemiBold, size: 16)
    static let body = Font.custom(openSansRegular, size: 14)
    static let bodyStrong = Font.custom(openSansSemiBold, size: 14)
    static let caption = Font.custom(openSansRegular, size: 13)
    static let captionStrong = Font.custom(openSansSemiBold, size: 13)

    static let button = Font.custom(openSansSemiBold, size: 18)
    static let buttonSmall = Font.custom(openSansSemiBold, size: 16)
    static let tabLabel = Font.custom(openSansRegular, size: 11)

    // Numbers (Open Sans; Playfair numerals only on recipe meta and time circles)
    static let numberMedium = Font.custom(openSansSemiBold, size: 20)
    static let numberLarge = Font.custom(openSansRegular, size: 24)
    static let numberXLarge = Font.custom(openSansRegular, size: 28)
    static let avatarLabel = Font.custom(openSansSemiBold, size: 10)

    static func playfair(_ size: CGFloat, semibold: Bool = false) -> Font {
        .custom(semibold ? playfairSemiBold : playfairRegular, size: size)
    }

    static func openSans(_ size: CGFloat, semibold: Bool = false) -> Font {
        .custom(semibold ? openSansSemiBold : openSansRegular, size: size)
    }
}

// MARK: - Spacing

enum SaltSpacing {
    static let screenMargin: CGFloat = 18
    static let section: CGFloat = 32
    static let header: CGFloat = 16
    static let titleToContent: CGFloat = 12
    static let topPadding: CGFloat = 56
    static let bottomTabPadding: CGFloat = 120
    static let inputVertical: CGFloat = 12
}

enum SaltRadius {
    static let recipeImage: CGFloat = 25
    static let buttonLarge: CGFloat = 14
    static let buttonSmall: CGFloat = 10
    static let input: CGFloat = 12
    static let card: CGFloat = 16
    static let sheet: CGFloat = 24
    static let titleCard: CGFloat = 14
}

// MARK: - Button

enum SaltButtonVariant {
    case primary, secondary, text, outline
}

enum SaltButtonSize {
    case large, small
}

/// Button/Default from the design system. Large = 53pt, radius 14, SemiBold 18.
/// Small = 38pt, radius 10, SemiBold 16. Never pill-shaped, never gray.
struct SaltButtonStyle: ButtonStyle {
    var variant: SaltButtonVariant = .primary
    var size: SaltButtonSize = .large
    var fullWidth: Bool = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size == .large ? SaltFont.button : SaltFont.buttonSmall)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, variant == .text ? 0 : (size == .large ? 20 : 16))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: variant == .text ? nil : (size == .large ? 53 : 38))
            .frame(minHeight: 44)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if variant == .outline {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(SaltColor.borderDefault, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }

    private var radius: CGFloat {
        size == .large ? SaltRadius.buttonLarge : SaltRadius.buttonSmall
    }

    private var foreground: Color {
        guard isEnabled else { return SaltColor.textDisabled }
        switch variant {
        case .primary: return SaltColor.textOnAccent
        case .secondary, .outline: return SaltColor.textPrimary
        case .text: return SaltColor.textAccent
        }
    }

    @ViewBuilder private var background: some View {
        switch variant {
        case .primary:
            isEnabled ? SaltColor.actionPrimary : SaltColor.surfaceControl
        case .secondary:
            SaltColor.surfaceWarmStrong
        case .outline:
            SaltColor.surfaceScreen
        case .text:
            Color.clear
        }
    }
}

extension ButtonStyle where Self == SaltButtonStyle {
    static func salt(
        _ variant: SaltButtonVariant = .primary,
        size: SaltButtonSize = .large,
        fullWidth: Bool? = nil
    ) -> SaltButtonStyle {
        // Large buttons are a screen's main action (full width); small ones hug their text.
        SaltButtonStyle(variant: variant, size: size, fullWidth: fullWidth ?? (size == .large && variant != .text))
    }
}

/// Primary button label with a spinner, for "Importing…" style busy states.
struct SaltButtonLabel: View {
    let title: String
    var systemImage: String?
    var isLoading = false

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .tint(.white)
                    .controlSize(.small)
            } else if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
    }
}

// MARK: - Chip

/// Default: white, 1px border, gray text. Selected: surface/warm + ✓.
struct SaltChip: View {
    let title: String
    var isSelected = false
    var showsCheck = true
    var showsChevron = false
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: 6) {
            if isSelected && showsCheck {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SaltColor.textPrimary)
            }
            Text(title)
                .font(SaltFont.body)
                .foregroundStyle(isSelected ? SaltColor.textPrimary : SaltColor.textSecondary)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? SaltColor.textPrimary : SaltColor.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(isSelected ? SaltColor.surfaceWarm : SaltColor.surfaceScreen, in: Capsule())
        .overlay {
            if !isSelected {
                Capsule().stroke(SaltColor.borderSubtle, lineWidth: 1)
            }
        }
        .contentShape(Capsule())
    }
}

// MARK: - Input

/// Radius 12, 1px border/default; focused = dark border; error = red border.
struct SaltInputBorder: ViewModifier {
    var isFocused = false
    var hasError = false
    var radius: CGFloat = SaltRadius.input

    func body(content: Content) -> some View {
        content
            .font(SaltFont.bodyLarge)
            .foregroundStyle(SaltColor.textPrimary)
            .tint(SaltColor.actionPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, SaltSpacing.inputVertical)
            .background(SaltColor.surfaceScreen, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    private var borderColor: Color {
        if hasError { return SaltColor.textDestructive }
        if isFocused { return SaltColor.textPrimary }
        return SaltColor.borderDefault
    }
}

extension View {
    func saltInput(isFocused: Bool = false, hasError: Bool = false) -> some View {
        modifier(SaltInputBorder(isFocused: isFocused, hasError: hasError))
    }
}

/// One-line error under a field: small warning icon + calm text.
struct SaltFieldError: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(SaltColor.textDestructive)
            Text(message)
                .font(SaltFont.caption)
                .foregroundStyle(SaltColor.textSecondary)
        }
    }
}

// MARK: - Segmented control

/// Page tabs (All / Imports / Saved): Playfair labels on surface/warm, white selected pill.
struct SaltPageTabs<Tab: Hashable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = tab }
                } label: {
                    Text(title(tab))
                        .font(SaltFont.playfair(22))
                        .foregroundStyle(SaltColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(SaltColor.surfaceScreen)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(SaltColor.surfaceWarm, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Small toggles (Imperial / Metric) on surface/control with Open Sans labels.
struct SaltSmallToggle<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(SaltFont.body)
                        .foregroundStyle(SaltColor.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(SaltColor.surfaceScreen)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(SaltColor.surfaceControl, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Stepper

/// No container; 30px surface/pink circles with − / + and the value between.
/// The visible circles are 30pt but the tap area is 44pt.
struct SaltStepper: View {
    let label: String
    var canDecrement = true
    var canIncrement = true
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            key("minus", enabled: canDecrement, label: "Fewer", action: onDecrement)
            Text(label)
                .font(SaltFont.bodyLarge)
                .foregroundStyle(SaltColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            key("plus", enabled: canIncrement, label: "More", action: onIncrement)
        }
    }

    private func key(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? SaltColor.textPrimary : SaltColor.textDisabled)
                .frame(width: 30, height: 30)
                .background(SaltColor.surfacePink, in: Circle())
                // 52pt tap area that still takes 44pt in the layout, so nothing moves
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
                .padding(-4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Badges

/// Success = orange ✓ on a surface/warm-strong circle (no green).
struct SaltSuccessBadge: View {
    var size: CGFloat = 28
    var isDone = true

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(isDone ? SaltColor.iconAccent : SaltColor.textDisabled)
            .frame(width: size, height: size)
            .background(isDone ? SaltColor.surfaceWarmStrong : SaltColor.surfaceControl, in: Circle())
    }
}

/// Small "Premium" badge used on Profile and Premium sheets.
struct SaltPremiumBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 10))
            Text("Premium")
                .font(SaltFont.captionStrong)
        }
        .foregroundStyle(SaltColor.textAccent)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(SaltColor.surfaceWarmStrong, in: Capsule())
    }
}

// MARK: - Avatar

/// Avatar without photo = pink circle with initials.
struct SaltAvatar: View {
    let name: String
    var imageURL: URL?
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(SaltColor.surfacePink)
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsView
                }
                .clipShape(Circle())
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
    }

    private var initialsView: some View {
        Text(Self.initials(from: name))
            .font(size >= 40 ? SaltFont.openSans(size * 0.4, semibold: true) : SaltFont.avatarLabel)
            .foregroundStyle(SaltColor.textPrimary)
    }

    static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}

/// Overlapping stack of member avatars (replaces the orange "Shared" label).
struct SaltAvatarStack: View {
    let names: [String]
    var size: CGFloat = 18
    var maxVisible = 3

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(names.prefix(maxVisible).enumerated()), id: \.offset) { _, name in
                SaltAvatar(name: name, size: size)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            }
        }
    }
}

// MARK: - Empty state

/// Lightest-peach circle with a gray icon + Playfair title + one Large Primary button.
struct SaltEmptyState: View {
    let systemImage: String
    let title: String
    var message: String?
    var buttonTitle: String?
    var action: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(SaltColor.textSecondary)
                .frame(width: 88, height: 88)
                .background(SaltColor.surfaceWarmSubtle, in: Circle())
                .padding(.bottom, 20)

            Text(title)
                .font(SaltFont.h2)
                .foregroundStyle(SaltColor.textPrimary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(SaltFont.body)
                    .foregroundStyle(SaltColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.salt())
                    .padding(.top, 24)
            }

            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.salt(.text, size: .small))
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sheet header

/// Filter / form sheet header: Playfair title with an optional trailing link (Reset, Cancel…).
struct SaltSheetHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(SaltFont.h2)
                .foregroundStyle(SaltColor.textPrimary)
            Spacer()
            trailing()
        }
    }
}

extension SaltSheetHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}

// MARK: - Skeleton

/// Skeleton loaders in surface/control.
struct SaltSkeleton: View {
    var cornerRadius: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(SaltColor.surfaceControl)
            .opacity(pulse ? 0.55 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Glass circle button

/// Top-bar circle button (back, …, bookmark) on the recipe hero.
struct SaltGlassCircle<Content: View>: View {
    var isActive = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: 40, height: 40)
            .background {
                if isActive {
                    Circle().fill(SaltColor.surfaceWarmStrong)
                } else {
                    Circle().fill(Color.white.opacity(0.92))
                }
            }
            .contentShape(Circle())
    }
}

/// Bookmark over a photo (Figma): 34pt circle, black at 32% over an 8pt backdrop blur.
/// Saved = orange filled bookmark; otherwise a white outline.
struct SaltBookmarkCircle: View {
    let isBookmarked: Bool

    static let size: CGFloat = 34

    var body: some View {
        // Drawn rather than the SF Symbol, which is taller and narrower than the Figma icon
        Group {
            if isBookmarked {
                BookmarkGlyph().fill(SaltColor.iconAccent)
            } else {
                BookmarkGlyph().stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
        }
        // Figma: a 10.5 x 13.5 vector centered in an 18pt icon (3.75 / 2.25 in)
        .frame(width: 10.5, height: 13.5)
        .frame(width: 18, height: 18)
        .frame(width: Self.size, height: Self.size)
        .background {
            ZStack {
                // ~ backdrop-filter: blur(8px)
                Circle().fill(.ultraThinMaterial)
                // #00000052
                Circle().fill(Color.black.opacity(0x52 / 255.0))
            }
            .environment(\.colorScheme, .dark)
        }
        .clipShape(Circle())
    }
}

/// Bookmark ribbon: rounded top, notch at the bottom
struct BookmarkGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius), radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.28))
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

#Preview("Buttons") {
    VStack(spacing: 12) {
        Button("Save recipe") {}.buttonStyle(.salt())
        Button("Paste as text instead") {}.buttonStyle(.salt(.secondary))
        Button("Edit profile") {}.buttonStyle(.salt(.outline, size: .small))
        Button("See all") {}.buttonStyle(.salt(.text, size: .small))
        Button("Disabled") {}.buttonStyle(.salt()).disabled(true)
        HStack {
            SaltChip(title: "Italian")
            SaltChip(title: "Italian", isSelected: true)
        }
        SaltStepper(label: "4 servings", onDecrement: {}, onIncrement: {})
        SaltEmptyState(systemImage: "book", title: "No recipes yet", buttonTitle: "Add your first recipe", action: {})
    }
    .padding(18)
}
