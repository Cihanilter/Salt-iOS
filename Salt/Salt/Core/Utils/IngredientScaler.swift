//
//  IngredientScaler.swift
//  Salt
//
//  Shows free-text ingredient lines amount-first, scaled for a different number of servings
//

import Foundation

/// Ingredients are stored as plain text, in a few formats:
///   - "Lean ground beef: 1 pound"   (curated/database recipes: name, then amount)
///   - "180 g orecchiette"           (imported/user recipes: amount first)
///   - "Garlic cloves (2), crushed"  (amount in parentheses)
///
/// For display, every line is rewritten amount-first ("1 pound lean ground beef") with kitchen
/// fractions ("½" rather than "1/2"), and its amount is scaled. Only that one amount is scaled
/// (both ends of a range like "2–3"); other numbers in the line ("cut into 4 pieces") and lines
/// without an amount ("Salt, to taste") stay as they are. The stored text isn't changed.
enum IngredientScaler {

    // MARK: Public

    /// The number of servings in text like "6 servings", "Serves 4" or "4-6" (the first number)
    static func baseServings(from text: String) -> Int? {
        guard let match = text.range(of: #"\d+"#, options: .regularExpression),
              let value = Int(text[match]), value > 0 else { return nil }
        return value
    }

    /// The line as shown in the recipe: amount first, multiplied by `factor` (1 = as written)
    static func display(_ line: String, scaledBy factor: Double = 1) -> String {
        scale(amountFirst(line), by: factor)
    }

    // MARK: Sections

    /// A group of ingredients, e.g. "Marinade"; the heading is nil for ungrouped ingredients
    struct Section {
        let heading: String?
        let lines: [String]
    }

    /// Splits the ingredient list into groups. Recipes mark groups either with heading lines
    /// ("For the pico de gallo:") or, in AI imports, with a tag on each line
    /// ("3 ripe tomatoes (for pico de gallo)"). Without either, it's one group without a heading.
    static func sections(from lines: [String]) -> [Section] {
        if lines.contains(where: { sectionHeading($0) != nil }) {
            return sectionsByHeadingLines(lines)
        }
        return sectionsByTags(lines) ?? [Section(heading: nil, lines: lines)]
    }

    private static func sectionsByHeadingLines(_ lines: [String]) -> [Section] {
        var sections: [Section] = []
        var heading: String?
        var current: [String] = []
        for line in lines {
            if let next = sectionHeading(line) {
                if heading != nil || !current.isEmpty { sections.append(Section(heading: heading, lines: current)) }
                heading = next
                current = []
            } else {
                current.append(line)
            }
        }
        if heading != nil || !current.isEmpty { sections.append(Section(heading: heading, lines: current)) }
        return sections
    }

    /// "(for marinade)", "(optional, for pico de gallo)". Group 1 = text before "for", 2 = group name
    private static let groupTag = try! NSRegularExpression(
        pattern: #"\s*\(([^()]*?,\s*)?for\s+(?:the\s+)?([^(),]+?)\s*\)"#, options: [.caseInsensitive]
    )

    /// Tags that are how an ingredient is used, not a part of the recipe
    private static let usageNotes: Set<String> = [
        "garnish", "garnishing", "serving", "dusting", "greasing", "frying", "brushing", "decoration",
        "decorating", "sprinkling", "drizzling", "the pan", "pan", "the tin", "tin", "rolling", "coating"
    ]

    /// Groups by "(for …)" tags when there are at least two different ones. Untagged lines
    /// belong to the next tagged line's group ("Juice from 1 orange" above "… (for marinade)");
    /// untagged lines after the last tag become "Other ingredients" (e.g. tortillas to assemble).
    private static func sectionsByTags(_ lines: [String]) -> [Section]? {
        func tag(of line: String) -> (name: String, range: NSRange, kept: String)? {
            let ns = line as NSString
            guard let match = groupTag.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let name = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            guard !usageNotes.contains(name.lowercased()) else { return nil }
            // "(optional, for pico de gallo)" keeps "(optional)"
            let before = match.range(at: 1).location != NSNotFound
                ? ns.substring(with: match.range(at: 1)).trimmingCharacters(in: CharacterSet(charactersIn: ", "))
                : ""
            return (name, match.range, before.isEmpty ? "" : " (\(before))")
        }

        let tags = lines.map(tag(of:))
        let names = tags.compactMap { $0?.name.lowercased() }
        guard Set(names).count >= 2 else { return nil }

        var order: [String] = []                  // group keys in order of first appearance
        var groups: [String: (heading: String, lines: [String])] = [:]
        var pending: [String] = []                // untagged lines waiting for the next tag

        for (line, tag) in zip(lines, tags) {
            guard let tag else { pending.append(line); continue }
            let key = tag.name.lowercased()
            let cleaned = ((line as NSString).replacingCharacters(in: tag.range, with: tag.kept))
                .trimmingCharacters(in: .whitespaces)
            if groups[key] == nil {
                order.append(key)
                groups[key] = (tag.name.prefix(1).uppercased() + tag.name.dropFirst(), [])
            }
            groups[key]?.lines += pending + [cleaned]
            pending = []
        }

        var sections = order.compactMap { key in groups[key].map { Section(heading: $0.heading, lines: $0.lines) } }
        // Labeled so they don't read as part of the last group
        if !pending.isEmpty { sections.append(Section(heading: "Other ingredients", lines: pending)) }
        return sections
    }

    /// The heading if the line starts a group of ingredients rather than being one, e.g.
    /// "For the pico de gallo:" → "Pico de gallo", "Chicken:" → "Chicken", "**Sauce**" → "Sauce",
    /// "PICO DE GALLO" → "Pico de gallo". Imports put these in the ingredient list as plain lines.
    static func sectionHeading(_ line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 60 else { return nil }

        // Marked as a heading: "**Sauce**", "## Sauce", "--Sauce--", "[Sauce]"
        let markers = CharacterSet(charactersIn: "*#-–—=_[]")
        let unmarked = text.trimmingCharacters(in: markers).trimmingCharacters(in: .whitespaces)
        let isMarked = unmarked != text && !unmarked.isEmpty
            && (text.hasPrefix("**") || text.hasPrefix("#") || text.hasPrefix("--") || text.hasPrefix("["))
        text = unmarked

        let hasAmount = text.range(of: #"[\d¼½¾⅓⅔⅛⅜⅝⅞]"#, options: .regularExpression) != nil
        let endsWithColon = text.hasSuffix(":")
        let startsWithFor = text.range(of: #"^(?i)for\s+(the\s+)?\S"#, options: .regularExpression) != nil
        let letters = text.filter(\.isLetter)
        let isAllCaps = letters.count >= 3 && letters == letters.uppercased() && text.contains(" ")

        // "Chicken: 1 pound" is an ingredient; "Chicken:" and "For the sauce:" are headings
        guard isMarked || (!hasAmount && (endsWithColon || startsWithFor || isAllCaps)) else { return nil }

        // Tidy up: no colon, no "For the", sentence case for ALL CAPS
        if endsWithColon { text.removeLast() }
        if let forThe = text.range(of: #"^(?i)for\s+(the\s+)?"#, options: .regularExpression) {
            text.removeSubrange(forThe)
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if isAllCaps { text = text.lowercased() }
        // "For serving:" reads better as "To serve"
        if ["serving", "serve", "to serve"].contains(text.lowercased()) {
            return "To serve"
        }
        guard let first = text.first else { return nil }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: Amount first

    /// "Milk: ½ cup" → "½ cup milk", "Garlic cloves (2), crushed" → "2 garlic cloves, crushed",
    /// "Salt: to taste" → "Salt, to taste". Lines that already start with an amount are unchanged.
    static func amountFirst(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let ns = trimmed as NSString
        let all = NSRange(location: 0, length: ns.length)
        if leadingAmount.firstMatch(in: trimmed, range: all) != nil { return trimmed }

        // "Name: amount[, note]"
        if let colon = trimmed.firstIndex(of: ":") {
            let name = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
            let rest = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !rest.isEmpty else { return trimmed }

            let restRange = NSRange(location: 0, length: (rest as NSString).length)
            guard leadingAmount.firstMatch(in: rest, range: restRange) != nil else {
                return "\(name), \(rest)"  // "Salt and pepper, to taste"
            }
            // "1 can (16 ounce), drained" → amount "1 can (16 ounce)", note ", drained"
            var (amount, note) = splitAtTopLevelComma(rest)
            // A bracketed note without numbers goes after the name: "¼ cup milk (or to taste)".
            // Sizes and conversions like "(16 ounce)" or "(125g)" stay with the amount.
            if let bracket = amount.range(of: #"\s*\([^()\d]*\)$"#, options: .regularExpression) {
                note = " " + amount[bracket].trimmingCharacters(in: .whitespaces) + note
                amount = String(amount[..<bracket.lowerBound])
            }
            return "\(amount) \(lowercasedName(name))\(note)"
        }

        // "Name (amount)[, note]"
        if let match = parenthesizedAmount.firstMatch(in: trimmed, range: all) {
            let name = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let amount = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            let after = ns.substring(with: match.range(at: match.numberOfRanges - 1))
            let note = after.isEmpty || after.hasPrefix(",") ? after : " " + after
            return "\(amount) \(lowercasedName(name))\(note)"
        }

        return trimmed
    }

    // MARK: Amount, unit and name

    /// Splits a line for the step-by-step ingredient form: "2 cups flour" → ("2", "cups", "flour"),
    /// "1 can (15 ounce) beans" → ("1", "can", "(15 ounce) beans"), "Salt to taste" → ("", "", "Salt to taste").
    /// Joining the non-empty parts with spaces gives the line back.
    static func parts(of line: String) -> (amount: String, unit: String, name: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let ns = trimmed as NSString
        // Headings ("For the sauce:") have no amount, so they stay whole in the name
        guard let match = leadingAmount.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) else {
            return ("", "", trimmed)
        }

        let amount = ns.substring(with: match.range).trimmingCharacters(in: .whitespaces)
        var rest = ns.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespaces)
        var unit = ""
        if let first = rest.split(separator: " ", maxSplits: 1).first {
            let word = String(first)
            let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,")).lowercased()
            if unitKinds[bare] != nil || containerUnits.contains(bare) {
                unit = word
                rest = String(rest.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return (amount, unit, rest)
    }

    /// Counted units that read as a unit in the form ("2 cloves garlic"), on top of the measuring ones
    private static let containerUnits: Set<String> = [
        "can", "cans", "clove", "cloves", "slice", "slices", "piece", "pieces", "sprig", "sprigs",
        "bunch", "bunches", "handful", "handfuls", "package", "packages", "packet", "packets",
        "jar", "jars", "bottle", "bottles", "head", "heads", "stalk", "stalks", "bag", "bags", "box", "boxes"
    ]

    /// Splits at the first comma outside parentheses
    private static func splitAtTopLevelComma(_ text: String) -> (String, String) {
        var depth = 0
        for index in text.indices {
            switch text[index] {
            case "(": depth += 1
            case ")": depth = max(0, depth - 1)
            case "," where depth == 0:
                return (String(text[..<index]).trimmingCharacters(in: .whitespaces), String(text[index...]))
            default: break
            }
        }
        return (text, "")
    }

    /// Words that stay capitalized when the name moves after the amount
    private static let properNouns: Set<String> = [
        "italian", "french", "greek", "mexican", "thai", "asian", "cajun", "dijon", "parmesan",
        "parmigiano", "pecorino", "romano", "worcestershire", "tabasco", "sriracha", "old", "japanese",
        "chinese", "spanish", "swiss", "monterey", "kalamata", "granny", "yukon", "english", "jamaican",
        "korean", "indian", "mediterranean", "philadelphia", "frank's", "hellmann's", "bisquick", "ritz"
    ]

    /// "Lean ground beef" → "lean ground beef"; keeps "Italian sausage" and "BBQ sauce"
    private static func lowercasedName(_ name: String) -> String {
        guard let first = name.split(separator: " ").first else { return name }
        let word = String(first)
        let isAcronym = word.count > 1 && word == word.uppercased()
        if isAcronym || properNouns.contains(word.lowercased()) { return name }
        return name.prefix(1).lowercased() + name.dropFirst()
    }

    // MARK: Scaling

    /// The line with its leading amount multiplied by `factor` and the following unit or
    /// ingredient in singular/plural to match. Expects an amount-first line (see `amountFirst`).
    static func scale(_ line: String, by factor: Double) -> String {
        guard factor > 0 else { return line }

        let text = line as NSString
        let all = NSRange(location: 0, length: text.length)
        guard let match = leadingAmount.firstMatch(in: line, range: all) else { return line }

        let firstText = text.substring(with: match.range(at: 1))
        guard let first = parseNumber(firstText) else { return line }
        let secondText = match.range(at: 3).location != NSNotFound ? text.substring(with: match.range(at: 3)) : nil
        let second = secondText.flatMap(parseNumber)

        let remainder = text.substring(from: NSMaxRange(match.range))
        let unitInfo = unit(atStartOf: remainder)
        let kind = unitInfo?.kind ?? .count
        let isScaled = abs(factor - 1) > 0.0001

        // As written, unless it's being scaled or written as "1/2", "1 and 1/2" or "One"
        func formatted(_ raw: String, _ value: Double) -> String {
            let lower = raw.lowercased()
            let needsKitchenStyle = raw.contains("/") || lower.contains(" and ") || wordValues[lower] != nil
            return isScaled || needsKitchenStyle ? format(value * factor, unit: kind) : raw
        }

        var amount = formatted(firstText, first)
        if let secondText, let second {
            amount += text.substring(with: match.range(at: 2)) + formatted(secondText, second)
        }

        var rest = remainder
        // A conversion right after a measuring unit, "1 cup (125g) flour", is the same amount
        // and scales too. A package size, "1 can (15 ounce)" or "1 (14.5 ounce) can", doesn't.
        if let unitInfo, unitInfo.kind != .count, isScaled {
            rest = scaleConversion(in: rest, after: NSMaxRange(unitInfo.range), by: factor)
        }
        // "1 cup" → "2 cups", "2 large eggs" → "1 large egg"
        rest = inflectNoun(in: rest, for: (second ?? first) * factor)

        let prefix = text.substring(to: match.range(at: 1).location)
        return prefix + amount + rest
    }

    // MARK: Matching

    // One number: "1 and 1/2", "1 and a half", "1 1/2", "1 ½", "1½", "1/2", "1.5", "1,5", "½"
    private static let number = #"(?:\d+\s+and\s+(?:a\s+half|\d+/\d+|[¼½¾⅓⅔⅛⅜⅝⅞])|\d+\s+\d+/\d+|\d+\s*[¼½¾⅓⅔⅛⅜⅝⅞]|\d+/\d+|\d+(?:[.,]\d+)?|[¼½¾⅓⅔⅛⅜⅝⅞])"#
    // "One onion", but not "One-pot"
    private static let wordNumber = #"(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b(?!-)"#
    private static let approx = #"(?:(?:about|approx\.?|approximately|roughly|around)\s+)?"#
    // Groups: 1 = amount, 2 = range separator, 3 = range end
    private static let quantity = "(\(number)|\(wordNumber))(?:(\\s*(?:-|–|—|to)\\s*)(\(number)))?"

    /// "180 g orecchiette", "About 1 tbsp butter", "One onion". A number that describes the
    /// ingredient rather than its amount ("2% milk", "1-inch piece") doesn't count.
    private static let leadingAmount = try! NSRegularExpression(
        pattern: "^\\s*\(approx)\(quantity)(?![\\d%°]|\\s*-?\\s*inch)", options: [.caseInsensitive]
    )

    /// "Garlic cloves (2), crushed", "Beef chuck roast (about 2 pounds), trimmed".
    /// Groups: 1 = name, 2 = amount with its unit, last = what follows (the amount has groups of its own)
    private static let parenthesizedAmount = try! NSRegularExpression(
        pattern: "^([^()\\d:]+?)\\s*\\(\\s*(\(approx)\(quantity)(?:\\s+[A-Za-z]+)*)\\s*\\)(.*)$",
        options: [.caseInsensitive]
    )

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
        let lower = text.lowercased()
        if let word = wordValues[lower] { return word }

        // "1 and 1/2", "1 and ½", "1 and a half"
        if let and = lower.range(of: " and ") {
            guard let whole = Double(lower[..<and.lowerBound].trimmingCharacters(in: .whitespaces)) else { return nil }
            let part = String(lower[and.upperBound...])
            if part.hasPrefix("a half") { return whole + 0.5 }
            return parseNumber(part).map { whole + $0 }
        }

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

    /// The word right after the amount (e.g. "cup", "g", "large"), its range in `text`, and how
    /// amounts of it are written. Words that aren't measuring units mean counted things.
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
        "carrot": "carrots", "shallot": "shallots", "leek": "leeks", "apple": "apples", "banana": "bananas",
        "peach": "peaches", "pear": "pears", "orange": "oranges", "avocado": "avocados", "mango": "mangoes",
        "pepper": "peppers", "chili": "chilies", "jalapeño": "jalapeños", "jalapeno": "jalapenos",
        "cucumber": "cucumbers", "zucchini": "zucchinis", "mushroom": "mushrooms", "radish": "radishes",
        "scallion": "scallions", "stalk": "stalks", "rib": "ribs", "leaf": "leaves", "strawberry": "strawberries",
        "cherry": "cherries", "breast": "breasts", "thigh": "thighs", "drumstick": "drumsticks",
        "fillet": "fillets", "filet": "filets", "steak": "steaks", "chop": "chops", "sausage": "sausages",
        "tortilla": "tortillas", "bun": "buns", "roll": "rolls", "loaf": "loaves", "cookie": "cookies",
        "sheet": "sheets", "cube": "cubes", "bag": "bags", "box": "boxes", "container": "containers",
        "envelope": "envelopes", "ear": "ears", "date": "dates", "fig": "figs", "plum": "plums", "olive": "olives"
    ]
    private static let singulars = Dictionary(uniqueKeysWithValues: plurals.map { ($1, $0) })

    /// Puts the first known unit or ingredient within the next few words ("cup", "large eggs",
    /// "(28 ounce) cans") in singular or plural to match `value`, keeping its capitalization.
    /// Stops at a comma so notes like ", cut into 4 pieces" are left alone.
    private static func inflectNoun(in text: String, for value: Double) -> String {
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: #"\([^)]*\)|[A-Za-z]+|,"#)
        var wordsChecked = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            if token == "," { break }
            if token.hasPrefix("(") { continue }  // package size, e.g. "(14.5 ounce)"

            let lower = token.lowercased()
            let target = value > 1 ? plurals[lower] : singulars[lower]
            if let target {
                let replacement = token.first?.isUppercase == true ? target.prefix(1).uppercased() + target.dropFirst() : target
                return ns.replacingCharacters(in: match.range, with: replacement)
            }
            // Already in the right form, or the word to keep: stop looking
            if plurals[lower] != nil || singulars[lower] != nil || unitKinds[lower] != nil { break }

            wordsChecked += 1
            if wordsChecked == 3 { break }
        }
        return text
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
