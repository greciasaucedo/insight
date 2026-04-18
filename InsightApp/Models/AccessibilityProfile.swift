//
//  AccessibilityProfile.swift
//  InsightApp
//

import Foundation

struct PenaltyWeights {
    var stairs:   Double
    var obstacle: Double
    var slope:    Double
    var limited:  Double
}

enum AccessibilityProfile: String, CaseIterable, Codable, Identifiable {
    case standard        = "standard"
    case wheelchair      = "wheelchair"
    case elderly         = "elderly"
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

    var penaltyWeights: PenaltyWeights {
        switch self {
        case .standard:        return PenaltyWeights(stairs: 1.0, obstacle: 1.0, slope: 1.0, limited: 1.0)
        case .wheelchair:      return PenaltyWeights(stairs: 3.0, obstacle: 2.5, slope: 1.5, limited: 2.0)
        case .reducedMobility: return PenaltyWeights(stairs: 2.0, obstacle: 2.0, slope: 2.0, limited: 2.5)
        case .elderly:         return PenaltyWeights(stairs: 2.0, obstacle: 1.5, slope: 2.5, limited: 2.0)
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
