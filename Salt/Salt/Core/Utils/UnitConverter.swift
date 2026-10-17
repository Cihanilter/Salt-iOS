//
//  UnitConverter.swift
//  Salt
//
//  Shows ingredient amounts and oven temperatures in imperial or metric units
//

import Foundation

/// The measuring system a recipe is shown in
enum UnitSystem: String {
    case imperial, metric
}

/// Converts amount-first ingredient lines (see `IngredientScaler.amountFirst`) for display:
/// "1 pound beef" ↔ "455 g beef", "8 fl oz cream" ↔ "240 ml cream". Only imperial and metric
/// units convert; cups, spoons, pinches and counted things ("2 eggs") stay as written.
/// The stored text isn't changed.
enum UnitConverter {

    // MARK: Public

    /// The system most of the recipe's measurements are in; nil when none of them can be converted
    static func system(of lines: [String]) -> UnitSystem? {
        var imperial = 0
        var metric = 0
        for line in lines {
            let line = IngredientScaler.amountFirst(line)
            // The amount's unit, or else a package size: "1 package (16 ounces) penne"
            guard let unit = measurement(in: line)?.unit ?? sizes(in: line).first?.size.unit else { continue }
            if unit.system == .imperial { imperial += 1 } else { metric += 1 }
        }
        guard imperial + metric > 0 else { return nil }
        return metric > imperial ? .metric : .imperial
    }

    /// The line with its amount and any package sizes in `system`, e.g. "1 package (16 ounces) penne"
    /// → "1 package (455 g) penne". Lines without a convertible unit are unchanged.
    static func convert(_ line: String, to system: UnitSystem) -> String {
        convertSizes(in: convertAmount(line, to: system), to: system)
    }

    /// The leading amount: "1 pound beef" → "455 g beef"
    private static func convertAmount(_ line: String, to system: UnitSystem) -> String {
        guard let found = measurement(in: line), found.unit.system != system else { return line }

        var rest = found.rest
        // "1 lb (450 g) beef" already says it in the other system, so that's used as is.
        // "1 kg (2 lb) potatoes" would repeat the old system after converting, so it goes.
        if let bracket = conversionBracket(atStartOf: rest) {
            if bracket.unit.system == system { return found.prefix + bracket.text + bracket.after }
            rest = bracket.after
        }

        guard let amount = convertedAmount(found, to: system, isPackageSize: false) else { return line }
        return found.prefix + amount + rest
    }

    /// Amounts in brackets that say how big something is: "1 package (16 ounces)", "1 (14.5 ounce) can",
    /// "1 cup (8 oz)". They don't change with the servings, only their unit does.
    private static func convertSizes(in line: String, to system: UnitSystem) -> String {
        var result = line
        // Last first, so the earlier ranges still point at the same text
        for (range, size) in sizes(in: line).reversed() where size.unit.system != system {
            guard let amount = convertedAmount(size, to: system, isPackageSize: true) else { continue }
            result = (result as NSString).replacingCharacters(in: range, with: size.prefix + amount + size.rest)
        }
        return result
    }

    /// "455 g", "6 ½ oz", "0.91–1.36 kg"; nil when the amount is too small to convert
    private static func convertedAmount(_ found: Measurement, to system: UnitSystem, isPackageSize: Bool) -> String? {
        let amounts = found.values.map { $0 * found.unit.size }  // grams or milliliters
        guard let target = target(for: amounts.max() ?? 0, dimension: found.unit.dimension,
                                  system: system, isPackageSize: isPackageSize) else { return nil }
        let values = amounts.map { target.rounded($0 / target.size) }
        let amount = values.map(target.text).joined(separator: found.separator ?? "")
        let unit = (values.last ?? 0) > 1 ? target.plural : target.singular
        return amount + " " + unit
    }

    /// "Bake at 350°F" → "Bake at 175°C". Where both are given ("350°F (180°C)") the one in
    /// `system` is kept.
    static func convertTemperatures(in text: String, to system: UnitSystem) -> String {
        var result = text

        for match in pairedTemperature.matches(in: result, range: fullRange(of: result)).reversed() {
            let ns = result as NSString
            let pieces = (1...3).compactMap { group -> String? in
                let range = match.range(at: group)
                return range.location == NSNotFound ? nil : ns.substring(with: range)
            }
            guard let kept = pieces.first(where: { temperature(in: $0)?.system == system }) else { continue }
            result = ns.replacingCharacters(in: match.range, with: kept)
        }

        for match in singleTemperature.matches(in: result, range: fullRange(of: result)).reversed() {
            let ns = result as NSString
            guard let found = temperature(in: ns.substring(with: match.range)), found.system != system else { continue }
            result = ns.replacingCharacters(in: match.range, with: converted(found.degrees, from: found.system))
        }
        return result
    }

    // MARK: Units

    private struct Unit {
        enum Dimension { case mass, volume }
        let system: UnitSystem
        let dimension: Dimension
        let size: Double  // grams or milliliters in one
    }

    private static let units: [String: Unit] = {
        var units: [String: Unit] = [:]
        func add(_ words: [String], _ system: UnitSystem, _ dimension: Unit.Dimension, _ size: Double) {
            for word in words { units[word] = Unit(system: system, dimension: dimension, size: size) }
        }
        add(["g", "gr", "gram", "grams", "gramme", "grammes"], .metric, .mass, 1)
        add(["kg", "kilo", "kilos", "kilogram", "kilograms"], .metric, .mass, 1000)
        add(["ml", "milliliter", "milliliters", "millilitre", "millilitres"], .metric, .volume, 1)
        add(["cl"], .metric, .volume, 10)
        add(["dl"], .metric, .volume, 100)
        add(["l", "liter", "liters", "litre", "litres"], .metric, .volume, 1000)
        // US sizes, which is what the recipes use
        add(["oz", "ounce", "ounces"], .imperial, .mass, 28.35)
        add(["lb", "lbs", "pound", "pounds"], .imperial, .mass, 453.6)
        add(["fl oz", "floz", "fluid ounce", "fluid ounces"], .imperial, .volume, 29.57)
        add(["pint", "pints", "pt"], .imperial, .volume, 473)
        add(["quart", "quarts", "qt"], .imperial, .volume, 946)
        add(["gallon", "gallons", "gal"], .imperial, .volume, 3785)
        return units
    }()

    // MARK: Matching

    private struct Measurement {
        let prefix: String      // whatever comes before the amount, e.g. "About "
        let values: [Double]    // the amount, or both ends of a range
        let separator: String?  // "–" in "2–3 lb"
        let unit: Unit
        let rest: String        // everything after the unit: " flour, sifted"
    }

    /// The unit right after the amount: "oz.", "fl oz", "lbs", "g" in "180g"
    private static let unitWord = try! NSRegularExpression(
        pattern: #"^\s*(fl\.?\s*oz\.?|fluid\s+ounces?|[A-Za-z]+\.?)(?![A-Za-z])"#, options: [.caseInsensitive]
    )

    private static func measurement(in line: String) -> Measurement? {
        let ns = line as NSString
        guard let match = IngredientScaler.leadingAmount.firstMatch(in: line, range: fullRange(of: line)),
              let first = IngredientScaler.parseNumber(ns.substring(with: match.range(at: 1))) else { return nil }

        var values = [first]
        var separator: String?
        if match.range(at: 3).location != NSNotFound,
           let second = IngredientScaler.parseNumber(ns.substring(with: match.range(at: 3))) {
            values.append(second)
            separator = ns.substring(with: match.range(at: 2))
        }

        let afterAmount = ns.substring(from: NSMaxRange(match.range))
        let after = afterAmount as NSString
        guard let word = unitWord.firstMatch(in: afterAmount, range: fullRange(of: afterAmount)) else { return nil }
        let key = after.substring(with: word.range(at: 1)).lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard let unit = units[key] else { return nil }

        return Measurement(prefix: ns.substring(to: match.range(at: 1).location), values: values,
                           separator: separator, unit: unit, rest: after.substring(from: NSMaxRange(word.range)))
    }

    private static let bracket = try! NSRegularExpression(pattern: #"^\s*\(\s*([^()]+?)\s*\)"#)

    /// A bracket at the start of `text` holding only an amount, e.g. " (450 g)": its contents,
    /// unit, and the text after it
    private static func conversionBracket(atStartOf text: String) -> (text: String, unit: Unit, after: String)? {
        let ns = text as NSString
        guard let match = bracket.firstMatch(in: text, range: fullRange(of: text)) else { return nil }
        let inner = ns.substring(with: match.range(at: 1))
        guard let found = measurement(in: inner), found.rest.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        return (inner, found.unit, ns.substring(from: NSMaxRange(match.range)))
    }

    private static let anyBracket = try! NSRegularExpression(pattern: #"\(\s*([^()]+?)\s*\)"#)

    /// Brackets anywhere in the line holding only an amount, e.g. "(16 ounces)", "(about 2 pounds)"
    /// or "(15 oz each)": the range of what's inside, and the amount
    private static func sizes(in line: String) -> [(range: NSRange, size: Measurement)] {
        let ns = line as NSString
        return anyBracket.matches(in: line, range: fullRange(of: line)).compactMap { match in
            let range = match.range(at: 1)
            guard let size = measurement(in: ns.substring(with: range)),
                  ["", "each"].contains(size.rest.trimmingCharacters(in: .whitespaces).lowercased()) else { return nil }
            return (range, size)
        }
    }

    private static func fullRange(of text: String) -> NSRange {
        NSRange(location: 0, length: (text as NSString).length)
    }

    // MARK: Targets

    /// A unit to show amounts in and how they're rounded
    private struct Target {
        enum Style {
            case metric               // g, ml: halves under 10, whole under 100, then fives
            case metricLarge          // kg, L: up to two decimals
            case kitchen([Double])    // the fractions allowed between whole numbers, 0 and 1 included
        }

        let singular: String
        let plural: String
        let size: Double  // grams or milliliters in one
        let style: Style

        static let grams = Target(singular: "g", plural: "g", size: 1, style: .metric)
        static let kilograms = Target(singular: "kg", plural: "kg", size: 1000, style: .metricLarge)
        static let milliliters = Target(singular: "ml", plural: "ml", size: 1, style: .metric)
        static let liters = Target(singular: "L", plural: "L", size: 1000, style: .metricLarge)
        static let ounces = Target(singular: "oz", plural: "oz", size: 28.35, style: .kitchen([0, 0.5, 1]))
        static let pounds = Target(singular: "lb", plural: "lb", size: 453.6, style: .kitchen([0, 0.25, 0.5, 0.75, 1]))
        static let fluidOunces = Target(singular: "fl oz", plural: "fl oz", size: 29.57, style: .kitchen([0, 0.5, 1]))
        static let quarts = Target(singular: "quart", plural: "quarts", size: 946,
                                   style: .kitchen([0, 0.25, 0.5, 0.75, 1]))

        func rounded(_ value: Double) -> Double {
            switch style {
            case .metric:
                if value < 10 { return max((value * 2).rounded() / 2, 0.5) }
                if value < 100 { return value.rounded() }
                return (value / 5).rounded() * 5
            case .metricLarge:
                return (value * 100).rounded() / 100
            case .kitchen(let steps):
                let whole = value.rounded(.down)
                let nearest = steps.min { abs($0 - (value - whole)) < abs($1 - (value - whole)) } ?? 0
                // Never round an ingredient away entirely
                return whole + nearest > 0 ? whole + nearest : steps.first { $0 > 0 } ?? value
            }
        }

        func text(_ value: Double) -> String {
            switch style {
            case .metric, .metricLarge:
                var text = String(format: "%.2f", value)
                while text.hasSuffix("0") { text.removeLast() }
                if text.hasSuffix(".") { text.removeLast() }
                return text
            case .kitchen:
                return IngredientScaler.fraction(value)
            }
        }
    }

    /// The unit that reads naturally for `amount` (in grams or milliliters); nil when the amount
    /// is too small to convert (a few grams of salt or ml of vanilla is less than ½ oz)
    /// Package sizes stay in ounces up to 2 lb, the way labels print them ("16 oz", not "1 lb").
    private static func target(for amount: Double, dimension: Unit.Dimension, system: UnitSystem,
                               isPackageSize: Bool) -> Target? {
        switch (system, dimension) {
        case (.metric, .mass):
            return amount < 1000 ? .grams : .kilograms
        case (.metric, .volume):
            return amount < 1000 ? .milliliters : .liters
        case (.imperial, .mass):
            if amount < 14 { return nil }
            return amount < (isPackageSize ? 910 : 450) ? .ounces : .pounds
        case (.imperial, .volume):
            if amount < 14 { return nil }
            return amount < 946 ? .fluidOunces : .quarts
        }
    }

    // MARK: Temperatures

    private static let temperaturePattern = #"\d{2,3}\s*(?:°|º|˚|degrees?)\s*(?:F|C|Fahrenheit|Celsius|Centigrade)\b"#

    private static let singleTemperature = try! NSRegularExpression(
        pattern: #"(\d{2,3})\s*(?:°|º|˚|degrees?)\s*(F|C|Fahrenheit|Celsius|Centigrade)\b"#, options: [.caseInsensitive]
    )

    /// "350°F (180°C)" or "350°F/180°C"
    private static let pairedTemperature = try! NSRegularExpression(
        pattern: #"(\#(temperaturePattern))\s*(?:\(\s*(\#(temperaturePattern))\s*\)|/\s*(\#(temperaturePattern)))"#,
        options: [.caseInsensitive]
    )

    private static func temperature(in text: String) -> (degrees: Double, system: UnitSystem)? {
        let ns = text as NSString
        guard let match = singleTemperature.firstMatch(in: text, range: fullRange(of: text)),
              let degrees = Double(ns.substring(with: match.range(at: 1))) else { return nil }
        let scale = ns.substring(with: match.range(at: 2)).lowercased()
        return (degrees, scale.hasPrefix("f") ? .imperial : .metric)
    }

    /// Rounded the way recipes write oven temperatures: 175°C, 350°F
    private static func converted(_ degrees: Double, from system: UnitSystem) -> String {
        switch system {
        case .imperial:
            let celsius = (degrees - 32) * 5 / 9
            return "\(Int(celsius >= 100 ? (celsius / 5).rounded() * 5 : celsius.rounded()))°C"
        case .metric:
            let fahrenheit = degrees * 9 / 5 + 32
            return "\(Int(fahrenheit >= 300 ? (fahrenheit / 25).rounded() * 25 : fahrenheit.rounded()))°F"
        }
    }
}
