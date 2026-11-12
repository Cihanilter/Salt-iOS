//
//  ImportProgressView.swift
//  Salt
//

import SwiftUI

// MARK: - Import Progress

/// What's being imported, so the loading screen can show it
enum ImportProgressKind {
    case link
    case photos([UIImage])
    case note
}

/// Full-screen loading screen shown while a recipe is imported from a link, photos or a note
struct ImportProgressView: View {
    let kind: ImportProgressKind
    /// Nil hides Cancel (the import walkthroughs, which move on by themselves)
    let onCancel: (() -> Void)?

    @State private var messageIndex = 0
    @State private var showsSlowHint = false

    /// Status lines shown one after another; the last one stays until the import ends
    private var messages: [String] {
        let first: String
        switch kind {
        case .link: first = "Reading the recipe..."
        case .photos(let photos): first = photos.count > 1 ? "Reading your photos..." : "Reading your photo..."
        case .note: first = "Reading your note..."
        }
        return [first, "Gathering the ingredients...", "Writing out the steps...", "Almost ready..."]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundColor(Color("GraniteGray"))
                }
            }
            .frame(minHeight: 22)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            BreathingLogo()
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Importing your recipe")
                    .font(.custom("Playfair9pt-SemiBold", size: 26))

                Text(messages[messageIndex])
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundColor(Color("GraniteGray"))
                    .id(messageIndex)
                    .transition(.opacity)

                // Videos can take up to a minute when the recipe is read from what's said in them
                Text("Some recipes take up to a minute.")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundColor(Color("DarkSilver"))
                    .opacity(showsSlowHint ? 1 : 0)
                    .padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.top, 32)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task {
            // Step through the status lines while the import runs
            while messageIndex < messages.count - 1 {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut) { messageIndex += 1 }
            }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut) { showsSlowHint = true }
        }
    }
}

// MARK: - Breathing Logo

/// The Salt logo growing and shrinking slightly, like it's breathing
private struct BreathingLogo: View {
    @State private var isBreathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image("saltAppIcon")
            .resizable()
            .scaledToFit()
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .shadow(color: Color("Orange").opacity(isBreathing ? 0.35 : 0.1), radius: isBreathing ? 24 : 8)
            .scaleEffect(isBreathing ? 1.06 : 0.96)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
    }
}

// MARK: - Preview

#Preview("Link") {
    ImportProgressView(kind: .link, onCancel: {})
}
