//
//  AccessibilityProfile.swift
//  InsightApp
//

import Foundation

enum AccessibilityProfile: String, CaseIterable, Codable, Identifiable {
    case standard       = "standard"
    case wheelchair     = "wheelchair"
    case elderly        = "elderly"
    case reducedMobility = "reduced_mobility"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:        return "Estándar"
        case .wheelchair:      return "Silla de ruedas"
        case .elderly:         return "Adulto mayor"
        case .reducedMobility: return "Movilidad reducida"
        }
    }

    var icon: String {
        switch self {
        case .standard:        return "person.fill"
        case .wheelchair:      return "figure.roll"
        case .elderly:         return "figure.walk.circle"
        case .reducedMobility: return "figure.walk"
        }
    }

    /// Maps AccessibilityOption selections to the most representative profile.
    static func from(options: Set<AccessibilityOption>) -> AccessibilityProfile {
        if options.contains(.wheelchairUser) { return .wheelchair }
        if options.contains(.elderly)        { return .elderly }
        if options.contains(.limitedMobility){ return .reducedMobility }
        return .standard
    }
}
