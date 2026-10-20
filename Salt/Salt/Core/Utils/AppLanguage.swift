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

    /// Sent to Salt-backend so AI answers come back in the app's language
    static var code: String { isTurkish ? "tr" : "en" }

    /// The recipes table column for a field in the app's language, e.g. "title" → "title_tr"
    static func recipeColumn(_ name: String) -> String {
        isTurkish ? "\(name)_tr" : name
    }

    /// Lowercased the way the app's language does it (Turkish "I" → "ı", "İ" → "i")
    static func lowercased(_ text: String) -> String {
        text.lowercased(with: isTurkish ? Locale(identifier: "tr_TR") : Locale(identifier: "en_US"))
    }

    /// PostgREST `or` filter matching a title in the app's language or in English, so Turkish
    /// users also find "Lasagna". `pattern` is an ilike pattern such as "lazanya%".
    static func titleFilter(_ pattern: String) -> String {
        let quoted = "\"" + pattern
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        return isTurkish ? "title_tr.ilike.\(quoted),title.ilike.\(quoted)" : "title.ilike.\(quoted)"
    }
}
