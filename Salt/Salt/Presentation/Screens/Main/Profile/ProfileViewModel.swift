//
//  ProfileViewModel.swift
//  Salt
//
//  ViewModel for Profile screen
//

import Foundation
import Combine
import UIKit

@MainActor
class ProfileViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var userProfile: UserProfileData?
    @Published var recipesCount: Int = 0
    @Published var isLoading = false
    @Published var isEditing = false
    @Published var errorMessage: String?
    @Published var isUploadingImage = false

    // Edit mode properties
    @Published var editFullName = ""
    @Published var editBio = ""
    @Published var editAboutMe = ""
    @Published var editLocation = ""
    @Published var editFavoriteCuisines: [String] = []

    // MARK: - Private Properties

    private let authManager = AuthManager.shared
    private let recipeService = RecipeService.shared
    private let profileService = ProfileService.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Available Cuisines

    let availableCuisines = [
        "Italian", "Mexican", "Asian", "American", "French",
        "Indian", "Japanese", "Thai", "Greek", "Mediterranean",
        "Chinese", "Korean", "Vietnamese", "Spanish", "Middle Eastern",
        "Baking", "Desserts", "Healthy Eating", "Meal Prep", "Quick & Easy"
    ]

    // MARK: - Computed Properties

    var displayName: String {
        userProfile?.fullName ?? authManager.currentUser?.fullName ?? "User"
    }

    var email: String? {
        authManager.currentUser?.email
    }

    var memberSince: String? {
        guard let date = authManager.currentUser?.createdAt else {
            return nil
        }
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMMM yyyy"
        return displayFormatter.string(from: date)
    }

    // MARK: - Init

    init() {
        loadProfile()
    }

    // MARK: - Load Profile

    func loadProfile() {
        Task {
            await loadProfileFromSupabase()
            await loadRecipesCount()
        }
    }

    private func loadProfileFromSupabase() async {
        do {
            if let profile = try await profileService.getProfile() {
                userProfile = UserProfileData(
                    fullName: profile.fullName ?? authManager.currentUser?.fullName ?? "",
                    bio: profile.bio,
                    aboutMe: profile.aboutMe,
                    location: profile.location,
                    favoriteCuisines: profile.favoriteCuisines ?? [],
                    profileImageUrl: profile.profileImageUrl
                )
            } else if let user = authManager.currentUser {
                // No profile in DB yet, use auth data
                userProfile = UserProfileData(
                    fullName: user.fullName,
                    bio: nil,
                    aboutMe: nil,
                    location: nil,
                    favoriteCuisines: [],
                    profileImageUrl: nil
                )
            }
        } catch {
            print("Failed to load profile: \(error)")
            // Fallback to auth data
            if let user = authManager.currentUser {
                userProfile = UserProfileData(
                    fullName: user.fullName,
                    bio: nil,
                    aboutMe: nil,
                    location: nil,
                    favoriteCuisines: [],
                    profileImageUrl: nil
                )
            }
        }
    }

    func loadRecipesCount() async {
        do {
            recipesCount = try await recipeService.getUserRecipesCount()
        } catch {
            print("Failed to load recipes count: \(error)")
        }
    }

    // MARK: - Edit Profile

    func startEditing() {
        editFullName = userProfile?.fullName ?? ""
        editBio = userProfile?.bio ?? ""
        editAboutMe = userProfile?.aboutMe ?? ""
        editLocation = userProfile?.location ?? ""
        editFavoriteCuisines = userProfile?.favoriteCuisines ?? []
        isEditing = true
    }

    func cancelEditing() {
        isEditing = false
    }

    func saveProfile() async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            // Save to Supabase
            try await profileService.upsertProfile(
                fullName: editFullName,
                bio: editBio.isEmpty ? nil : editBio,
                aboutMe: editAboutMe.isEmpty ? nil : editAboutMe,
                location: editLocation.isEmpty ? nil : editLocation,
                favoriteCuisines: editFavoriteCuisines.isEmpty ? nil : editFavoriteCuisines
            )

            // Update local profile
            userProfile = UserProfileData(
                fullName: editFullName,
                bio: editBio.isEmpty ? nil : editBio,
                aboutMe: editAboutMe.isEmpty ? nil : editAboutMe,
                location: editLocation.isEmpty ? nil : editLocation,
                favoriteCuisines: editFavoriteCuisines,
                profileImageUrl: userProfile?.profileImageUrl
            )

            isLoading = false
            isEditing = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("Failed to save profile: \(error)")
            isLoading = false
            return false
        }
    }

    // MARK: - Upload Profile Image

    func uploadProfileImage(_ image: UIImage) async {
        isUploadingImage = true
        errorMessage = nil

        do {
            let imageUrl = try await profileService.uploadProfileImage(image)
            try await profileService.updateProfileImageUrl(imageUrl)

            // Update local profile
            userProfile?.profileImageUrl = imageUrl
            print("✅ Profile image uploaded: \(imageUrl)")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to upload profile image: \(error)")
        }

        isUploadingImage = false
    }

    func toggleCuisine(_ cuisine: String) {
        if editFavoriteCuisines.contains(cuisine) {
            editFavoriteCuisines.removeAll { $0 == cuisine }
        } else {
            editFavoriteCuisines.append(cuisine)
        }
    }

    // MARK: - Sign Out

    func signOut() {
        Task {
            do {
                try await authManager.signOut()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - User Profile Data

struct UserProfileData {
    var fullName: String
    var bio: String?
    var aboutMe: String?
    var location: String?
    var favoriteCuisines: [String]
    var profileImageUrl: String?
}
