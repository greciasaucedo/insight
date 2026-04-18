//
//  AuthUser.swift
//  InsightApp
//

import Foundation

struct AuthUser: Codable {
    let id: String
    let firstName: String
    let lastName: String
    let phone: String

    var displayName: String { "\(firstName) \(lastName)" }
}
