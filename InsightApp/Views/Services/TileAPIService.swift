//
//  TileAPIService.swift
//  InsightApp
//
//  Tile-specific Supabase operations con propagación completa de errores.
//  Credentials en SupabaseConfig.swift (git-ignored).
//
//  SQL schema — ejecutar una vez en el editor SQL de Supabase:
//
//  CREATE TABLE accessibility_tiles (
//    id                  uuid             PRIMARY KEY DEFAULT gen_random_uuid(),
//    latitude            double precision NOT NULL,
//    longitude           double precision NOT NULL,
//    accessibility_score integer          CHECK (accessibility_score BETWEEN 0 AND 100),
//    confidence_score    double precision CHECK (confidence_score BETWEEN 0 AND 1),
//    reasons             jsonb            DEFAULT '[]',
//    is_user_scanned     boolean          DEFAULT false,
//    is_simulated        boolean          DEFAULT false,
//    source              text,
//    label               text,
//    created_at          timestamptz      DEFAULT now(),
//    updated_at          timestamptz      DEFAULT now(),
//    -- Campos expandidos:
//    vibration_score     double precision CHECK (vibration_score BETWEEN 0 AND 1),
//    slope_score         double precision CHECK (slope_score BETWEEN 0 AND 1),
//    passability_score   double precision CHECK (passability_score BETWEEN 0 AND 1),
//    profile_used        text
//  );
//  CREATE INDEX ON accessibility_tiles (created_at);
//  CREATE INDEX ON accessibility_tiles (latitude, longitude);
//

import Foundation
import CoreLocation
import os.log
import UIKit

final class TileAPIService {
    static let shared = TileAPIService()
    private init() {}

    private let log = Logger(subsystem: "com.insight", category: "TileAPI")

    // MARK: Save

    func saveTile(_ tile: AccessibilityTile, isSimulated: Bool) async throws {
        guard SupabaseConfig.projectURL != "https://YOUR_PROJECT_ID.supabase.co",
              !SupabaseConfig.projectURL.isEmpty else { return }
        let payload = TileSavePayload(tile: tile, isSimulated: isSimulated)
        var request = makeRequest(path: "/rest/v1/accessibility_tiles", method: "POST")
        request.httpBody = try JSONEncoder().encode(payload)
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            log.error("saveTile HTTP \(http.statusCode)")
            throw URLError(.badServerResponse)
        }
    }

    // MARK: Fetch nearby tiles
    // Bounding box: lat ± (radiusKm / 111), lng ± (radiusKm / 111), is_simulated = false
    // También filtra opcionalmente por antigüedad máxima (maxAgeDays).

    func fetchNearbyTiles(
        lat: Double,
        lng: Double,
        radiusKm: Double = 1.5,
        maxAgeDays: Int? = 30
    ) async throws -> [RemoteTile] {
        guard SupabaseConfig.projectURL != "https://YOUR_PROJECT_ID.supabase.co",
              !SupabaseConfig.projectURL.isEmpty else { return [] }

        let deg = radiusKm / 111.0
        var query = "latitude=gte.\(lat - deg)&latitude=lte.\(lat + deg)" +
                    "&longitude=gte.\(lng - deg)&longitude=lte.\(lng + deg)" +
                    "&is_simulated=eq.false"

        // Filtro de recencia: ignorar datos más viejos que maxAgeDays
        if let days = maxAgeDays {
            let cutoff = ISO8601DateFormatter().string(
                from: Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            )
            query += "&created_at=gte.\(cutoff)"
        }

        // Ordenar por más reciente primero
        query += "&order=created_at.desc"

        var request = makeRequest(path: "/rest/v1/accessibility_tiles?\(query)", method: "GET")
        request.httpBody = nil
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            log.error("fetchNearbyTiles HTTP \(http.statusCode)")
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([RemoteTile].self, from: data)
    }

    // MARK: Helpers

    private func makeRequest(path: String, method: String) -> URLRequest {
        let url = URL(string: SupabaseConfig.projectURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        let bearer = AuthService.shared.accessToken ?? SupabaseConfig.anonKey
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        return request
    }
}

// MARK: - Payload

/// Payload que se envía a Supabase al guardar un tile.
/// Los nombres de campo coinciden exactamente con las columnas del schema real.
///
/// Columnas existentes:  id, latitude, longitude, accessibility_score,
///   confidence_score, reasons, is_user_scanned, is_simulated, source,
///   label, created_at, updated_at, device_id, profile_used, user_id
/// Columnas nuevas:      vibration_score, slope_score, passability_score
private struct TileSavePayload: Encodable {
    let latitude: Double
    let longitude: Double
    let accessibility_score: Int
    let confidence_score: Double
    let reasons: [String]
    let is_user_scanned: Bool
    let is_simulated: Bool
    let source: String          // TileSourceType.rawValue
    let label: String           // CoreML detected label
    let device_id: String
    let user_id: String?
    let profile_used: String    // perfil activo al escanear
    // Nuevas columnas
    let vibration_score: Double?
    let slope_score: Double?
    let passability_score: Double?

    init(tile: AccessibilityTile, isSimulated: Bool) {
        latitude             = tile.coordinate.latitude
        longitude            = tile.coordinate.longitude
        accessibility_score  = tile.accessibilityScore
        confidence_score     = tile.confidenceScore
        reasons              = tile.reasons
        is_user_scanned      = tile.isUserScanned
        self.is_simulated    = isSimulated
        source               = tile.sourceType.rawValue
        label                = tile.detectedLabel ?? tile.reasons.first ?? ""
        device_id            = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        user_id              = AuthService.shared.currentUser?.id
        profile_used         = tile.profileUsed ?? ProfileService.shared.currentProfile.rawValue
        vibration_score      = tile.vibrationScore
        slope_score          = tile.slopeScore
        passability_score    = tile.passabilityScore
    }
}
