//
//  ProfileService.swift
//  InsightApp
//

import Foundation
import Combine

final class ProfileService: ObservableObject {
    static let shared = ProfileService()
    private init() {
        currentProfile = PersistenceService.shared.loadProfile()
    }

    @Published private(set) var currentProfile: AccessibilityProfile

    func setProfile(_ profile: AccessibilityProfile) {
        currentProfile = profile
        PersistenceService.shared.saveProfile(profile)
    }
}
