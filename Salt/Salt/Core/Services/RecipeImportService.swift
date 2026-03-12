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

        #if DEBUG
        print("[RecipeImport] URL: \(urlString)")
        print("[RecipeImport] HTML length: \(html.count)")
        print("[RecipeImport] Found \(jsonLdScripts.count) JSON-LD scripts")
        #endif

        // Try to find Recipe schema
        for jsonString in jsonLdScripts {
            if let recipe = parseRecipeSchema(from: jsonString, sourceUrl: urlString) {
                #if DEBUG
                print("[RecipeImport] ✅ Found recipe via JSON-LD")
                #endif
                return recipe
            }
        }

        #if DEBUG
        print("[RecipeImport] No JSON-LD recipe found, trying microdata...")
        print("[RecipeImport] HTML contains 'itemscope': \(html.contains("itemscope"))")
        print("[RecipeImport] HTML contains 'itemprop': \(html.contains("itemprop"))")
        print("[RecipeImport] HTML contains 'Recipe': \(html.contains("Recipe"))")
        #endif

        // If no JSON-LD, try microdata (fallback)
        if let recipe = parseMicrodata(from: html, sourceUrl: urlString) {
            #if DEBUG
            print("[RecipeImport] ✅ Found recipe via Microdata")
            #endif
            return recipe
        }

        #if DEBUG
        print("[RecipeImport] No microdata recipe found, trying RDFa...")
        print("[RecipeImport] HTML contains 'typeof': \(html.contains("typeof"))")
        print("[RecipeImport] HTML contains 'property': \(html.contains("property"))")
        #endif

        // If no microdata, try RDFa (fallback)
        if let recipe = parseRDFa(from: html, sourceUrl: urlString) {
            #if DEBUG
            print("[RecipeImport] ✅ Found recipe via RDFa")
            #endif
            return recipe
        }

        #if DEBUG
        print("[RecipeImport] ❌ No recipe found in any format")
        // Print first 2000 chars of HTML for debugging
        print("[RecipeImport] HTML preview: \(String(html.prefix(2000)))")
        #endif

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

    // MARK: - Microdata Parsing

    /// Parse microdata format (itemscope/itemprop attributes)
    private func parseMicrodata(from html: String, sourceUrl: String) -> ImportedRecipe? {
        // First, try to find and extract Recipe itemscope block
        // Pattern matches: <div itemscope itemtype="http://schema.org/Recipe">
        // The block may have attributes in any order
        let patterns = [
            #"<[^>]+itemscope[^>]+itemtype\s*=\s*["']https?://schema\.org/Recipe["'][^>]*>([\s\S]*?)(?=</div>|</article>|</section>)"#,
            #"<[^>]+itemtype\s*=\s*["']https?://schema\.org/Recipe["'][^>]+itemscope[^>]*>([\s\S]*?)(?=</div>|</article>|</section>)"#
        ]

        for pattern in patterns {
            if let recipeRegex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let recipeMatch = recipeRegex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
               let recipeRange = Range(recipeMatch.range, in: html) {
                let recipeHtml = String(html[recipeRange])
                #if DEBUG
                print("[RecipeImport] Found Recipe block, length: \(recipeHtml.count)")
                #endif
                if let recipe = extractMicrodataRecipe(from: recipeHtml, sourceUrl: sourceUrl) {
                    return recipe
                }
            }
        }

        // Fallback: try to find Recipe in the whole document
        return parseMicrodataFromDocument(html: html, sourceUrl: sourceUrl)
    }

    /// Parse microdata from entire document (when Recipe block is not clearly defined)
    private func parseMicrodataFromDocument(html: String, sourceUrl: String) -> ImportedRecipe? {
        // Check if there's any itemprop="recipeIngredient" in the document
        guard html.contains("itemprop") && html.contains("recipeIngredient") else {
            return nil
        }
        #if DEBUG
        print("[RecipeImport] Trying whole document parsing...")
        #endif
        return extractMicrodataRecipe(from: html, sourceUrl: sourceUrl)
    }

    /// Extract recipe data from HTML with microdata attributes
    private func extractMicrodataRecipe(from html: String, sourceUrl: String) -> ImportedRecipe? {
        // Extract title - find best name (not user names like "NYT Kullanıcısı")
        let title = extractBestRecipeName(from: html)

        guard let recipeTitle = title, !recipeTitle.isEmpty else {
            #if DEBUG
            print("[RecipeImport] Could not find recipe title")
            #endif
            return nil
        }

        #if DEBUG
        print("[RecipeImport] Found title: \(recipeTitle)")
        #endif

        // Extract description
        let description = extractMicrodataValue(from: html, property: "description")
            ?? extractMetaItemprop(from: html, property: "description")

        // Extract image
        let imageUrl = extractMicrodataImage(from: html)

        // Extract times
        let prepTime = extractMicrodataTime(from: html, property: "prepTime")
        let cookTime = extractMicrodataTime(from: html, property: "cookTime")
        let totalTime = extractMicrodataTime(from: html, property: "totalTime")

        // Extract servings
        let servings = extractMicrodataValue(from: html, property: "recipeYield")
            ?? extractMetaItemprop(from: html, property: "recipeYield")
            ?? "2 servings"

        // Extract ingredients
        let ingredients = extractMicrodataList(from: html, property: "recipeIngredient")
        #if DEBUG
        print("[RecipeImport] Found \(ingredients.count) ingredients")
        #endif

        // Extract instructions
        var instructions = extractMicrodataInstructions(from: html)
        if instructions.isEmpty {
            instructions = extractMicrodataList(from: html, property: "recipeInstructions")
        }
        #if DEBUG
        print("[RecipeImport] Found \(instructions.count) instructions")
        #endif

        // Extract author
        let author = extractMicrodataValue(from: html, property: "author")
            ?? extractNestedMicrodataValue(from: html, parentProperty: "author", childProperty: "name")

        // Only return if we have meaningful data
        guard !ingredients.isEmpty || !instructions.isEmpty else {
            #if DEBUG
            print("[RecipeImport] No ingredients or instructions found - returning nil")
            #endif
            return nil
        }

        return ImportedRecipe(
            title: recipeTitle,
            description: description,
            imageUrl: imageUrl,
            prepTimeMinutes: prepTime,
            cookTimeMinutes: cookTime,
            totalTimeMinutes: totalTime ?? ((prepTime ?? 0) + (cookTime ?? 0) > 0 ? (prepTime ?? 0) + (cookTime ?? 0) : nil),
            servings: servings,
            ingredients: ingredients,
            instructions: instructions,
            sourceUrl: sourceUrl,
            sourceName: extractSourceName(from: [:], url: sourceUrl),
            author: author
        )
    }

    /// Find the best recipe name (avoiding user names like "NYT Kullanıcısı")
    private func extractBestRecipeName(from html: String) -> String? {
        // Collect all potential names from meta tags
        var names: [String] = []

        // Pattern 1: <meta itemprop="name" content="...">
        let metaPattern = #"<meta[^>]+itemprop\s*=\s*["']name["'][^>]+content\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: metaPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
            for match in matches {
                if let valueRange = Range(match.range(at: 1), in: html) {
                    let value = decodeHTMLEntities(String(html[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines))
                    if !value.isEmpty {
                        names.append(value)
                    }
                }
            }
        }

        // Pattern 2: reverse order <meta content="..." itemprop="name">
        let reverseMetaPattern = #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+itemprop\s*=\s*["']name["']"#
        if let regex = try? NSRegularExpression(pattern: reverseMetaPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
            for match in matches {
                if let valueRange = Range(match.range(at: 1), in: html) {
                    let value = decodeHTMLEntities(String(html[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines))
                    if !value.isEmpty && !names.contains(value) {
                        names.append(value)
                    }
                }
            }
        }

        // Filter out common user placeholder names
        let blacklist = ["NYT Kullanıcısı", "User", "Anonymous", "Kullanıcı"]
        let filteredNames = names.filter { name in
            !blacklist.contains(where: { name.contains($0) })
        }

        // Return the first good name, or fallback to any name
        return filteredNames.first ?? names.first
    }

    /// Extract single value from itemprop attribute
    private func extractMicrodataValue(from html: String, property: String) -> String? {
        // Pattern for: <tag itemprop="property">value</tag>
        let pattern = #"<[^>]+itemprop\s*=\s*["']\#(property)["'][^>]*>([^<]+)<"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let valueRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        let value = String(html[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return decodeHTMLEntities(value)
    }

    /// Extract value from <meta itemprop="property" content="value">
    private func extractMetaItemprop(from html: String, property: String) -> String? {
        // Pattern for: <meta itemprop="property" content="value">
        let pattern = #"<meta[^>]+itemprop\s*=\s*["']\#(property)["'][^>]+content\s*=\s*["']([^"']+)["']"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let valueRange = Range(match.range(at: 1), in: html) else {
            // Try reverse order (content before itemprop)
            let reversePattern = #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+itemprop\s*=\s*["']\#(property)["']"#
            guard let reverseRegex = try? NSRegularExpression(pattern: reversePattern, options: .caseInsensitive),
                  let reverseMatch = reverseRegex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
                  let reverseValueRange = Range(reverseMatch.range(at: 1), in: html) else {
                return nil
            }
            return decodeHTMLEntities(String(html[reverseValueRange]))
        }

        return decodeHTMLEntities(String(html[valueRange]))
    }

    /// Extract image URL from microdata
    private func extractMicrodataImage(from html: String) -> String? {
        // Pattern 1: Nested ImageObject with url inside
        // <div itemprop="image" itemscope itemtype="...ImageObject">
        //   <meta itemprop="url" content="https://..."/>
        // </div>
        let nestedPattern = #"itemprop\s*=\s*["']image["'][^>]*itemscope[^>]*itemtype\s*=\s*["'][^"']*ImageObject["'][^>]*>[\s\S]*?<meta[^>]+itemprop\s*=\s*["']url["'][^>]+content\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: nestedPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let urlRange = Range(match.range(at: 1), in: html) {
            let url = String(html[urlRange])
            if url.hasPrefix("http") {
                #if DEBUG
                print("[RecipeImport] Found image (nested): \(url)")
                #endif
                return url
            }
        }

        // Pattern 2: Try meta tag with itemprop="image" content="url"
        if let metaImage = extractMetaItemprop(from: html, property: "image") {
            if metaImage.hasPrefix("http") {
                #if DEBUG
                print("[RecipeImport] Found image (meta): \(metaImage)")
                #endif
                return metaImage
            }
        }

        // Pattern 3: Try img tag with itemprop="image"
        let imgPattern = #"<img[^>]+itemprop\s*=\s*["']image["'][^>]+src\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let urlRange = Range(match.range(at: 1), in: html) {
            let url = String(html[urlRange])
            if url.hasPrefix("http") {
                return url
            }
        }

        // Pattern 4: Try reverse order for img
        let reverseImgPattern = #"<img[^>]+src\s*=\s*["']([^"']+)["'][^>]+itemprop\s*=\s*["']image["']"#
        if let regex = try? NSRegularExpression(pattern: reverseImgPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let urlRange = Range(match.range(at: 1), in: html) {
            let url = String(html[urlRange])
            if url.hasPrefix("http") {
                return url
            }
        }

        // Pattern 5: Look for og:image as fallback
        let ogPattern = #"<meta[^>]+property\s*=\s*["']og:image["'][^>]+content\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: ogPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let urlRange = Range(match.range(at: 1), in: html) {
            let url = String(html[urlRange])
            #if DEBUG
            print("[RecipeImport] Found image (og:image): \(url)")
            #endif
            return url
        }

        return nil
    }

    /// Extract time value from microdata (handles ISO duration in content attribute)
    private func extractMicrodataTime(from html: String, property: String) -> Int? {
        // Try meta/span with content attribute containing ISO duration
        let contentPattern = #"<[^>]+itemprop\s*=\s*["']\#(property)["'][^>]+content\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: contentPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let valueRange = Range(match.range(at: 1), in: html) {
            return parseISODuration(String(html[valueRange]))
        }

        // Try reverse order
        let reversePattern = #"<[^>]+content\s*=\s*["']([^"']+)["'][^>]+itemprop\s*=\s*["']\#(property)["']"#
        if let regex = try? NSRegularExpression(pattern: reversePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let valueRange = Range(match.range(at: 1), in: html) {
            return parseISODuration(String(html[valueRange]))
        }

        // Try inline value
        if let inlineValue = extractMicrodataValue(from: html, property: property) {
            return parseISODuration(inlineValue)
        }

        return nil
    }

    /// Extract list of values with the same itemprop (e.g., ingredients)
    private func extractMicrodataList(from html: String, property: String) -> [String] {
        var results: [String] = []

        // Pattern 1: <tag itemprop="property">value</tag> (handles duplicate attributes)
        // Match: <li itemprop="recipeIngredient" itemprop="recipeIngredient">text</li>
        let pattern1 = #"<(?:li|span|p|div)[^>]*itemprop\s*=\s*["']\#(property)["'][^>]*>([^<]+)</(?:li|span|p|div)>"#

        if let regex = try? NSRegularExpression(pattern: pattern1, options: .caseInsensitive) {
            let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
            for match in matches {
                if let valueRange = Range(match.range(at: 1), in: html) {
                    let value = String(html[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        results.append(decodeHTMLEntities(value))
                    }
                }
            }
        }

        // If no results, try meta tags with content attribute
        if results.isEmpty {
            let metaPattern = #"<meta[^>]+itemprop\s*=\s*["']\#(property)["'][^>]+content\s*=\s*["']([^"']+)["']"#
            if let regex = try? NSRegularExpression(pattern: metaPattern, options: .caseInsensitive) {
                let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
                for match in matches {
                    if let valueRange = Range(match.range(at: 1), in: html) {
                        let value = String(html[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty {
                            results.append(decodeHTMLEntities(value))
                        }
                    }
                }
            }
        }

        return results
    }

    /// Extract instructions from microdata (handles nested structures)
    private func extractMicrodataInstructions(from html: String) -> [String] {
        var results: [String] = []

        // Pattern 1: <ol/ul itemprop="recipeInstructions">...<li>step</li>...</ol/ul>
        // This is the most common pattern for Turkish recipe sites
        let olPattern = #"<(?:ol|ul)[^>]+itemprop\s*=\s*["']recipeInstructions["'][^>]*>([\s\S]*?)</(?:ol|ul)>"#
        if let regex = try? NSRegularExpression(pattern: olPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let olRange = Range(match.range(at: 1), in: html) {
            let olContent = String(html[olRange])
            // Extract <li> contents
            let liPattern = #"<li[^>]*>([^<]+)</li>"#
            if let liRegex = try? NSRegularExpression(pattern: liPattern, options: .caseInsensitive) {
                let liMatches = liRegex.matches(in: olContent, options: [], range: NSRange(olContent.startIndex..., in: olContent))
                for liMatch in liMatches {
                    if let valueRange = Range(liMatch.range(at: 1), in: olContent) {
                        let value = String(olContent[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty {
                            results.append(decodeHTMLEntities(value))
                        }
                    }
                }
            }
        }

        // Pattern 2: Try individual elements with itemprop="recipeInstructions"
        if results.isEmpty {
            let instructionPattern = #"<(?:li|p|div|span)[^>]*itemprop\s*=\s*["']recipeInstructions["'][^>]*>([^<]+)</(?:li|p|div|span)>"#
            if let regex = try? NSRegularExpression(pattern: instructionPattern, options: .caseInsensitive) {
                let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
                for match in matches {
                    if let valueRange = Range(match.range(at: 1), in: html) {
                        let value = String(html[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty {
                            results.append(decodeHTMLEntities(value))
                        }
                    }
                }
            }
        }

        // Pattern 3: Try class-based pattern (fallback)
        if results.isEmpty {
            let classPattern = #"class\s*=\s*["'][^"']*recipe-instructions[^"']*["'][^>]*>([\s\S]*?)</(?:ol|ul)>"#
            if let regex = try? NSRegularExpression(pattern: classPattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
               let olRange = Range(match.range(at: 1), in: html) {
                let olContent = String(html[olRange])
                let liPattern = #"<li[^>]*>([^<]+)</li>"#
                if let liRegex = try? NSRegularExpression(pattern: liPattern, options: .caseInsensitive) {
                    let liMatches = liRegex.matches(in: olContent, options: [], range: NSRange(olContent.startIndex..., in: olContent))
                    for liMatch in liMatches {
                        if let valueRange = Range(liMatch.range(at: 1), in: olContent) {
                            let value = String(olContent[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !value.isEmpty {
                                results.append(decodeHTMLEntities(value))
                            }
                        }
                    }
                }
            }
        }

        return results
    }

    /// Extract nested microdata value (e.g., author -> name)
    private func extractNestedMicrodataValue(from html: String, parentProperty: String, childProperty: String) -> String? {
        // Find the parent block
        let parentPattern = #"itemprop\s*=\s*["']\#(parentProperty)["'][^>]*>([\s\S]*?)</"#

        guard let regex = try? NSRegularExpression(pattern: parentPattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let contentRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        let parentContent = String(html[contentRange])
        return extractMicrodataValue(from: parentContent, property: childProperty)
    }

    // MARK: - RDFa Parsing

    /// Parse RDFa format (typeof/property attributes)
    private func parseRDFa(from html: String, sourceUrl: String) -> ImportedRecipe? {
        // Check if there's RDFa Recipe markup
        guard html.contains("typeof") && html.contains("Recipe") else {
            return nil
        }

        // Extract title
        let title = extractRDFaValue(from: html, property: "name")

        guard let recipeTitle = title, !recipeTitle.isEmpty else { return nil }

        // Extract description
        let description = extractRDFaValue(from: html, property: "description")

        // Extract image
        let imageUrl = extractRDFaImage(from: html)

        // Extract times
        let prepTime = extractRDFaTime(from: html, property: "prepTime")
        let cookTime = extractRDFaTime(from: html, property: "cookTime")
        let totalTime = extractRDFaTime(from: html, property: "totalTime")

        // Extract servings
        let servings = extractRDFaValue(from: html, property: "recipeYield") ?? "2 servings"

        // Extract ingredients
        let ingredients = extractRDFaList(from: html, property: "recipeIngredient")

        // Extract instructions
        let instructions = extractRDFaList(from: html, property: "recipeInstructions")

        // Extract author
        let author = extractRDFaValue(from: html, property: "author")

        // Only return if we have meaningful data
        guard !ingredients.isEmpty || !instructions.isEmpty else { return nil }

        return ImportedRecipe(
            title: recipeTitle,
            description: description,
            imageUrl: imageUrl,
            prepTimeMinutes: prepTime,
            cookTimeMinutes: cookTime,
            totalTimeMinutes: totalTime ?? ((prepTime ?? 0) + (cookTime ?? 0) > 0 ? (prepTime ?? 0) + (cookTime ?? 0) : nil),
            servings: servings,
            ingredients: ingredients,
            instructions: instructions,
            sourceUrl: sourceUrl,
            sourceName: extractSourceName(from: [:], url: sourceUrl),
            author: author
        )
    }

    /// Extract single value from RDFa property attribute
    private func extractRDFaValue(from html: String, property: String) -> String? {
        // Pattern for: <tag property="property">value</tag>
        let pattern = #"<[^>]+property\s*=\s*["'][^"']*\#(property)["'][^>]*>([^<]+)<"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let valueRange = Range(match.range(at: 1), in: html) else {
            // Try content attribute
            return extractRDFaContent(from: html, property: property)
        }

        let value = String(html[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return decodeHTMLEntities(value)
    }

    /// Extract value from RDFa content attribute
    private func extractRDFaContent(from html: String, property: String) -> String? {
        let pattern = #"<[^>]+property\s*=\s*["'][^"']*\#(property)["'][^>]+content\s*=\s*["']([^"']+)["']"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let valueRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return decodeHTMLEntities(String(html[valueRange]))
    }

    /// Extract image URL from RDFa
    private func extractRDFaImage(from html: String) -> String? {
        // Try img tag with property="image"
        let imgPattern = #"<img[^>]+property\s*=\s*["'][^"']*image["'][^>]+src\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let urlRange = Range(match.range(at: 1), in: html) {
            return String(html[urlRange])
        }

        // Try content attribute
        return extractRDFaContent(from: html, property: "image")
    }

    /// Extract time value from RDFa
    private func extractRDFaTime(from html: String, property: String) -> Int? {
        if let content = extractRDFaContent(from: html, property: property) {
            return parseISODuration(content)
        }
        if let value = extractRDFaValue(from: html, property: property) {
            return parseISODuration(value)
        }
        return nil
    }

    /// Extract list of values from RDFa
    private func extractRDFaList(from html: String, property: String) -> [String] {
        var results: [String] = []

        let pattern = #"<[^>]+property\s*=\s*["'][^"']*\#(property)["'][^>]*>([^<]+)<"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return results
        }

        let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))

        for match in matches {
            if let valueRange = Range(match.range(at: 1), in: html) {
                let value = String(html[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    results.append(decodeHTMLEntities(value))
                }
            }
        }

        return results
    }

    // MARK: - HTML Helpers

    /// Decode common HTML entities
    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&#8211;", "–"),
            ("&#8212;", "—"),
            ("&#8217;", "'"),
            ("&#8220;", "\u{201C}"),
            ("&#8221;", "\u{201D}"),
            ("&#x27;", "'"),
            ("&#x22;", "\"")
        ]

        for (entity, character) in entities {
            result = result.replacingOccurrences(of: entity, with: character)
        }

        // Decode numeric entities (&#NNN;)
        let numericPattern = #"&#(\d+);"#
        if let regex = try? NSRegularExpression(pattern: numericPattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let codeRange = Range(match.range(at: 1), in: result),
                   let code = Int(result[codeRange]),
                   let scalar = Unicode.Scalar(code) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }

        // Decode hex entities (&#xNN;) - important for Turkish characters
        let hexPattern = #"&#x([0-9A-Fa-f]+);"#
        if let regex = try? NSRegularExpression(pattern: hexPattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let codeRange = Range(match.range(at: 1), in: result),
                   let code = Int(result[codeRange], radix: 16),
                   let scalar = Unicode.Scalar(code) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }

        return result
    }
}
