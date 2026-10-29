//
//  HowToVideoView.swift
//  Salt
//
//  Screen recordings of sharing a recipe from each app to Salt, played in a phone frame.
//  Videos are bundled as Resources/Videos/howto_<app>.mp4; an app without one shows only its steps.
//

import SwiftUI
import AVFoundation

/// Apps with a share-to-Salt how-to
enum HowToApp: String, CaseIterable, Identifiable {
    case instagram
    case tiktok
    case facebook
    case youtubeShorts = "youtube"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .facebook: "Facebook"
        case .youtubeShorts: "YouTube Shorts"
        }
    }

    var emoji: String {
        switch self {
        case .instagram: "📸"
        case .tiktok: "🎵"
        case .facebook: "👥"
        case .youtubeShorts: "▶️"
        }
    }

    /// The taps from a post to Salt
    var steps: [String] {
        switch self {
        case .instagram:
            ["Tap the share button under the post", "Tap \u{201C}Share to...\u{201D}", "Tap More, then Salt"]
        case .tiktok:
            ["Tap the share arrow on the video", "Tap \u{201C}More\u{201D} at the end of the row", "Tap Salt"]
        case .facebook:
            ["Tap Share on the post or reel", "Tap \u{201C}More options\u{201D}", "Tap More, then Salt"]
        case .youtubeShorts:
            ["Tap Share on the Short", "Tap \u{201C}More\u{201D} at the end of the row", "Tap Salt"]
        }
    }

    var videoURL: URL? {
        Bundle.main.url(forResource: "howto_\(rawValue)", withExtension: "mp4")
    }
}

// MARK: - Looping Video

/// Silent, looping video with no controls, filling its frame
struct LoopingVideoPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.play(url)
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.stop()
    }

    final class PlayerView: UIView {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        override static var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        func play(_ url: URL) {
            // The bundled videos have no audio track, so playing them doesn't
            // interrupt music or podcasts the user is listening to
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            self.player = player
            player.play()
        }

        func stop() {
            player?.pause()
            looper = nil
            player = nil
        }
    }
}

/// A video inside an iPhone-like frame
struct PhoneFrameVideo: View {
    let url: URL

    var body: some View {
        LoopingVideoPlayer(url: url)
            .aspectRatio(540.0 / 1170.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color.black))
            .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
            .accessibilityHidden(true)
    }
}

// MARK: - How-To Sheet

/// How to send a recipe from one app to Salt: the recording plus the steps
struct HowToVideoSheet: View {
    let app: HowToApp
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Save recipes from \(app.name)")
                .font(.custom("Playfair9pt-SemiBold", size: 24))
                .multilineTextAlignment(.center)
                .padding(.top, 24)
                .padding(.horizontal, 24)

            if let url = app.videoURL {
                PhoneFrameVideo(url: url)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 40)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(app.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color("Orange")))
                        Text(step)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)

            if app.videoURL == nil {
                Spacer()
            }

            OnboardingPrimaryButton(title: "Got it") { dismiss() }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .background(Color.white.ignoresSafeArea())
        .onAppear {
            Analytics.log(.howToVideoOpened, ["app": app.rawValue])
        }
    }
}

#Preview {
    HowToVideoSheet(app: .instagram)
}
