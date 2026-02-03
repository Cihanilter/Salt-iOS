//
//  SupabaseClient.swift
//  Salt
//

import Foundation
import Supabase

final class SupabaseClientManager {
    static let shared = SupabaseClientManager()

    let client: SupabaseClient

    private init() {
        guard let url = URL(string: SupabaseConfig.projectURL) else {
            fatalError("Invalid Supabase URL")
        }

        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }
}
