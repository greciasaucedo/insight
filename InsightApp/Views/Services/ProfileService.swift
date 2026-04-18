//
//  ProfileService.swift
//  InsightApp
//

import Foundation

final class ProfileService {
    static let shared = ProfileService()
    private init() {}

    private let key = "insight.accessibilityProfile.v1"

    var current: AccessibilityProfile {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let profile = AccessibilityProfile(rawValue: raw) else { return .standard }
            return profile
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
