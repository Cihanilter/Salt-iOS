//
//  RecipeService.swift
//  Salt
//
//  Service for managing bookmarks and user recipes
//

import Foundation
import Supabase
import UIKit

// MARK: - Recipe Service

class RecipeService {
    static let shared = RecipeService()

    private var supabase: SupabaseClient {
        SupabaseClientManager.shared.client
    }

    private init() {}

    // MARK: - Bookmarks

    /// Get all bookmarked recipe IDs for current user
    func getBookmarkedRecipeIds() async throws -> Set<UUID> {
        guard let userId = try? await supabase.auth.session.user.id else {
            return []
        }

        let bookmarks: [RecipeBookmark] = try await supabase
            .from("user_recipe_bookmarks")
            .select("id, user_id, recipe_id, bookmarked_at, is_favorite")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        return Set(bookmarks.map { $0.recipeId })
    }

    /// Get all bookmarked recipes with full details (single query using FK relationship)
    func getBookmarkedRecipes() async throws -> [Recipe] {
        guard let userId = try? await supabase.auth.session.user.id else {
            return []
        }

        // Single query with FK relationship - recipes embedded in response
        let response = try await supabase
            .from("user_recipe_bookmarks")
            .select("bookmarked_at, recipes(*)")
            .eq("user_id", value: userId.uuidString)
            .order("bookmarked_at", ascending: false)
            .execute()

        // Decode response with embedded recipes
        let bookmarksWithRecipes = try JSONDecoder().decode([BookmarkWithRecipe].self, from: response.data)
        return bookmarksWithRecipes.compactMap { $0.recipes }
    }

    /// Add bookmark
    func addBookmark(recipeId: UUID) async throws {
        guard let userId = try? await supabase.auth.session.user.id else {
            throw RecipeServiceError.notAuthenticated
        }

        let bookmarkData: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "recipe_id": .string(recipeId.uuidString)
        ]

        try await supabase
            .from("user_recipe_bookmarks")
            .insert(bookmarkData)
            .execute()
    }

    /// Remove bookmark
    func removeBookmark(recipeId: UUID) async throws {
        guard let userId = try? await supabase.auth.session.user.id else {
            throw RecipeServiceError.notAuthenticated
        }

        try await supabase
            .from("user_recipe_bookmarks")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("recipe_id", value: recipeId.uuidString)
            .execute()
    }

    /// Toggle bookmark
    func toggleBookmark(recipeId: UUID) async throws -> Bool {
        let bookmarkedIds = try await getBookmarkedRecipeIds()
        let isBookmarked = bookmarkedIds.contains(recipeId)

        if isBookmarked {
            try await removeBookmark(recipeId: recipeId)
            return false
        } else {
            try await addBookmark(recipeId: recipeId)
            return true
        }
    }

    // MARK: - User Recipes

    /// Get all user-created recipes
    func getUserRecipes() async throws -> [UserRecipe] {
        guard let userId = try? await supabase.auth.session.user.id else {
            return []
        }

        let recipes: [UserRecipe] = try await supabase
            .from("user_recipes")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        return recipes
    }

    /// Get user recipes count
    func getUserRecipesCount() async throws -> Int {
        guard let userId = try? await supabase.auth.session.user.id else {
            return 0
        }

        let response = try await supabase
            .from("user_recipes")
            .select("id", head: true, count: .exact)
            .eq("user_id", value: userId.uuidString)
            .execute()

        return response.count ?? 0
    }

    /// Create a new user recipe
    func createRecipe(_ recipe: UserRecipe) async throws -> UserRecipe {
        guard let userId = try? await supabase.auth.session.user.id else {
            throw RecipeServiceError.notAuthenticated
        }

        // Build recipe data matching user_recipes table schema
        var recipeData: [String: AnyJSON] = [
            "id": .string(recipe.id.uuidString),
            "user_id": .string(userId.uuidString),
            "title": .string(recipe.title),
            "description": recipe.description.map { .string($0) } ?? .null,
            "image_url": recipe.imageUrl.map { .string($0) } ?? .null,
            "prep_time_minutes": recipe.prepTimeMinutes.map { .integer($0) } ?? .null,
            "cook_time_minutes": recipe.cookTimeMinutes.map { .integer($0) } ?? .null,
            "total_time_minutes": recipe.totalTimeMinutes.map { .integer($0) } ?? .null,
            "servings": recipe.servings.map { .integer($0) } ?? .null,
            "servings_text": recipe.servingsText.map { .string($0) } ?? .null,
            "ingredients": .array(recipe.ingredients.map { .string($0) }),
            "instructions": .array(recipe.instructions.map { .string($0) }),
            "cuisines": recipe.cuisines.map { .array($0.map { .string($0) }) } ?? .null,
            "notes": recipe.notes.map { .string($0) } ?? .null,
            "source_url": recipe.sourceUrl.map { .string($0) } ?? .null,
            "photos": recipe.photos.map { .array($0.map { .string($0) }) } ?? .null
        ]

        // Set source based on origin
        if let sourceUrl = recipe.sourceUrl?.lowercased() {
            if sourceUrl.contains("instagram") {
                recipeData["source"] = .string("imported_instagram")
            } else if sourceUrl.contains("youtube") || sourceUrl.contains("youtu.be") {
                recipeData["source"] = .string("imported_youtube")
            } else if sourceUrl.contains("tiktok") {
                recipeData["source"] = .string("imported_tiktok")
            } else {
                recipeData["source"] = .string("imported_web")
            }
        } else {
            recipeData["source"] = .string("manual")
        }

        let created: [UserRecipe] = try await supabase
            .from("user_recipes")
            .insert(recipeData)
            .select()
            .execute()
            .value

        return created.first ?? recipe
    }

    /// Update an existing user recipe
    func updateRecipe(_ recipe: UserRecipe) async throws {
        guard let userId = try? await supabase.auth.session.user.id else {
            throw RecipeServiceError.notAuthenticated
        }

        let recipeData: [String: AnyJSON] = [
            "title": .string(recipe.title),
            "description": recipe.description.map { .string($0) } ?? .null,
            "image_url": recipe.imageUrl.map { .string($0) } ?? .null,
            "prep_time_minutes": recipe.prepTimeMinutes.map { .integer($0) } ?? .null,
            "cook_time_minutes": recipe.cookTimeMinutes.map { .integer($0) } ?? .null,
            "total_time_minutes": recipe.totalTimeMinutes.map { .integer($0) } ?? .null,
            "servings": recipe.servings.map { .integer($0) } ?? .null,
            "servings_text": recipe.servingsText.map { .string($0) } ?? .null,
            "ingredients": .array(recipe.ingredients.map { .string($0) }),
            "instructions": .array(recipe.instructions.map { .string($0) }),
            "cuisines": recipe.cuisines.map { .array($0.map { .string($0) }) } ?? .null,
            "dish_types": recipe.dishTypes.map { .array($0.map { .string($0) }) } ?? .null,
            "notes": recipe.notes.map { .string($0) } ?? .null,
            "photos": recipe.photos.map { .array($0.map { .string($0) }) } ?? .null
        ]

        try await supabase
            .from("user_recipes")
            .update(recipeData)
            .eq("id", value: recipe.id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    /// Delete a user recipe
    func deleteRecipe(_ recipeId: UUID) async throws {
        guard let userId = try? await supabase.auth.session.user.id else {
            throw RecipeServiceError.notAuthenticated
        }

        try await supabase
            .from("user_recipes")
            .delete()
            .eq("id", value: recipeId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    /// Save imported recipe as user recipe
    func saveImportedRecipe(_ recipe: ImportedRecipe) async throws -> UserRecipe {
        guard let userId = try? await supabase.auth.session.user.id else {
            throw RecipeServiceError.notAuthenticated
        }

        let recipeId = UUID()
        var finalImageUrl = recipe.imageUrl
        var finalPhotos: [String]? = recipe.imageUrl != nil ? [recipe.imageUrl!] : nil

        // If image URL is from temporary CDN (Instagram, TikTok, etc.), re-upload to Supabase Storage
        if let imageUrl = recipe.imageUrl, isTemporaryUrl(imageUrl) {
            print("📸 Detected temporary image URL, re-uploading to Supabase Storage...")
            if let permanentUrl = try? await uploadImageFromUrl(imageUrl, recipeId: recipeId) {
                finalImageUrl = permanentUrl
                finalPhotos = [permanentUrl]
                print("✅ Image re-uploaded successfully: \(permanentUrl)")
            } else {
                print("⚠️ Failed to re-upload image, using original URL (may expire)")
            }
        }

        let userRecipe = UserRecipe(
            id: recipeId,
            userId: userId,
            createdAt: nil,
            updatedAt: nil,
            title: recipe.title,
            description: recipe.description,
            imageUrl: finalImageUrl,
            prepTimeMinutes: recipe.prepTimeMinutes,
            cookTimeMinutes: recipe.cookTimeMinutes,
            totalTimeMinutes: recipe.totalTimeMinutes,
            servings: nil,
            servingsText: recipe.servings,
            ingredients: recipe.ingredients,
            instructions: recipe.instructions,
            cuisines: nil,
            dishTypes: nil,
            notes: nil,
            sourceUrl: recipe.sourceUrl,
            sourceName: recipe.sourceName,
            photos: finalPhotos
        )

        return try await createRecipe(userRecipe)
    }

    /// Save RecipeDetail as user recipe (used when recipe was edited in preview)
    func saveRecipeDetail(_ recipeDetail: RecipeDetail, sourceUrl: String? = nil) async throws -> UserRecipe {
        guard let userId = try? await supabase.auth.session.user.id else {
            throw RecipeServiceError.notAuthenticated
        }

        let recipeId = UUID()

        // Parse servings from string
        let servingsInt = Int(recipeDetail.servings.components(separatedBy: CharacterSet.decimalDigits.inverted).joined())

        // Calculate total time
        let prepMinutes = Int(recipeDetail.prepTime)
        let cookMinutes = Int(recipeDetail.cookTime)
        let totalMinutes: Int?
        if let prep = prepMinutes, let cook = cookMinutes {
            totalMinutes = prep + cook
        } else {
            totalMinutes = prepMinutes ?? cookMinutes
        }

        // Re-upload temporary images to Supabase Storage
        var finalImages: [String] = []
        for (index, imageUrl) in recipeDetail.images.enumerated() {
            if isTemporaryUrl(imageUrl) {
                print("📸 Re-uploading temporary image \(index + 1)/\(recipeDetail.images.count)...")
                if let permanentUrl = try? await uploadImageFromUrl(imageUrl, recipeId: recipeId) {
                    finalImages.append(permanentUrl)
                    print("✅ Image \(index + 1) re-uploaded successfully")
                } else {
                    // Keep original URL as fallback (may expire)
                    finalImages.append(imageUrl)
                    print("⚠️ Failed to re-upload image \(index + 1), using original URL")
                }
            } else {
                finalImages.append(imageUrl)
            }
        }

        let userRecipe = UserRecipe(
            id: recipeId,
            userId: userId,
            createdAt: nil,
            updatedAt: nil,
            title: recipeDetail.title,
            description: recipeDetail.description == "No description" ? nil : recipeDetail.description,
            imageUrl: finalImages.first,
            prepTimeMinutes: prepMinutes,
            cookTimeMinutes: cookMinutes,
            totalTimeMinutes: totalMinutes,
            servings: servingsInt,
            servingsText: recipeDetail.servings,
            ingredients: recipeDetail.ingredients,
            instructions: recipeDetail.instructions,
            cuisines: nil,
            dishTypes: nil,
            notes: recipeDetail.notes == "Enjoy this delicious recipe!" ? nil : recipeDetail.notes,
            sourceUrl: sourceUrl,
            sourceName: nil,
            photos: finalImages.isEmpty ? nil : finalImages
        )

        return try await createRecipe(userRecipe)
    }
}

// MARK: - Bookmark With Recipe (for FK relationship query)

private struct BookmarkWithRecipe: Codable {
    let bookmarkedAt: String?
    let recipes: Recipe?

    enum CodingKeys: String, CodingKey {
        case bookmarkedAt = "bookmarked_at"
        case recipes
    }
}

// MARK: - Errors

enum RecipeServiceError: LocalizedError {
    case notAuthenticated
    case recipeNotFound
    case saveFailed(String)
    case imageUploadFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to continue"
        case .recipeNotFound:
            return "Recipe not found"
        case .saveFailed(let message):
            return "Failed to save recipe: \(message)"
        case .imageUploadFailed:
            return "Failed to upload recipe image"
        }
    }
}

// MARK: - Recipe Image Upload Extension

extension RecipeService {
    /// Upload recipe images to Supabase Storage (parallel upload for speed)
    func uploadRecipeImages(_ images: [UIImage], recipeId: UUID) async throws -> [String] {
        guard let userId = try? await supabase.auth.session.user.id else {
            throw RecipeServiceError.notAuthenticated
        }

        // Guard against corrupted arrays
        guard images.count < 50 else {
            print("❌ Invalid image count: \(images.count), skipping upload")
            return []
        }

        guard !images.isEmpty else {
            return []
        }

        // Prepare image data before parallel upload
        let imageDataPairs: [(Int, Data)] = images.enumerated().compactMap { index, image in
            guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }
            return (index, data)
        }

        // Upload all images in parallel using TaskGroup
        let uploadedUrls = await withTaskGroup(of: (Int, String)?.self, returning: [String].self) { group in
            for (index, imageData) in imageDataPairs {
                group.addTask {
                    do {
                        let filePath = "\(userId.uuidString)/\(recipeId.uuidString)/\(index).jpg"

                        try await self.supabase.storage
                            .from("recipe-images")
                            .upload(
                                path: filePath,
                                file: imageData,
                                options: FileOptions(
                                    contentType: "image/jpeg",
                                    upsert: true
                                )
                            )

                        let publicUrl = try self.supabase.storage
                            .from("recipe-images")
                            .getPublicURL(path: filePath)

                        return (index, publicUrl.absoluteString)
                    } catch {
                        print("❌ Failed to upload image \(index): \(error)")
                        return nil
                    }
                }
            }

            // Collect results and sort by index to maintain order
            var results: [(Int, String)] = []
            for await result in group {
                if let result = result {
                    results.append(result)
                }
            }

            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        print("✅ Uploaded \(uploadedUrls.count) images in parallel")
        return uploadedUrls
    }

    /// Download image from URL and upload to Supabase Storage
    /// Used for imported recipes with temporary URLs (Instagram, TikTok, etc.)
    func uploadImageFromUrl(_ imageUrl: String, recipeId: UUID) async throws -> String? {
        guard let userId = try? await supabase.auth.session.user.id else {
            throw RecipeServiceError.notAuthenticated
        }

        guard let url = URL(string: imageUrl) else {
            print("❌ Invalid image URL: \(imageUrl)")
            return nil
        }

        do {
            // Download image data
            let (data, response) = try await URLSession.shared.data(from: url)

            // Check response
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ Failed to download image: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }

            // Verify it's actually image data
            guard data.count > 1000 else {
                print("❌ Downloaded data too small, likely not an image")
                return nil
            }

            // Upload to Supabase Storage
            let filePath = "\(userId.uuidString)/\(recipeId.uuidString)/imported.jpg"

            try await supabase.storage
                .from("recipe-images")
                .upload(
                    path: filePath,
                    file: data,
                    options: FileOptions(
                        contentType: "image/jpeg",
                        upsert: true
                    )
                )

            let publicUrl = try supabase.storage
                .from("recipe-images")
                .getPublicURL(path: filePath)

            print("✅ Re-uploaded imported image to Supabase Storage")
            return publicUrl.absoluteString
        } catch {
            print("❌ Failed to re-upload image: \(error)")
            return nil
        }
    }

    /// Check if URL is temporary (social media CDN)
    private func isTemporaryUrl(_ url: String) -> Bool {
        let temporaryHosts = [
            "cdninstagram.com",
            "instagram.com",
            "fbcdn.net",
            "tiktokcdn.com",
            "tiktok.com",
            "pinimg.com"
        ]
        return temporaryHosts.contains { url.contains($0) }
    }
}
