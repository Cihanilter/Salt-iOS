//
//  ShareViewController.swift
//  SaltShare
//
//  Receives a shared link (Safari, Instagram, TikTok, ...) and hands it to the
//  Salt app via the `salt://import?url=...` deep link, where the regular
//  import flow takes over.
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let doneButton = UIButton(type: .system)
    private var didStart = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true

        Task { @MainActor in
            await handleSharedContent()
        }
    }

    // MARK: - Flow

    @MainActor
    private func handleSharedContent() async {
        guard let sharedUrl = await extractSharedUrl() else {
            showMessage("No link found. Share a recipe link to import it into Salt.")
            return
        }

        guard let deepLink = makeImportDeepLink(for: sharedUrl) else {
            showMessage("This link can't be imported.")
            return
        }

        if openContainingApp(with: deepLink) {
            // Give the system a moment to start the transition before dismissing
            try? await Task.sleep(nanoseconds: 300_000_000)
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        } else {
            // Fallback: the system refused to open the app, let the user paste it manually
            UIPasteboard.general.string = sharedUrl.absoluteString
            showMessage("Link copied. Open Salt and paste it in Add Recipe → Import.")
        }
    }

    /// Finds the first web URL in the shared items. Apps like TikTok and Instagram
    /// often share plain text that contains the link, so text is scanned too.
    private func extractSharedUrl() async -> URL? {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        // 1. Proper URL attachments
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
               let url = (item as? URL) ?? (item as? String).flatMap(firstWebUrl(in:)),
               isWebUrl(url) {
                return url
            }
        }

        // 2. Plain text attachments containing a link
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let url = firstWebUrl(in: text) {
                return url
            }
        }

        // 3. Text attached directly to the extension item
        for item in items {
            if let text = item.attributedContentText?.string, let url = firstWebUrl(in: text) {
                return url
            }
        }

        return nil
    }

    private func firstWebUrl(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range)
            .compactMap { $0.url }
            .first(where: isWebUrl)
    }

    private func isWebUrl(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }

    /// Builds `salt://import?url=<encoded>`. The shared URL is fully percent-encoded
    /// so characters like `&` and `?` inside it survive the round trip.
    private func makeImportDeepLink(for url: URL) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "salt://import?url=\(encoded)")
    }

    /// Extensions can't use `UIApplication.shared`, so walk the responder chain to reach
    /// the application object and invoke `open(_:options:completionHandler:)` dynamically.
    private func openContainingApp(with url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self

        while let current = responder {
            if let application = current as? UIApplication, application.responds(to: selector) {
                typealias OpenURLFunction = @convention(c) (
                    AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
                ) -> Void
                let implementation = application.method(for: selector)
                let open = unsafeBitCast(implementation, to: OpenURLFunction.self)
                open(application, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = .systemBackground

        spinner.color = UIColor(red: 1.0, green: 0.27, blue: 0.0, alpha: 1.0)
        spinner.startAnimating()

        statusLabel.text = "Opening in Salt…"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.isHidden = true
        doneButton.addAction(UIAction { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [spinner, statusLabel, doneButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func showMessage(_ message: String) {
        spinner.stopAnimating()
        spinner.isHidden = true
        statusLabel.text = message
        doneButton.isHidden = false
    }
}
