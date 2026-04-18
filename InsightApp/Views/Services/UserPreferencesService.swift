//
//  UserPreferencesService.swift
//  InsightApp
//
//  Central store for user preferences. All values are persisted to UserDefaults
//  and exposed as @Published so any ObservableObject subscriber reacts immediately.
//

import Foundation
import Combine

final class UserPreferencesService: ObservableObject {
    static let shared = UserPreferencesService()

    private let defaults = UserDefaults.standard

    // MARK: - Preferences

    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }

    @Published var voiceGuidanceEnabled: Bool {
        didSet { defaults.set(voiceGuidanceEnabled, forKey: Keys.voice) }
    }

    @Published var screenlessModeEnabled: Bool {
        didSet { defaults.set(screenlessModeEnabled, forKey: Keys.screenless) }
    }

    // MARK: - Init

    private init() {
        hapticsEnabled        = defaults.object(forKey: Keys.haptics)    as? Bool ?? true
        voiceGuidanceEnabled  = defaults.object(forKey: Keys.voice)      as? Bool ?? false
        screenlessModeEnabled = defaults.object(forKey: Keys.screenless) as? Bool ?? false
    }

    // MARK: - Keys

    private enum Keys {
        static let haptics    = "insight.pref.haptics"
        static let voice      = "insight.pref.voice"
        static let screenless = "insight.pref.screenless"
    }
}
