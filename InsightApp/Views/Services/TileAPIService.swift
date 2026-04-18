//
//  TileAPIService.swift
//  InsightApp
//
//  Tile-specific Supabase operations with full error propagation.
//  Credentials live in SupabaseConfig.swift (git-ignored).
//
//  SQL schema (run once in the Supabase SQL editor):
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
//    updated_at          timestamptz      DEFAULT now()
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

    func fetchNearbyTiles(lat: Double, lng: Double, radiusKm: Double = 1.5) async throws -> [RemoteTile] {
        guard SupabaseConfig.projectURL != "https://YOUR_PROJECT_ID.supabase.co",
              !SupabaseConfig.projectURL.isEmpty else { return [] }
        let deg = radiusKm / 111.0
        let query = "latitude=gte.\(lat - deg)&latitude=lte.\(lat + deg)" +
                    "&longitude=gte.\(lng - deg)&longitude=lte.\(lng + deg)" +
                    "&is_simulated=eq.false"
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
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        return request
    }
}

// MARK: - Payload

private struct TileSavePayload: Encodable {
    let latitude: Double
    let longitude: Double
    let accessibility_score: Int
    let confidence_score: Double
    let reasons: [String]
    let is_user_scanned: Bool
    let is_simulated: Bool
    let source: String
    let label: String
    let device_id: String
    let profile_used: String

    init(tile: AccessibilityTile, isSimulated: Bool) {
        latitude            = tile.coordinate.latitude
        longitude           = tile.coordinate.longitude
        accessibility_score = tile.accessibilityScore
        confidence_score    = tile.confidenceScore
        reasons             = tile.reasons
        is_user_scanned     = tile.isUserScanned
        self.is_simulated   = isSimulated
        source              = tile.isUserScanned ? "camera" : "mock"
        label               = tile.reasons.first ?? ""
        device_id           = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        profile_used        = ProfileService.shared.currentProfile.rawValue
    }
}
