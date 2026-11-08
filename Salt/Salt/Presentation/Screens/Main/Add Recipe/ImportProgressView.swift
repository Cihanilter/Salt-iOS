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

/// Full-screen loading screen shown while a recipe is imported from a link, photos or a note:
/// ingredients tumbling into a pan, with a pinch of salt
struct ImportProgressView: View {
    let kind: ImportProgressKind
    let onCancel: () -> Void

    @State private var messageIndex = 0
    @State private var showsSlowHint = false

    /// Status lines shown one after another; the last one stays until the import ends
    private var messages: [String] {
        let first: String
        switch kind {
        case .link: first = "Peeking at the recipe..."
        case .photos(let photos): first = photos.count > 1 ? "Reading your photos..." : "Reading your photo..."
        case .note: first = "Reading your note..."
        }
        return [
            first,
            "Gathering the ingredients...",
            "Measuring everything out...",
            "Putting the steps in order...",
            "Adding a pinch of salt...",
            "Plating it up..."
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundColor(Color("GraniteGray"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            ZStack(alignment: .bottomLeading) {
                CookingPanView()
                    .frame(width: 280, height: 280)

                // The photos being read, like a recipe card propped up on the counter
                if case .photos(let photos) = kind {
                    PhotoCardStack(photos: photos)
                        .offset(x: -36, y: 8)
                }
            }

            VStack(spacing: 10) {
                Text("Cooking up your recipe")
                    .font(.custom("Playfair9pt-SemiBold", size: 28))

                Text(messages[messageIndex])
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundColor(Color("GraniteGray"))
                    .id(messageIndex)
                    .transition(.opacity)

                // Videos can take up to a minute when the recipe is read from what's said in them
                Text("Good things take time. Some recipes need up to a minute.")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundColor(Color("DarkSilver"))
                    .opacity(showsSlowHint ? 1 : 0)
                    .padding(.top, 6)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.top, 24)

            Spacer()

            Label("You can check and edit everything before saving", systemImage: "checkmark.circle")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundColor(Color("GraniteGray"))
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            // Warm kitchen light from the top
            LinearGradient(
                colors: [Color("PeachCream"), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .task {
            // Step through the status lines while the import runs
            while messageIndex < messages.count - 1 {
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut) { messageIndex += 1 }
            }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut) { showsSlowHint = true }
        }
    }
}

// MARK: - Cooking Pan

/// A pan rocking on the stove while ingredients tumble in one after another,
/// with steam rising and a pinch of salt falling
private struct CookingPanView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let ingredients: [(symbol: String, color: Color)] = [
        ("carrot.fill", Color("Orange")),
        ("leaf.fill", Color(red: 0.42, green: 0.62, blue: 0.33)),
        ("fish.fill", Color("OrangeRed")),
        ("drop.fill", Color(red: 0.85, green: 0.68, blue: 0.20))
    ]
    /// Seconds for one ingredient to fall into the pan
    private static let dropDuration = 1.3

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            // A still frame mid-drop when motion is reduced
            scene(time: reduceMotion ? 0.7 : context.date.timeIntervalSinceReferenceDate)
        }
        .accessibilityHidden(true)
    }

    private func scene(time: Double) -> some View {
        let cycle = time / Self.dropDuration
        let ingredient = Self.ingredients[Int(cycle.truncatingRemainder(dividingBy: Double(Self.ingredients.count)))]
        // 0 when the ingredient appears, 1 when it lands
        let progress = cycle - cycle.rounded(.down)
        // Ingredients come in from alternating sides
        let side: CGFloat = Int(cycle).isMultiple(of: 2) ? -1 : 1
        // The pan dips a little as each one lands
        let landing = max(0, 1 - abs(progress - 0.92) / 0.08)

        return ZStack {
            ForEach(0..<3, id: \.self) { index in
                SteamWisp(time: time, index: index)
            }

            SaltPinch(time: time)

            Image(systemName: ingredient.symbol)
                .font(.system(size: 34))
                .foregroundStyle(ingredient.color)
                .rotationEffect(.degrees(Double(side) * 200 * progress))
                .scaleEffect(1 - 0.35 * progress)
                // Falls along a curve, speeding up like it's dropped
                .offset(x: side * 80 * (1 - progress), y: -130 + 160 * progress * progress)
                .opacity(progress < 0.85 ? 1 : (1 - progress) / 0.15)

            // The stove's flame, flickering under the pan
            Image(systemName: "flame.fill")
                .font(.system(size: 30))
                .foregroundStyle(
                    LinearGradient(colors: [Color("Orange"), Color("OrangeRed")], startPoint: .top, endPoint: .bottom)
                )
                .scaleEffect(x: 1 + 0.06 * sin(time * 9), y: 1 + 0.12 * sin(time * 13), anchor: .bottom)
                .offset(x: -18, y: 128)

            Image(systemName: "frying.pan.fill")
                .font(.system(size: 120))
                .foregroundStyle(Color("GraniteGray"))
                .rotationEffect(.degrees(sin(time * 2.2) * 3 - landing * 2), anchor: .bottom)
                .offset(y: 60 + landing * 3)
        }
    }
}

/// A soft puff of steam rising from the pan and fading out
private struct SteamWisp: View {
    let time: Double
    let index: Int

    var body: some View {
        let progress = (time / 2.4 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
        Capsule()
            .fill(Color("DarkSilver").opacity(0.35 * sin(.pi * progress)))
            .frame(width: 9, height: 28)
            .blur(radius: 2)
            .offset(
                x: CGFloat(index - 1) * 24 - 14 + sin(progress * .pi * 2) * 6,
                y: 20 - 80 * progress
            )
    }
}

/// A few grains of salt sprinkled from above every so often
private struct SaltPinch: View {
    let time: Double

    /// Horizontal positions and start delays of the grains
    private static let grains: [(x: CGFloat, delay: Double)] = [
        (-18, 0), (-6, 0.12), (6, 0.05), (16, 0.2), (0, 0.3), (-12, 0.36)
    ]

    var body: some View {
        // A pinch every 3 seconds; each grain falls for about a second
        let pinch = time.truncatingRemainder(dividingBy: 3)
        ZStack {
            ForEach(Self.grains.indices, id: \.self) { index in
                let grain = Self.grains[index]
                let progress = min(max((pinch - grain.delay) / 1.0, 0), 1)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color("DarkSilver").opacity(0.6), lineWidth: 0.5))
                    .frame(width: 5, height: 5)
                    .offset(x: grain.x - 14, y: -140 + 170 * progress)
                    .opacity(progress > 0 && progress < 1 ? 1 : 0)
            }
        }
    }
}

// MARK: - Photo Card Stack

/// The photos being imported as a small tilted stack
private struct PhotoCardStack: View {
    let photos: [UIImage]

    var body: some View {
        ZStack {
            ForEach(Array(photos.prefix(3).enumerated().reversed()), id: \.offset) { index, photo in
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 70, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .rotationEffect(.degrees(-8 + Double(index) * 7))
                    .offset(x: CGFloat(index) * 8)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview("Link") {
    ImportProgressView(kind: .link, onCancel: {})
}

#Preview("Note") {
    ImportProgressView(kind: .note, onCancel: {})
}
