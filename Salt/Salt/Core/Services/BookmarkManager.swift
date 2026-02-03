//
//  BookmarkManager.swift
//  Salt
//
//  Manages bookmark state across the app
//

import Foundation
import Combine

@MainActor
class BookmarkManager: ObservableObject {
    static let shared = BookmarkManager()

    @Published private(set) var bookmarkedIds: Set<UUID> = []
    @Published private(set) var isLoading = false

    private let recipeService = RecipeService.shared

    private init() {
        Task {
            await loadBookmarks()
        }
    }

    // MARK: - Load Bookmarks

    func loadBookmarks() async {
        isLoading = true
        do {
            bookmarkedIds = try await recipeService.getBookmarkedRecipeIds()
        } catch {
            print("Failed to load bookmarks: \(error)")
        }
        isLoading = false
    }

    // MARK: - Check Bookmark Status

    func isBookmarked(_ recipeId: UUID) -> Bool {
        bookmarkedIds.contains(recipeId)
    }

    // MARK: - Toggle Bookmark (Optimistic Update)

    func toggleBookmark(for recipeId: UUID) async -> Bool {
        let wasBookmarked = bookmarkedIds.contains(recipeId)
        let newState = !wasBookmarked

        // OPTIMISTIC UPDATE: Update UI immediately
        if newState {
            bookmarkedIds.insert(recipeId)
        } else {
            bookmarkedIds.remove(recipeId)
        }

        // Sync with server in background
        do {
            if newState {
                try await recipeService.addBookmark(recipeId: recipeId)
            } else {
                try await recipeService.removeBookmark(recipeId: recipeId)
            }
        } catch {
            // Rollback on error
            print("❌ Bookmark sync failed, rolling back: \(error)")
            if wasBookmarked {
                bookmarkedIds.insert(recipeId)
            } else {
                bookmarkedIds.remove(recipeId)
            }
            return wasBookmarked
        }

        return newState
    }
}
