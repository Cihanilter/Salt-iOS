//
//  AppLanguage.swift
//  Salt
//
//  The language the app is shown in, from the iPhone's settings (or Settings › Salt › Language)
//

import Foundation

enum AppLanguage {
    /// True when iOS picked the Turkish localization for the app
    static let isTurkish: Bool = Bundle.main.preferredLocalizations.first?.hasPrefix("tr") == true

    /// The app's language in that language, e.g. "Türkçe", "English"
    static var displayName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let locale = Locale(identifier: code)
        let name = locale.localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    /// "tr" or "en": the recipes shown in Explore (recipes.language), and the language
    /// Salt-backend answers in
    static var code: String { isTurkish ? "tr" : "en" }

    /// Sent with every Supabase request. Recipes in other languages than English are only
    /// visible to requests that carry it, so app versions from before Turkish never see them.
    static let requestHeader = "x-salt-language"

    /// Lowercased the way the app's language does it (Turkish "I" → "ı", "İ" → "i")
    static func lowercased(_ text: String) -> String {
        text.lowercased(with: isTurkish ? Locale(identifier: "tr_TR") : Locale(identifier: "en_US"))
    }
}
