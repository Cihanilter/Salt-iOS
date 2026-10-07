//
//  IngredientScaler.swift
//  Salt
//
//  Scales the amounts in free-text ingredient lines for a different number of servings
//

import Foundation

/// Ingredients are stored as plain text, in two formats:
///   - "Lean ground beef: 1 pound"   (curated/database recipes: name, then amount)
///   - "180 g orecchiette"           (imported/user recipes: amount first)
/// and sometimes with the amount in parentheses: "Garlic cloves (2), crushed".
///
/// Only that one amount is scaled (both ends of a range like "2–3"). Other numbers in the
/// line ("cut into 4 pieces") and lines without an amount ("Salt: to taste") stay as they are.
enum IngredientScaler {

    // MARK: Public

    /// The number of servings in text like "6 servings", "Serves 4" or "4-6" (the first number)
    static func baseServings(from text: String) -> Int? {
        guard let match = text.range(of: #"\d+"#, options: .regularExpression),
              let value = Int(text[match]), value > 0 else { return nil }
        return value
    }

    /// The line with its amount multiplied by `factor`, formatted for cooking
    /// (kitchen fractions for cups and spoons, whole grams, whole eggs).
    static func scale(_ line: String, by factor: Double) -> String {
        guard factor > 0, abs(factor - 1) > 0.0001 else { return line }

        let text = line as NSString
        for pattern in anchoredPatterns {
            guard let match = pattern.firstMatch(in: line, range: NSRange(location: 0, length: text.length)),
                  let first = parseNumber(text.substring(with: match.range(at: 1))) else { continue }

            let second = match.range(at: 3).location != NSNotFound
                ? parseNumber(text.substring(with: match.range(at: 3)))
                : nil
            let remainder = text.substring(from: NSMaxRange(match.range))
            let unitInfo = unit(atStartOf: remainder)

            // Rebuild the amount, keeping the original range separator ("–", " to ")
            var amount = format(first * factor, unit: unitInfo?.kind ?? .count)
            if let second {
                let separator = text.substring(with: match.range(at: 2))
                amount += separator + format(second * factor, unit: unitInfo?.kind ?? .count)
            }

            var rest = remainder
            if let unitInfo {
                // A conversion right after a measuring unit, "1 cup (125g) flour", is the same amount
                // and scales too. A package size, "1 can (15 ounce)" or "1 (14.5 ounce) can", doesn't.
                if unitInfo.kind != .count {
                    rest = scaleConversion(in: rest, after: NSMaxRange(unitInfo.range), by: factor)
                }

                // "1 cup" → "2 cups", "2 pounds" → "1 pound"
                if let replacement = inflect(unitInfo.word, for: (second ?? first) * factor) {
                    rest = (rest as NSString).replacingCharacters(in: unitInfo.range, with: replacement)
                }
            }

            let prefix = text.substring(to: match.range(at: 1).location)
            return prefix + amount + rest
        }
        return line
    }

    // MARK: Matching

    // One number: "1 1/2", "1 ½", "1½", "1/2", "1.5", "1,5", "½"
    private static let number = #"(?:\d+\s+\d+/\d+|\d+\s*[¼½¾⅓⅔⅛⅜⅝⅞]|\d+/\d+|\d+(?:[.,]\d+)?|[¼½¾⅓⅔⅛⅜⅝⅞])"#
    private static let wordNumber = #"(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#
    private static let approx = #"(?:(?:about|approx\.?|approximately|roughly|around)\s+)?"#
    // Groups: 1 = amount, 2 = range separator, 3 = range end
    private static let quantity = "(\(number)|\(wordNumber))(?:(\\s*(?:-|–|—|to)\\s*)(\(number)))?"

    /// Where the amount can be, in the order tried
    private static let anchoredPatterns: [NSRegularExpression] = [
        "^[^:]*:\\s*\(approx)\(quantity)",   // "Name: 1 cup", "Shrimp (peeled): 1 pound"
        "^\\s*\(approx)\(quantity)",          // "180 g orecchiette", "About 1 tbsp butter"
        "\\(\\s*\(quantity)"                  // "Garlic cloves (2), crushed"
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static let unicodeFractions: [Character: Double] = [
        "¼": 0.25, "½": 0.5, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3,
        "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875
    ]

    private static let wordValues: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12
    ]

    static func parseNumber(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if let word = wordValues[text.lowercased()] { return word }

        // Whole number followed by a unicode fraction: "1½", "1 ½", or just "½"
        if let last = text.last, let fraction = unicodeFractions[last] {
            let whole = text.dropLast().trimmingCharacters(in: .whitespaces)
            return whole.isEmpty ? fraction : Double(whole).map { $0 + fraction }
        }

        // "1 1/2" or "1/2"
        if text.contains("/") {
            let parts = text.split(separator: " ")
            let fractionPart = parts.last.map(String.init) ?? text
            let pieces = fractionPart.split(separator: "/")
            guard pieces.count == 2, let top = Double(pieces[0]), let bottom = Double(pieces[1]), bottom != 0 else { return nil }
            let whole = parts.count == 2 ? Double(parts[0]) ?? 0 : 0
            return whole + top / bottom
        }

        // "1,000" is a thousand; "1,5" is one and a half
        if let comma = text.firstIndex(of: ",") {
            let decimals = text[text.index(after: comma)...]
            return decimals.count == 3 ? Double(text.replacingOccurrences(of: ",", with: ""))
                                       : Double(text.replacingOccurrences(of: ",", with: "."))
        }
        return Double(text)
    }

    /// Scales a bracketed amount starting at `location`, e.g. " (125g)" or " (240 ml)"
    private static func scaleConversion(in text: String, after location: Int, by factor: Double) -> String {
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: "^\\s*\\(\\s*(\(number))(\\s*)([A-Za-z]+)")
        let searchRange = NSRange(location: location, length: ns.length - location)
        guard let match = regex.firstMatch(in: text, options: .anchored, range: searchRange),
              let value = parseNumber(ns.substring(with: match.range(at: 1))),
              let kind = unitKinds[ns.substring(with: match.range(at: 3)).lowercased()] else { return text }
        return ns.replacingCharacters(in: match.range(at: 1), with: format(value * factor, unit: kind))
    }

    // MARK: Units

    private enum UnitKind {
        case metric        // g, ml: whole numbers (one decimal under 10)
        case metricLarge   // kg, l: up to two decimals
        case kitchen       // cups, spoons, pounds, ounces: kitchen fractions
        case count         // eggs, onions, cloves: whole numbers, fractions under 1
    }

    private static let unitKinds: [String: UnitKind] = {
        var kinds: [String: UnitKind] = [:]
        for word in ["g", "gr", "gram", "grams", "ml", "milliliter", "milliliters", "millilitre", "millilitres", "mg"] {
            kinds[word] = .metric
        }
        for word in ["kg", "kilogram", "kilograms", "l", "liter", "liters", "litre", "litres"] {
            kinds[word] = .metricLarge
        }
        for word in ["cup", "cups", "c", "tbsp", "tbs", "tablespoon", "tablespoons", "tsp", "teaspoon", "teaspoons",
                     "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "pint", "pints", "quart", "quarts",
                     "pinch", "pinches", "dash", "dashes", "stick", "sticks"] {
            kinds[word] = .kitchen
        }
        return kinds
    }()

    /// The word right after the amount (e.g. "cup", "g", "eggs"), its range in `text`, and how
    /// amounts of it are written. Unknown words are counted things ("2 large eggs").
    private static func unit(atStartOf text: String) -> (word: String, range: NSRange, kind: UnitKind)? {
        let regex = try! NSRegularExpression(pattern: #"^\s*([A-Za-z]+)"#)
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else {
            return nil
        }
        let range = match.range(at: 1)
        let word = (text as NSString).substring(with: range)
        return (word, range, unitKinds[word.lowercased()] ?? .count)
    }

    /// Singular and plural forms of units and common counted ingredients
    private static let plurals: [String: String] = [
        "cup": "cups", "tablespoon": "tablespoons", "teaspoon": "teaspoons", "pound": "pounds",
        "ounce": "ounces", "pint": "pints", "quart": "quarts", "pinch": "pinches", "dash": "dashes",
        "stick": "sticks", "gram": "grams", "kilogram": "kilograms", "liter": "liters", "litre": "litres",
        "clove": "cloves", "can": "cans", "slice": "slices", "piece": "pieces", "sprig": "sprigs",
        "bunch": "bunches", "handful": "handfuls", "package": "packages", "packet": "packets",
        "jar": "jars", "bottle": "bottles", "head": "heads", "egg": "eggs", "onion": "onions",
        "lemon": "lemons", "lime": "limes", "potato": "potatoes", "tomato": "tomatoes",
        "carrot": "carrots", "shallot": "shallots", "leek": "leeks", "apple": "apples", "banana": "bananas"
    ]
    private static let singulars = Dictionary(uniqueKeysWithValues: plurals.map { ($1, $0) })

    /// The word in singular or plural to match the new amount, keeping its capitalization;
    /// nil when it doesn't need to change or isn't a word we know
    private static func inflect(_ word: String, for value: Double) -> String? {
        let lower = word.lowercased()
        let target: String?
        if value > 1 {
            target = plurals[lower]
        } else {
            target = singulars[lower]
        }
        guard let target, target != lower else { return nil }
        return word.first?.isUppercase == true ? target.prefix(1).uppercased() + target.dropFirst() : target
    }

    // MARK: Formatting

    private static func format(_ value: Double, unit: UnitKind) -> String {
        switch unit {
        case .metric:
            return value >= 10 ? "\(Int(value.rounded()))" : decimal(value, digits: 1)
        case .metricLarge:
            return decimal(value, digits: 2)
        case .kitchen:
            return fraction(value)
        case .count:
            return value < 1 ? fraction(value) : "\(Int(value.rounded()))"
        }
    }

    /// "1.5", "2", "0.25" (no trailing zeros, always a dot)
    private static func decimal(_ value: Double, digits: Int) -> String {
        var text = String(format: "%.\(digits)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// Nearest kitchen fraction: "¾", "1 ½", "2 ⅓"; large amounts round to halves
    private static func fraction(_ value: Double) -> String {
        let steps: [(Double, String)] = [
            (0, ""), (0.125, "⅛"), (0.25, "¼"), (1.0 / 3, "⅓"), (0.375, "⅜"), (0.5, "½"),
            (0.625, "⅝"), (2.0 / 3, "⅔"), (0.75, "¾"), (0.875, "⅞"), (1, "")
        ]
        let usable = value >= 10 ? steps.filter { [0, 0.5, 1].contains($0.0) } : steps

        var whole = Int(value)
        let remainder = value - Double(whole)
        let nearest = usable.min { abs($0.0 - remainder) < abs($1.0 - remainder) } ?? (0, "")
        if nearest.0 == 1 { whole += 1 }

        switch (whole, nearest.1) {
        case (0, ""): return "⅛"  // never round an ingredient away entirely
        case (0, let symbol): return symbol
        case (let whole, ""): return "\(whole)"
        case (let whole, let symbol): return "\(whole) \(symbol)"
        }
    }
}
