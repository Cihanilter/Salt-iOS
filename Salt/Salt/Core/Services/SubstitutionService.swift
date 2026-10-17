//
//  SubstitutionService.swift
//  Salt
//
//  Finds substitutes for an ingredient: a built-in list first, AI ideas for the recipe on top
//

import Foundation
import Supabase

/// Why the cook wants to replace an ingredient
enum SubstitutionReason: String, CaseIterable, Identifiable {
    case missing
    case dislike
    case vegan
    case dairyFree = "dairy_free"
    case glutenFree = "gluten_free"

    var id: Self { self }

    var title: String {
        switch self {
        case .missing: return "Don't have it"
        case .dislike: return "Don't like it"
        case .vegan: return "Vegan"
        case .dairyFree: return "Dairy-free"
        case .glutenFree: return "Gluten-free"
        }
    }

    /// Diets only show substitutes that fit them
    var isDiet: Bool {
        self == .vegan || self == .dairyFree || self == .glutenFree
    }
}

/// A replacement for an ingredient line, written as a line itself ("½ cup Greek yogurt") so it's
/// scaled and converted like the original
struct Substitute: Hashable {
    enum Source: String {
        case builtIn = "built_in"
        case ai
    }

    let line: String
    let note: String?
    let source: Source
}

@MainActor
final class SubstitutionService {
    static let shared = SubstitutionService()
    private init() {}

    // MARK: Ingredient name

    /// What the line is, without amount or notes: "2 cups all-purpose flour, sifted" → "all-purpose flour",
    /// "1 package (16 ounces) penne pasta" → "penne pasta"
    static func ingredientName(of line: String) -> String {
        let name = IngredientScaler.parts(of: IngredientScaler.amountFirst(line)).name
        let main = name.split(separator: ",", maxSplits: 1).first.map(String.init) ?? name
        return main
            .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Built-in list

    private struct Entry: Decodable {
        let names: [String]
        let excludes: [String]?
        let substitutes: [BuiltIn]
    }

    private struct BuiltIn: Decodable {
        let name: String
        let factor: Double?   // amount compared with the original, e.g. 0.75 for "¾ of the amount"
        let per: String?      // amount per piece of a counted ingredient, e.g. "¼ cup" per egg
        let note: String?
        let diets: [String]?  // SubstitutionReason raw values it fits
    }

    /// Loaded once from ingredient_substitutes.json
    private lazy var entries: [Entry] = {
        guard let url = Bundle.main.url(forResource: "ingredient_substitutes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            print("❌ ingredient_substitutes.json missing or invalid")
            return []
        }
        return entries
    }()

    /// Substitutes from the built-in list, with the line's amount carried over. None when the cook
    /// dislikes the ingredient: the list has close stand-ins ("dried basil" for basil), not different
    /// flavors, so the AI answers that.
    func builtInSubstitutes(for line: String, reason: SubstitutionReason) -> [Substitute] {
        guard reason != .dislike, let entry = entry(for: Self.ingredientName(of: line)) else { return [] }
        let parts = IngredientScaler.parts(of: IngredientScaler.amountFirst(line))
        // A package size stays: "1 package (16 ounces) penne" → "1 package (16 ounces) gluten-free pasta"
        let size = parts.name.range(of: #"^\([^()]*\)"#, options: .regularExpression).map { String(parts.name[$0]) }
        return entry.substitutes
            .filter { !reason.isDiet || $0.diets?.contains(reason.rawValue) == true }
            .compactMap { builtIn in
                replacementLine(for: builtIn, amount: parts.amount, unit: parts.unit, size: size)
                    .map { Substitute(line: $0, note: builtIn.note, source: .builtIn) }
            }
    }

    /// The entry with the longest name in the ingredient's name, so "peanut butter" wins over "butter"
    private func entry(for name: String) -> Entry? {
        var best: (entry: Entry, length: Int)?
        for entry in entries {
            if entry.excludes?.contains(where: { Self.contains($0, in: name) }) == true { continue }
            for alias in entry.names where alias.count > (best?.length ?? 0) && Self.contains(alias, in: name) {
                best = (entry, alias.count)
            }
        }
        return best?.entry
    }

    /// Whole words only, plural allowed: "egg" is in "2 large eggs" but not in "eggplant"
    private static func contains(_ word: String, in text: String) -> Bool {
        let pattern = #"(?<!\p{L})"# + NSRegularExpression.escapedPattern(for: word) + #"(?:e?s)?(?!\p{L})"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "1 cup buttermilk" + "milk with lemon juice" → "1 cup milk with lemon juice";
    /// "2 eggs" + "¼ cup applesauce" per egg → "½ cup applesauce". Nil when it doesn't fit the line
    /// (a per-piece amount for "1 cup chopped onion").
    private func replacementLine(for builtIn: BuiltIn, amount: String, unit: String, size: String?) -> String? {
        guard !amount.isEmpty else {
            return builtIn.name.prefix(1).uppercased() + builtIn.name.dropFirst()  // "Salt, to taste"
        }
        if let per = builtIn.per {
            let unit = unit.lowercased()
            guard unit.isEmpty || unit.hasPrefix("clove"),
                  let count = IngredientScaler.parseNumber(amount) else { return nil }
            return IngredientScaler.scale("\(per) \(builtIn.name)", by: count)
        }
        let line = [amount, unit, size ?? "", builtIn.name].filter { !$0.isEmpty }.joined(separator: " ")
        // Also puts "1 flax eggs" in the singular
        return IngredientScaler.scale(line, by: builtIn.factor ?? 1)
    }

    // MARK: AI

    private let apiUrl = "https://salt-backend-production.up.railway.app/api/suggest-substitutes"

    private struct SuggestRequest: Encodable {
        let title: String
        let ingredients: [String]
        let ingredient: String
        let reason: String
    }

    private struct SuggestResponse: Decodable {
        struct Item: Decodable {
            let line: String
            let note: String?
        }
        let success: Bool
        let substitutes: [Item]?
    }

    enum SuggestError: Error {
        case failed
    }

    /// Answers for this session, so reopening an ingredient doesn't ask again
    private var cache: [String: [Substitute]] = [:]

    /// Substitutes picked for this recipe by Salt-backend (`/api/suggest-substitutes`)
    func aiSubstitutes(for line: String, recipeTitle: String, ingredients: [String],
                       reason: SubstitutionReason) async throws -> [Substitute] {
        let ingredient = IngredientScaler.amountFirst(line)
        let key = [recipeTitle, ingredient, reason.rawValue].joined(separator: "\u{1F}")
        if let cached = cache[key] { return cached }
        guard let url = URL(string: apiUrl) else { throw SuggestError.failed }

        // The backend only accepts signed-in users
        let session = try await SupabaseClientManager.shared.client.auth.session

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(SuggestRequest(
            title: recipeTitle,
            ingredients: ingredients.map(IngredientScaler.amountFirst),
            ingredient: ingredient,
            reason: reason.rawValue
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let items = try JSONDecoder().decode(SuggestResponse.self, from: data).substitutes else {
            throw SuggestError.failed
        }

        let substitutes = items.map {
            Substitute(line: $0.line, note: $0.note?.isEmpty == false ? $0.note : nil, source: .ai)
        }
        cache[key] = substitutes
        return substitutes
    }
}
