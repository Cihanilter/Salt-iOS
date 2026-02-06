//
//  RecipeImportService.swift
//  Salt
//

import Foundation

// MARK: - Imported Recipe Model

struct ImportedRecipe {
    let title: String
    let description: String?
    let imageUrl: String?
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let totalTimeMinutes: Int?
    let servings: String  // Always has value (default: "2 servings")
    let ingredients: [String]
    let instructions: [String]
    let sourceUrl: String
    let sourceName: String?
    let author: String?

    // Convert to Recipe for saving
    func toRecipe() -> Recipe {
        Recipe(
            id: UUID(),
            createdAt: nil,
            updatedAt: nil,
            title: title,
            description: description,
            imageUrl: imageUrl,
            sourceUrl: sourceUrl,
            sourceName: sourceName,
            imageWidth: nil,
            imageHeight: nil,
            prepTimeIso: nil,
            cookTimeIso: nil,
            totalTimeIso: nil,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            totalTimeMinutes: totalTimeMinutes,
            servings: nil,
            servingsText: servings,
            ingredients: ingredients,
            instructions: instructions,
            categories: [],
            cuisines: [],
            author: author,
            rating: nil,
            ratingCount: nil,
            isCurated: nil,
            totalRating: nil,
            nutrition: nil,
            publishedAt: nil
        )
    }

    // Convert to RecipeDetail for preview
    func toRecipeDetail() -> RecipeDetail {
        let totalTime = totalTimeMinutes ?? ((prepTimeMinutes ?? 0) + (cookTimeMinutes ?? 0))
        let durationText = totalTime > 0 ? "\(totalTime) mins" : "N/A"

        // Extract number from servings string (e.g., "4 servings" -> "4")
        let servingsNumber: String
        let servingsText = servings.trimmingCharacters(in: .whitespaces)
        var numberPart = ""
        for char in servingsText {
            if char.isNumber {
                numberPart.append(char)
            } else if !numberPart.isEmpty {
                break
            }
        }
        servingsNumber = numberPart.isEmpty ? "2" : numberPart

        return RecipeDetail(
            title: title,
            duration: durationText,
            ingredientsCount: "\(ingredients.count) ingredients",
            description: description ?? "No description",
            servings: servingsNumber,
            prepTime: prepTimeMinutes.map { "\($0)" } ?? "0",
            cookTime: cookTimeMinutes.map { "\($0)" } ?? "0",
            ingredients: ingredients,
            instructions: instructions,
            notes: "",
            images: imageUrl.map { [$0] } ?? [],
            sourceUrl: sourceUrl,
            sourceName: sourceName
        )
    }
}

// MARK: - Import Error

enum RecipeImportError: LocalizedError {
    case invalidUrl
    case networkError(Error)
    case noRecipeFound
    case parsingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidUrl:
            return "Invalid URL. Please check the link and try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .noRecipeFound:
            return "No recipe found on this page. Make sure the link points to a recipe."
        case .parsingError(let message):
            return "Failed to parse recipe: \(message)"
        }
    }
}

// MARK: - Recipe Import Service

class RecipeImportService {
    static let shared = RecipeImportService()

    // Backend URL for social media import (Railway - supports yt-dlp)
    private let socialImportApiUrl = "https://salt-backend-production.up.railway.app/api/import-social-recipe"

    private init() {}

    /// Import recipe from URL - auto-detects if it's social media or regular website
    func importRecipe(from urlString: String) async throws -> ImportedRecipe {
        // Validate URL
        guard let url = URL(string: urlString),
              url.scheme == "http" || url.scheme == "https" else {
            throw RecipeImportError.invalidUrl
        }

        // Check if it's a social media URL
        if isSocialMediaUrl(urlString) {
            return try await importFromSocialMedia(urlString)
        }

        // Regular website - use Schema.org parsing
        return try await importFromWebsite(url: url, urlString: urlString)
    }

    /// Check if URL is from a social media platform
    private func isSocialMediaUrl(_ urlString: String) -> Bool {
        let socialDomains = [
            "tiktok.com", "vm.tiktok.com",
            "instagram.com", "instagr.am",
            "youtube.com", "youtu.be",
            "facebook.com", "fb.watch",
            "twitter.com", "x.com"
        ]

        let urlLower = urlString.lowercased()
        return socialDomains.contains { urlLower.contains($0) }
    }

    /// Import from social media using backend API
    private func importFromSocialMedia(_ urlString: String) async throws -> ImportedRecipe {
        guard let apiUrl = URL(string: socialImportApiUrl) else {
            throw RecipeImportError.parsingError("Invalid API URL")
        }

        var request = URLRequest(url: apiUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "url": urlString,
            "saveToDatabase": false
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw RecipeImportError.networkError(NSError(domain: "HTTP", code: 0))
            }

            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? String {
                    throw RecipeImportError.parsingError(error)
                }
                throw RecipeImportError.networkError(NSError(domain: "HTTP", code: httpResponse.statusCode))
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RecipeImportError.parsingError("Invalid API response")
            }

            guard let success = json["success"] as? Bool, success else {
                if let isRecipe = json["isRecipe"] as? Bool, !isRecipe {
                    throw RecipeImportError.noRecipeFound
                }
                throw RecipeImportError.parsingError(json["error"] as? String ?? "Import failed")
            }

            guard let recipeData = json["recipe"] as? [String: Any] else {
                throw RecipeImportError.noRecipeFound
            }

            return parseApiRecipe(from: recipeData, sourceUrl: urlString)

        } catch let error as RecipeImportError {
            throw error
        } catch {
            throw RecipeImportError.networkError(error)
        }
    }

    /// Parse recipe from API response
    private func parseApiRecipe(from data: [String: Any], sourceUrl: String) -> ImportedRecipe {
        ImportedRecipe(
            title: data["title"] as? String ?? "Untitled Recipe",
            description: data["description"] as? String,
            imageUrl: data["imageUrl"] as? String,
            prepTimeMinutes: data["prepTimeMinutes"] as? Int,
            cookTimeMinutes: data["cookTimeMinutes"] as? Int,
            totalTimeMinutes: data["totalTimeMinutes"] as? Int,
            servings: data["servings"] as? String ?? "2 servings",
            ingredients: data["ingredients"] as? [String] ?? [],
            instructions: data["instructions"] as? [String] ?? [],
            sourceUrl: sourceUrl,
            sourceName: data["sourceName"] as? String,
            author: nil
        )
    }

    /// Import from regular website using Schema.org parsing
    private func importFromWebsite(url: URL, urlString: String) async throws -> ImportedRecipe {
        // Fetch HTML
        let html: String
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let htmlString = String(data: data, encoding: .utf8) else {
                throw RecipeImportError.parsingError("Failed to decode HTML")
            }
            html = htmlString
        } catch let error as RecipeImportError {
            throw error
        } catch {
            throw RecipeImportError.networkError(error)
        }

        // Extract JSON-LD scripts
        let jsonLdScripts = extractJsonLd(from: html)

        // Try to find Recipe schema
        for jsonString in jsonLdScripts {
            if let recipe = parseRecipeSchema(from: jsonString, sourceUrl: urlString) {
                return recipe
            }
        }

        // If no JSON-LD, try microdata (fallback)
        if let recipe = parseMicrodata(from: html, sourceUrl: urlString) {
            return recipe
        }

        throw RecipeImportError.noRecipeFound
    }

    // MARK: - Private Methods

    /// Extract all JSON-LD script contents from HTML
    private func extractJsonLd(from html: String) -> [String] {
        var results: [String] = []

        // Pattern to match <script type="application/ld+json">...</script>
        let pattern = #"<script[^>]*type\s*=\s*["\']application/ld\+json["\'][^>]*>([\s\S]*?)</script>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return results
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches {
            if let contentRange = Range(match.range(at: 1), in: html) {
                let content = String(html[contentRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                results.append(content)
            }
        }

        return results
    }

    /// Parse Recipe schema from JSON-LD string
    private func parseRecipeSchema(from jsonString: String, sourceUrl: String) -> ImportedRecipe? {
        guard let data = jsonString.data(using: .utf8) else { return nil }

        do {
            let json = try JSONSerialization.jsonObject(with: data)

            // Handle array of schemas
            if let array = json as? [[String: Any]] {
                for item in array {
                    if let recipe = extractRecipe(from: item, sourceUrl: sourceUrl) {
                        return recipe
                    }
                }
            }
            // Handle single schema
            else if let dict = json as? [String: Any] {
                // Check for @graph (common in structured data)
                if let graph = dict["@graph"] as? [[String: Any]] {
                    for item in graph {
                        if let recipe = extractRecipe(from: item, sourceUrl: sourceUrl) {
                            return recipe
                        }
                    }
                }
                // Direct recipe
                else if let recipe = extractRecipe(from: dict, sourceUrl: sourceUrl) {
                    return recipe
                }
            }
        } catch {
            print("JSON parsing error: \(error)")
        }

        return nil
    }

    /// Extract recipe data from JSON dictionary
    private func extractRecipe(from dict: [String: Any], sourceUrl: String) -> ImportedRecipe? {
        // Check if this is a Recipe type
        let type = dict["@type"]
        let isRecipe: Bool

        if let typeString = type as? String {
            isRecipe = typeString == "Recipe"
        } else if let typeArray = type as? [String] {
            isRecipe = typeArray.contains("Recipe")
        } else {
            isRecipe = false
        }

        guard isRecipe else { return nil }

        // Extract title (required)
        guard let title = dict["name"] as? String, !title.isEmpty else { return nil }

        // Extract description
        let description = dict["description"] as? String

        // Extract image
        let imageUrl = extractImageUrl(from: dict["image"])

        // Extract times
        let prepTime = parseISODuration(dict["prepTime"] as? String)
        let cookTime = parseISODuration(dict["cookTime"] as? String)
        let totalTime = parseISODuration(dict["totalTime"] as? String)

        // Extract servings
        let servings = extractServings(from: dict)

        // Extract ingredients
        let ingredients = extractIngredients(from: dict["recipeIngredient"])

        // Extract instructions
        let instructions = extractInstructions(from: dict["recipeInstructions"])

        // Extract source info
        let sourceName = extractSourceName(from: dict, url: sourceUrl)
        let author = extractAuthor(from: dict["author"])

        return ImportedRecipe(
            title: title,
            description: description,
            imageUrl: imageUrl,
            prepTimeMinutes: prepTime,
            cookTimeMinutes: cookTime,
            totalTimeMinutes: totalTime ?? ((prepTime ?? 0) + (cookTime ?? 0) > 0 ? (prepTime ?? 0) + (cookTime ?? 0) : nil),
            servings: servings,
            ingredients: ingredients,
            instructions: instructions,
            sourceUrl: sourceUrl,
            sourceName: sourceName,
            author: author
        )
    }

    /// Extract image URL from various formats
    private func extractImageUrl(from image: Any?) -> String? {
        if let urlString = image as? String {
            return urlString
        }
        if let imageDict = image as? [String: Any] {
            return imageDict["url"] as? String
        }
        if let imageArray = image as? [Any], let first = imageArray.first {
            if let urlString = first as? String {
                return urlString
            }
            if let imageDict = first as? [String: Any] {
                return imageDict["url"] as? String
            }
        }
        return nil
    }

    /// Parse ISO 8601 duration (PT30M, PT1H30M, etc.)
    private func parseISODuration(_ duration: String?) -> Int? {
        guard let duration = duration else { return nil }

        var totalMinutes = 0
        let pattern = #"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: duration, options: [], range: NSRange(duration.startIndex..., in: duration)) else {
            return nil
        }

        // Hours
        if let hoursRange = Range(match.range(at: 1), in: duration),
           let hours = Int(duration[hoursRange]) {
            totalMinutes += hours * 60
        }

        // Minutes
        if let minutesRange = Range(match.range(at: 2), in: duration),
           let minutes = Int(duration[minutesRange]) {
            totalMinutes += minutes
        }

        return totalMinutes > 0 ? totalMinutes : nil
    }

    /// Extract servings from recipe data (default: 2 servings)
    private func extractServings(from dict: [String: Any]) -> String {
        if let yield = dict["recipeYield"] as? String, !yield.isEmpty {
            return yield
        }
        if let yield = dict["recipeYield"] as? Int, yield > 0 {
            return "\(yield) servings"
        }
        if let yieldArray = dict["recipeYield"] as? [Any], let first = yieldArray.first {
            if let yieldString = first as? String, !yieldString.isEmpty {
                return yieldString
            }
            if let yieldInt = first as? Int, yieldInt > 0 {
                return "\(yieldInt) servings"
            }
        }
        // Default value if no servings found
        return "2 servings"
    }

    /// Extract ingredients array
    private func extractIngredients(from ingredients: Any?) -> [String] {
        guard let ingredientArray = ingredients as? [String] else { return [] }
        return ingredientArray.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Extract instructions array
    private func extractInstructions(from instructions: Any?) -> [String] {
        var result: [String] = []

        if let instructionArray = instructions as? [Any] {
            for item in instructionArray {
                if let text = item as? String {
                    result.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
                } else if let dict = item as? [String: Any] {
                    // HowToStep or HowToSection
                    if let text = dict["text"] as? String {
                        result.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else if let steps = dict["itemListElement"] as? [[String: Any]] {
                        // HowToSection with nested steps
                        for step in steps {
                            if let text = step["text"] as? String {
                                result.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                        }
                    }
                }
            }
        } else if let instructionString = instructions as? String {
            // Single string with all instructions
            result = instructionString
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return result
    }

    /// Extract source name
    private func extractSourceName(from dict: [String: Any], url: String) -> String? {
        if let publisher = dict["publisher"] as? [String: Any],
           let name = publisher["name"] as? String {
            return name
        }
        // Fallback: extract domain from URL
        if let urlObj = URL(string: url), let host = urlObj.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return nil
    }

    /// Extract author name
    private func extractAuthor(from author: Any?) -> String? {
        if let authorString = author as? String {
            return authorString
        }
        if let authorDict = author as? [String: Any] {
            return authorDict["name"] as? String
        }
        if let authorArray = author as? [[String: Any]], let first = authorArray.first {
            return first["name"] as? String
        }
        return nil
    }

    /// Fallback: parse microdata (basic implementation)
    private func parseMicrodata(from html: String, sourceUrl: String) -> ImportedRecipe? {
        // Basic microdata parsing - can be extended
        // For now, return nil and rely on JSON-LD
        return nil
    }
}
