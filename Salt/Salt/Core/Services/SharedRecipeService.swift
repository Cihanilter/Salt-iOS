//
//  SharedRecipeService.swift
//  Salt
//
//  Creates recipe share links (AppsFlyer OneLink) and loads the recipes they point to
//

import Foundation
import Supabase

final class SharedRecipeService {
    static let shared = SharedRecipeService()

    private var supabase: SupabaseClient {
        SupabaseClientManager.shared.client
    }

    private init() {}

    /// Saves a snapshot of the recipe and returns its share link. Sharing the same recipe
    /// again refreshes the snapshot and returns the same link.
    /// - Parameters:
    ///   - sourceRecipeId: the user recipe or Explore recipe being shared
    ///   - originalRecipeId: set for Explore recipes, so recipients bookmark the original
    func shareLink(for recipe: RecipeDetail, sourceRecipeId: UUID, originalRecipeId: UUID?) async throws -> URL {
        guard !AppsFlyerConfig.oneLinkTemplateID.isEmpty else {
            throw SharedRecipeError.linkUnavailable
        }
        guard let userId = try? await supabase.auth.session.user.id else {
            throw RecipeServiceError.notAuthenticated
        }

        let snapshot = SharedRecipe.Snapshot(
            recipe: recipe,
            ownerId: userId,
            sourceRecipeId: sourceRecipeId,
            originalRecipeId: originalRecipeId
        )

        struct CodeRow: Decodable { let code: String }
        let row: CodeRow = try await supabase
            .from("shared_recipes")
            .upsert(snapshot, onConflict: "owner_id,source_recipe_id")
            .select("code")
            .single()
            .execute()
            .value

        guard let url = Self.oneLink(code: row.code, recipe: recipe) else {
            throw SharedRecipeError.linkUnavailable
        }
        return url
    }

    /// Loads the recipe a share link points to (works while signed out)
    func fetchRecipe(code: String) async throws -> SharedRecipe {
        let recipes: [SharedRecipe] = try await supabase
            .rpc("get_shared_recipe", params: ["p_code": code])
            .execute()
            .value

        guard let recipe = recipes.first else {
            throw SharedRecipeError.notFound
        }
        return recipe
    }

    /// Long OneLink URL carrying the code, plus the title/photo shown in message previews
    /// (iMessage, WhatsApp...). Opens Salt, or the App Store and then the recipe after install.
    static func oneLink(code: String, recipe: RecipeDetail) -> URL? {
        guard !AppsFlyerConfig.oneLinkTemplateID.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = AppsFlyerConfig.oneLinkDomain
        components.path = "/\(AppsFlyerConfig.oneLinkTemplateID)"

        var queryItems = [
            URLQueryItem(name: "pid", value: "af_app_invites"),
            URLQueryItem(name: "c", value: "recipe_share"),
            URLQueryItem(name: "deep_link_value", value: SharedRecipeRouter.deepLinkValue),
            URLQueryItem(name: SharedRecipeRouter.codeParameter, value: code),
            URLQueryItem(name: "af_og_title", value: recipe.title),
            URLQueryItem(name: "af_og_description", value: "Get this recipe on Salt")
        ]
        if let image = recipe.images.first, !image.isEmpty {
            queryItems.append(URLQueryItem(name: "af_og_image", value: image))
        }
        components.queryItems = queryItems
        return components.url
    }
}

// MARK: - Errors

enum SharedRecipeError: LocalizedError {
    case notFound
    case linkUnavailable

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "This recipe is no longer available"
        case .linkUnavailable:
            return "Recipe sharing isn't available right now"
        }
    }
}
