//
//  SystemPasteButton.swift
//  Salt
//
//  Apple's UIPasteControl in SwiftUI: pastes without the iOS "Allow Paste" alert.
//  Styled as a Salt button (filled, rounded rectangle) through its configuration.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SystemPasteButton: UIViewRepresentable {
    enum Style {
        /// Orange fill, white label (clipboard card)
        case primary
        /// surface/warm-strong fill, dark label (next to the link field)
        case secondary
    }

    var style: Style = .secondary
    var cornerRadius: CGFloat = SaltRadius.buttonSmall
    let onPaste: (String) -> Void

    func makeUIView(context: Context) -> PasteTargetView {
        let target = PasteTargetView()
        target.onPaste = onPaste

        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .labelOnly
        configuration.cornerStyle = .fixed
        configuration.cornerRadius = cornerRadius
        switch style {
        case .primary:
            configuration.baseBackgroundColor = UIColor(SaltColor.actionPrimary)
            configuration.baseForegroundColor = .white
        case .secondary:
            configuration.baseBackgroundColor = UIColor(SaltColor.surfaceWarmStrong)
            configuration.baseForegroundColor = UIColor(SaltColor.textPrimary)
        }

        let control = UIPasteControl(configuration: configuration)
        control.target = target
        control.translatesAutoresizingMaskIntoConstraints = false
        target.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: target.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: target.trailingAnchor),
            control.topAnchor.constraint(equalTo: target.topAnchor),
            control.bottomAnchor.constraint(equalTo: target.bottomAnchor)
        ])
        return target
    }

    func updateUIView(_ uiView: PasteTargetView, context: Context) {
        uiView.onPaste = onPaste
    }

    /// Receives what UIPasteControl pastes (a URL or plain text)
    final class PasteTargetView: UIView {
        var onPaste: ((String) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [
                UTType.url.identifier, UTType.plainText.identifier
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool { true }

        override func paste(itemProviders: [NSItemProvider]) {
            guard let provider = itemProviders.first else { return }
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { self?.onPaste?(url.absoluteString) }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { [weak self] text, _ in
                    guard let text else { return }
                    DispatchQueue.main.async { self?.onPaste?(text) }
                }
            }
        }
    }
}
