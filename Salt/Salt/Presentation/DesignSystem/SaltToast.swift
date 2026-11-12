//
//  SaltToast.swift
//  Salt
//
//  The one-line toast used everywhere a recipe gets saved:
//  "Saved to My Recipes · Add to collection" (confirmation left, one next step right).
//  Shown above the tab bar by MainTabView, so it survives navigation.
//

import SwiftUI
import Combine

@MainActor
final class SaltToastCenter: ObservableObject {
    static let shared = SaltToastCenter()

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        /// Second, gray line (e.g. the Cooking mode toast)
        var detail: String?
        /// Orange icon instead of the success badge
        var systemImage: String?
        var showsCheck = true
        var actionTitle: String?
        var action: (() -> Void)?

        static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    @Published private(set) var current: Toast?
    /// Set by the saved toast's "Add to collection"; MainTabView presents the sheet
    @Published var collectionSheetRef: CollectionRecipeRef?

    private var hideTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String, detail: String? = nil, systemImage: String? = nil,
              showsCheck: Bool = true, actionTitle: String? = nil,
              duration: Duration = .seconds(5), action: (() -> Void)? = nil) {
        hideTask?.cancel()
        withAnimation(.spring(duration: 0.35)) {
            current = Toast(message: message, detail: detail, systemImage: systemImage,
                            showsCheck: showsCheck, actionTitle: actionTitle, action: action)
        }
        hideTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    /// "Saved to My Recipes · Add to collection"
    func showSaved(_ ref: CollectionRecipeRef?) {
        show(
            String(localized: "Saved to My Recipes"),
            actionTitle: ref == nil ? nil : String(localized: "Add to collection")
        ) { [weak self] in
            self?.collectionSheetRef = ref
        }
    }

    func dismiss() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { current = nil }
    }
}

/// The toast's look: white, thin border, success badge, orange text action.
struct SaltToastView: View {
    let toast: SaltToastCenter.Toast
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage = toast.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(SaltColor.iconAccent)
                    .frame(width: 28)
            } else if toast.showsCheck {
                SaltSuccessBadge(size: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.message)
                    .font(toast.detail == nil ? SaltFont.bodyLarge : SaltFont.bodyLargeStrong)
                    .foregroundStyle(SaltColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let detail = toast.detail {
                    Text(detail)
                        .font(SaltFont.body)
                        .foregroundStyle(SaltColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if let actionTitle = toast.actionTitle {
                // Never cut off: the message shrinks first
                Button(actionTitle, action: onAction)
                    .font(SaltFont.bodyLargeStrong)
                    .foregroundStyle(SaltColor.textAccent)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, toast.detail == nil ? 0 : 12)
        .frame(minHeight: 54)
        .background(SaltColor.surfaceScreen, in: RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SaltRadius.card, style: .continuous)
                .stroke(SaltColor.borderSubtle, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Hosts the shared toast at the bottom of a screen.
struct SaltToastHost: ViewModifier {
    @ObservedObject private var center = SaltToastCenter.shared
    var bottomPadding: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = center.current {
                SaltToastView(toast: toast) {
                    let action = toast.action
                    center.dismiss()
                    action?()
                }
                .padding(.horizontal, SaltSpacing.screenMargin)
                .padding(.bottom, bottomPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                    if value.translation.height > 0 { center.dismiss() }
                })
            }
        }
    }
}

extension View {
    /// Shows SaltToastCenter's toast; `bottomPadding` keeps it above the tab bar.
    func saltToastHost(bottomPadding: CGFloat = 8) -> some View {
        modifier(SaltToastHost(bottomPadding: bottomPadding))
    }
}

#Preview {
    SaltToastView(toast: .init(message: "Saved to My Recipes", actionTitle: "Add to collection"), onAction: {})
        .padding(18)
}
