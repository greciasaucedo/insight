//
//  AccessibilityScoringService.swift
//  InsightApp
//

import Foundation

struct AccessibilityScoringService {

    /// Returns the penalty points (positive integer) to subtract from a route score
    /// based on the tile's accessibility level, its detected label, and the user's profile.
    static func penalty(
        for level: AccessibilityLevel,
        label: String?,
        profile: AccessibilityProfile
    ) -> Int {
        let lowerLabel = label?.lowercased()

        switch profile {

        case .wheelchair:
            if lowerLabel == "stairs"   { return 50 }
            if lowerLabel == "obstacle" { return 45 }
            if level == .notAccessible  { return 40 }
            if level == .limited        { return 20 }

        case .elderly:
            if lowerLabel == "stairs"   { return 40 }
            if lowerLabel == "obstacle" { return 35 }
            if level == .notAccessible  { return 35 }
            if level == .limited        { return 18 }

        case .reducedMobility:
            if lowerLabel == "stairs"   { return 35 }
            if lowerLabel == "obstacle" { return 30 }
            if level == .notAccessible  { return 30 }
            if level == .limited        { return 15 }

        case .standard:
            if level == .notAccessible  { return 25 }
            if level == .limited        { return 10 }
        }

        return 0
    }

    /// Returns a Double penalty to subtract from the route score, using profile-specific
    /// multipliers from PenaltyWeights. Confidence and user-scanned adjustments are included.
    static func adjustedPenalty(for tile: AccessibilityTile, profile: AccessibilityProfile) -> Double {
        let weights = profile.penaltyWeights
        let label   = tile.reasons.first?.lowercased()
        let level   = tile.accessibilityLevel

        var base: Double
        if      label == "stairs"        { base = 20.0 * weights.stairs }
        else if label == "obstacle"      { base = 20.0 * weights.obstacle }
        else if label == "slope"         { base = 15.0 * weights.slope }
        else if level == .notAccessible  { base = 20.0 * weights.limited }
        else if level == .limited        { base = 10.0 * weights.limited }
        else { return 0 }

        if tile.isUserScanned         { base *= 1.4 }
        if tile.confidenceScore < 0.4 { base *= 0.6 }
        return base
    }

    /// Returns a human-readable explanation for why this tile impacted the route,
    /// tailored to the user's profile. Returns nil when no specific message applies.
    static func explanationMessage(
        for label: String?,
        profile: AccessibilityProfile
    ) -> String? {
        let lowerLabel = label?.lowercased()
        switch profile {
        case .wheelchair:
            if lowerLabel == "stairs"   { return "Se evitaron escaleras por el perfil seleccionado." }
            if lowerLabel == "obstacle" { return "Se evitó un obstáculo detectado en la ruta." }
            return "Se priorizó accesibilidad para silla de ruedas."
        case .elderly:
            return "Se priorizó una ruta con menor esfuerzo físico."
        case .reducedMobility:
            return "Se evitaron tramos de difícil tránsito."
        case .standard:
            return nil
        }
    }
}
