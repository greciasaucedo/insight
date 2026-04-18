//
//  RemoteTile.swift
//  InsightApp
//

import Foundation
import CoreLocation

struct RemoteTile: Decodable {
    let id: String?
    let latitude: Double
    let longitude: Double
    let accessibility_score: Int
    let confidence_score: Double
    let reasons: [String]
    let is_user_scanned: Bool
    let is_simulated: Bool
    let source: String?
    let label: String?

    func toAccessibilityTile() -> AccessibilityTile {
        AccessibilityTile(
            coordinate:         CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            accessibilityScore: accessibility_score,
            confidenceScore:    confidence_score,
            reasons:            reasons,
            isUserScanned:      is_user_scanned
        )
    }
}
