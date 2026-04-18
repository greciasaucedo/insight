//
//  RemoteTile.swift
//  InsightApp
//



import Foundation
import CoreLocation

struct RemoteTile: Decodable {

    // ── Columnas existentes en el schema real ────────────────────────────
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
    let created_at: String?    // timestamptz — ya existía
    let device_id: String?     // ya existía
    let profile_used: String?  // ya existía
    let user_id: String?       // ya existía

    // ── Columnas nuevas (opcionales para retrocompatibilidad) ────────────

    /// Suavidad de superficie captada por acelerómetro. 0.0 (máx vibración) – 1.0 (liso).
    let vibration_score: Double?

    /// Planitud captada por giroscopio. 0.0 (muy inclinado) – 1.0 (plano).
    let slope_score: Double?

    /// Estimación combinada de transitabilidad. 0.0 (intransitable) – 1.0 (óptimo).
    let passability_score: Double?

    /// URL pública de la foto tomada durante el escaneo (Supabase Storage, bucket scan-images).
    let scan_image_url: String?

    // MARK: - Conversion

    func toAccessibilityTile() -> AccessibilityTile {
        let date   = Self.parseDate(created_at) ?? Date()
        let srcType = TileSourceType(rawValue: source ?? "") ?? .remote

        return AccessibilityTile(
            coordinate:        CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            accessibilityScore: accessibility_score,
            confidenceScore:   confidence_score,
            reasons:           reasons,
            isUserScanned:     is_user_scanned,
            vibrationScore:    vibration_score,
            slopeScore:        slope_score,
            passabilityScore:  passability_score,
            sourceType:        srcType,
            detectedLabel:     label,
            profileUsed:       profile_used,
            createdAt:         date,
            scanImageURL:      scan_image_url
        )
    }

    // MARK: - Helpers

    /// Soporta el formato ISO completo de Postgres ("2025-04-18T10:30:00+00:00")
    /// y la variante con fracciones de segundo o con Z.
    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }
}
