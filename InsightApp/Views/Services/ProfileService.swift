//
//  ProfileService.swift
//  InsightApp
//

import Foundation
import Combine

final class ProfileService: ObservableObject {
    static let shared = ProfileService()
    private let optionsKey = "insight.profile.selectedOptions"

    private init() {
        currentProfile = PersistenceService.shared.loadProfile()
        let saved = UserDefaults.standard.stringArray(forKey: "insight.profile.selectedOptions") ?? []
        selectedOptions = saved.compactMap { AccessibilityOption(rawValue: $0) }
    }

    @Published private(set) var currentProfile: AccessibilityProfile
    @Published private(set) var selectedOptions: [AccessibilityOption] = []

    func setProfile(_ profile: AccessibilityProfile) {
        currentProfile = profile
        PersistenceService.shared.saveProfile(profile)
    }

    func setSelectedOptions(_ options: Set<AccessibilityOption>) {
        selectedOptions = Array(options)
        UserDefaults.standard.set(options.map(\.rawValue), forKey: optionsKey)
    }
}
