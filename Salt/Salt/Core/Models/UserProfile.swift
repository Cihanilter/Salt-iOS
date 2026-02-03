//
//  UserProfile.swift
//  Salt
//

import Foundation

struct UserProfile: Codable {
    let id: String
    let fullName: String
    let email: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case email
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
