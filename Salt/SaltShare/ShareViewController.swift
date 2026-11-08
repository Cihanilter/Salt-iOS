//
//  ShareViewController.swift
//  SaltShare
//
//  Receives a shared link (Safari, Instagram, TikTok, ...), screenshots and photos,
//  or a recipe written out as text (e.g. a note from the Notes app) and hands it to
//  the Salt app, where the regular import flow takes over:
//  - links: `salt://import?url=...`
//  - photos and text: saved to the App Group's SharedImports folder, then
//    `salt://import?shared=<id>` (too big for a link)
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
        let sharedUrl = await extractSharedUrl()
        let deepLink: URL
        if let sharedImport = await saveSharedPhotosOrText(hasLink: sharedUrl != nil) {
            deepLink = sharedImport
        } else if let sharedUrl {
            // A shared note (not a copy of it) is a link to iCloud, which Salt can't open
            if sharedUrl.host?.contains("icloud.com") == true, sharedUrl.path.contains("notes") {
                showMessage("To import a note, choose \"Send Copy\" in the Notes share menu, then pick Salt.")
                return
            }
            guard let linkImport = makeImportDeepLink(for: sharedUrl) else {
                showMessage("This link can't be imported.")
                return
            }
            deepLink = linkImport
        } else {
            showMessage("No recipe found. Share a recipe link, a screenshot or a note with the recipe to import it into Salt.")
            return
        }

        if openContainingApp(with: deepLink) {
            // Give the system a moment to start the transition before dismissing
            try? await Task.sleep(nanoseconds: 300_000_000)
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        } else {
            // Fallback: the system refused to open the app. Photos and text wait in the
            // App Group for the next launch; a link is copied so it can be pasted.
            if let url = URLComponents(url: deepLink, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value {
                UIPasteboard.general.string = url
                showMessage("Link copied. Open Salt and paste it in Add Recipe → Import.")
            } else {
                showMessage("Saved. Open Salt to finish importing.")
            }
        }
    }

    // MARK: - Photos & Text

    /// Most photos for one recipe, as in the app's photo picker
    private static let maxPhotos = 5
    private static let appGroup = "group.com.salt.recipes"

    /// Saves shared photos/screenshots, or text that's a written-out recipe, for the app to
    /// import, and returns the deep link to open. nil when there are none (e.g. a shared link).
    /// hasLink: a link was shared too; then images are only its preview (e.g. from Pinterest)
    /// and the link is imported instead.
    ///
    /// Folder format, read by `SharedImportInbox` in the app:
    /// `<App Group>/SharedImports/<id>/` holding either `1.jpg`, `2.jpg`, ... (in order) or `text.txt`
    private func saveSharedPhotosOrText(hasLink: Bool) async -> URL? {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        let imageProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        if !imageProviders.isEmpty, !hasLink {
            var photos: [Data] = []
            for provider in imageProviders.prefix(Self.maxPhotos) {
                if let data = await loadImageData(from: provider) {
                    photos.append(data)
                }
            }
            guard !photos.isEmpty else { return nil }
            return saveToAppGroup { folder in
                for (index, data) in photos.enumerated() {
                    try data.write(to: folder.appendingPathComponent("\(index + 1).jpg"))
                }
            }
        }

        let text = await sharedText()
        guard isRecipeText(text) else { return nil }
        return saveToAppGroup { folder in
            try text.write(to: folder.appendingPathComponent("text.txt"), atomically: true, encoding: .utf8)
        }
    }

    /// The image's file data. Apps share images as a file, data or a UIImage
    /// (e.g. the screenshot editor); file data is kept as is so big photos aren't decoded here.
    private func loadImageData(from provider: NSItemProvider) async -> Data? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) else { return nil }
        switch item {
        case let url as URL: return try? Data(contentsOf: url)
        case let data as Data: return data
        case let image as UIImage: return image.jpegData(compressionQuality: 0.9)
        default: return nil
        }
    }

    /// All shared text: text attachments, or the text attached to the extension item
    private func sharedText() async -> String {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        var texts: [String] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            switch try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) {
            case let text as String: texts.append(text)
            case let data as Data: String(data: data, encoding: .utf8).map { texts.append($0) }
            case let url as URL where url.isFileURL: (try? String(contentsOf: url, encoding: .utf8)).map { texts.append($0) }
            default: break
            }
        }
        if texts.isEmpty {
            texts = items.compactMap { $0.attributedContentText?.string }
        }
        return texts.joined(separator: "\n")
    }

    /// Whether the text is a written-out recipe rather than a link with a few words around it
    /// (e.g. TikTok's "Check out this video! https://..."): a few lines and more than a caption's worth of text.
    private func isRecipeText(_ text: String) -> Bool {
        var remaining = text
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range).reversed() {
                if let linkRange = Range(match.range, in: remaining) {
                    remaining.removeSubrange(linkRange)
                }
            }
        }
        let lines = remaining.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return remaining.trimmingCharacters(in: .whitespacesAndNewlines).count > 150 && lines.count >= 4
    }

    /// Creates a new folder in the App Group, lets `write` fill it, and returns `salt://import?shared=<id>`
    private func saveToAppGroup(_ write: (URL) throws -> Void) -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) else {
            return nil
        }
        let id = UUID().uuidString
        let folder = container.appendingPathComponent("SharedImports/\(id)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try write(folder)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
        return URL(string: "salt://import?shared=\(id)")
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
