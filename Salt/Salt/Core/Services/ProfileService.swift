//
//  ProfileService.swift
//  Salt
//
//  Service for managing user profiles
//

import Foundation
import Supabase
import UIKit

// MARK: - Profile Data Model

struct Profile: Codable {
    let id: UUID
    var fullName: String?
    var email: String?
    var createdAt: String?
    var updatedAt: String?
    var profileImageUrl: String?
    var bio: String?
    var aboutMe: String?
    var location: String?
    var favoriteCuisines: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case email
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case profileImageUrl = "profile_image_url"
        case bio
        case aboutMe = "about_me"
        case location
        case favoriteCuisines = "favorite_cuisines"
    }
}

// MARK: - Profile Service

class ProfileService {
    static let shared = ProfileService()

    private var supabase: SupabaseClient {
        SupabaseClientManager.shared.client
    }

    private init() {}

    // MARK: - Get Profile

    func getProfile() async throws -> Profile? {
        guard let userId = try? await supabase.auth.session.user.id else {
            return nil
        }

        let profiles: [Profile] = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .execute()
            .value

        return profiles.first
    }

    // MARK: - Create or Update Profile

    func upsertProfile(
        fullName: String?,
        bio: String?,
        aboutMe: String?,
        location: String?,
        favoriteCuisines: [String]?,
        profileImageUrl: String? = nil
    ) async throws {
        guard let session = try? await supabase.auth.session else {
            throw ProfileServiceError.notAuthenticated
        }

        let userId = session.user.id
        let userEmail = session.user.email ?? ""

        var profileData: [String: AnyJSON] = [
            "id": .string(userId.uuidString),
            "email": .string(userEmail),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]

        if let fullName = fullName {
            profileData["full_name"] = .string(fullName)
        }
        if let bio = bio {
            profileData["bio"] = .string(bio)
        }
        if let aboutMe = aboutMe {
            profileData["about_me"] = .string(aboutMe)
        }
        if let location = location {
            profileData["location"] = .string(location)
        }
        if let cuisines = favoriteCuisines {
            profileData["favorite_cuisines"] = .array(cuisines.map { .string($0) })
        }
        if let imageUrl = profileImageUrl {
            profileData["profile_image_url"] = .string(imageUrl)
        }

        try await supabase
            .from("profiles")
            .upsert(profileData)
            .execute()
    }

    // MARK: - Upload Profile Image

    func uploadProfileImage(_ image: UIImage) async throws -> String {
        guard let userId = try? await supabase.auth.session.user.id else {
            throw ProfileServiceError.notAuthenticated
        }

        // Compress image
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw ProfileServiceError.imageProcessingFailed
        }

        // Create file path: userId/profile.jpg
        let filePath = "\(userId.uuidString)/profile.jpg"

        // Upload to Supabase Storage
        try await supabase.storage
            .from("profile-images")
            .upload(
                path: filePath,
                file: imageData,
                options: FileOptions(
                    contentType: "image/jpeg",
                    upsert: true
                )
            )

        // Get public URL
        let publicUrl = try supabase.storage
            .from("profile-images")
            .getPublicURL(path: filePath)

        return publicUrl.absoluteString
    }

    // MARK: - Update Profile Image URL

    func updateProfileImageUrl(_ url: String) async throws {
        guard let userId = try? await supabase.auth.session.user.id else {
            throw ProfileServiceError.notAuthenticated
        }

        let updateData: [String: AnyJSON] = [
            "profile_image_url": .string(url),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]

        try await supabase
            .from("profiles")
            .update(updateData)
            .eq("id", value: userId.uuidString)
            .execute()
    }
}

// MARK: - Errors

enum ProfileServiceError: LocalizedError {
    case notAuthenticated
    case imageProcessingFailed
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to continue"
        case .imageProcessingFailed:
            return "Failed to process image"
        case .uploadFailed(let message):
            return "Failed to upload image: \(message)"
        }
    }
}
