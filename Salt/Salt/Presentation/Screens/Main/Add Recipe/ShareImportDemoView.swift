//
//  ShareImportDemoView.swift
//  Salt
//

import SwiftUI

// MARK: - Share Import Demo

/// Short looping walkthrough showing how to send a recipe to Salt
/// from a social media app: Share > Share to... > Salt.
struct ShareImportDemoView: View {
    @State private var currentStep = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps = ShareDemoStep.allCases

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                // Tip pill
                Label("Tip", systemImage: "lightbulb.fill")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundColor(Color("Orange"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color("Orange").opacity(0.12)))

                Text("Importing from social media?")
                    .font(.custom("Playfair9pt-SemiBold", size: 20))

                Text("You can share recipes straight to Salt from Instagram, TikTok or YouTube.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(Color("GraniteGray"))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)

            TabView(selection: $currentStep) {
                ForEach(steps) { step in
                    ShareDemoStepView(step: step, stepCount: steps.count)
                        .tag(step.rawValue)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 230)

            ShareDemoPageDots(count: steps.count, current: currentStep)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        // Tinted card sets the walkthrough apart from the link import above
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color("PeachCream").opacity(0.7))
        )
        .task(id: currentStep) {
            // Auto-advance; restarting on every change means a manual swipe resets the timer
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut) {
                currentStep = (currentStep + 1) % steps.count
            }
        }
    }
}

// MARK: - Demo Steps

enum ShareDemoStep: Int, CaseIterable, Identifiable {
    case tapShare
    case tapShareTo
    case tapSalt

    var id: Int { rawValue }

    var caption: String {
        switch self {
        case .tapShare: "Tap the share button"
        case .tapShareTo: "Tap \u{201C}Share to...\u{201D}"
        case .tapSalt: "Tap Salt"
        }
    }
}

struct ShareDemoStepView: View {
    let step: ShareDemoStep
    let stepCount: Int

    var body: some View {
        VStack(spacing: 14) {
            Group {
                switch step {
                case .tapShare: DemoPostMock()
                case .tapShareTo: DemoAppShareSheetMock()
                case .tapSalt: DemoSystemShareSheetMock()
                }
            }
            .frame(width: 220, height: 180)
            .background(Color("Alabaster"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 3)

            Text(step.caption)
                .font(.custom("Playfair9pt-Regular", size: 18))
                .foregroundColor(Color("OrangeRed"))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(stepCount): \(step.caption)")
    }
}

// MARK: - Step 1: Social Media Post

private struct DemoPostMock: View {
    var body: some View {
        VStack(spacing: 0) {
            DemoFoodPhoto()
                .frame(height: 130)

            HStack(spacing: 14) {
                Image(systemName: "heart")
                Image(systemName: "bubble.right")
                DemoHighlight {
                    Image(systemName: "paperplane")
                }
                Spacer()
                Image(systemName: "bookmark")
            }
            .font(.system(size: 15))
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Step 2: Social App's Share Sheet

private struct DemoAppShareSheetMock: View {
    var body: some View {
        VStack(spacing: 0) {
            DemoFoodPhoto(showsIcon: false)
                .frame(height: 28)

            VStack(spacing: 12) {
                // Contacts placeholder row
                HStack(spacing: 18) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(spacing: 5) {
                            Circle()
                                .fill(Color(.systemGray5))
                                .frame(width: 34, height: 34)
                            DemoPlaceholderLine(width: 26)
                        }
                    }
                }
                .padding(.top, 14)

                Divider()

                // Action row
                HStack(spacing: 12) {
                    DemoActionCircle(systemName: "plus.circle")

                    VStack(spacing: 4) {
                        DemoHighlight {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                                .foregroundColor(.black)
                                .frame(width: 22, height: 22)
                        }
                        Text("Share to...")
                            .font(.custom("OpenSans-Regular", size: 9))
                            .foregroundColor(.black)
                    }

                    DemoActionCircle(systemName: "link")
                    DemoActionCircle(systemName: "message.fill", tint: .green)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.white)
        }
    }
}

// MARK: - Step 3: iOS Share Sheet

private struct DemoSystemShareSheetMock: View {
    var body: some View {
        VStack(spacing: 16) {
            // Shared item preview row
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 6) {
                    DemoPlaceholderLine(width: 110)
                    DemoPlaceholderLine(width: 70)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)

            Divider()

            // App row
            HStack(alignment: .top, spacing: 12) {
                DemoAppIcon(label: "AirDrop") {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundColor(.blue)
                        .frame(width: 38, height: 38)
                        .background(Color.white)
                }

                VStack(spacing: 4) {
                    DemoHighlight(cornerRadius: 12) {
                        Image("saltAppIcon")
                            .resizable()
                            .frame(width: 38, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    Text("Salt")
                        .font(.custom("OpenSans-SemiBold", size: 9))
                        .foregroundColor(.black)
                }

                DemoAppIcon(label: "Messages") {
                    Image(systemName: "message.fill")
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.green)
                }

                DemoAppIcon(label: "Mail") {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.blue)
                }
            }

            Spacer(minLength: 0)
        }
        .background(Color.white)
    }
}

// MARK: - Demo Building Blocks

/// Stand-in for a recipe photo in the mock screens.
private struct DemoFoodPhoto: View {
    var showsIcon = true

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color("PeachCream"), Color("LightGrayishPink")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if showsIcon {
                Image(systemName: "fork.knife")
                    .font(.system(size: 30))
                    .foregroundColor(Color("GraniteGray"))
            }
        }
        .clipped()
    }
}

/// Pulsing orange ring that marks the element to tap in each step.
private struct DemoHighlight<Content: View>: View {
    var cornerRadius: CGFloat = 100
    @ViewBuilder var content: Content
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .padding(5)
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color.white))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color("Orange"), lineWidth: 2)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius + 6)
                    .fill(Color("Orange").opacity(0.2))
                    .padding(-6)
                    .scaleEffect(isPulsing ? 1.12 : 0.92)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

private struct DemoActionCircle: View {
    let systemName: String
    var tint: Color? = nil

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .foregroundColor(tint == nil ? .black : .white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint ?? Color(.systemGray6)))
            DemoPlaceholderLine(width: 20)
        }
    }
}

private struct DemoAppIcon<Icon: View>: View {
    let label: String
    @ViewBuilder var icon: Icon

    var body: some View {
        VStack(spacing: 4) {
            icon
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color(.systemGray5), lineWidth: 0.5)
                )
            Text(label)
                .font(.custom("OpenSans-Regular", size: 9))
                .foregroundColor(Color("GraniteGray"))
                .lineLimit(1)
        }
        .padding(.top, 5)  // Aligns with the highlighted Salt icon's padding
    }
}

private struct DemoPlaceholderLine: View {
    let width: CGFloat

    var body: some View {
        Capsule()
            .fill(Color(.systemGray5))
            .frame(width: width, height: 4)
    }
}

// MARK: - Page Dots

struct ShareDemoPageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color("Orange") : Color("Orange").opacity(0.25))
                    .frame(width: index == current ? 20 : 7, height: 7)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview {
    ShareImportDemoView()
        .padding()
}

#Preview("All Steps") {
    VStack(spacing: 8) {
        ForEach(ShareDemoStep.allCases) { step in
            ShareDemoStepView(step: step, stepCount: ShareDemoStep.allCases.count)
        }
    }
}
