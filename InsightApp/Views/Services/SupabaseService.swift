//
//  SupabaseService.swift
//  InsightApp
//
//  Uses Supabase PostgREST REST API directly via URLSession — no SPM package needed.
//  Credentials live in SupabaseConfig.swift (git-ignored). Copy from SupabaseConfig.swift.example.
//

import Foundation
import CoreLocation
import UIKit

// MARK: - Wire transfer types

private struct TilePayload: Encodable {
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
}

// RemoteTile is defined in Models/RemoteTile.swift

private struct ProfilePayload: Encodable {
    let device_id: String
    let user_id: String?
    let first_name: String?
    let last_name: String?
    let phone: String?
    let accessibility_profile: String
}

private struct RemoteProfile: Decodable {
    let accessibility_profile: String
}

// MARK: - Service

final class SupabaseService {
    static let shared = SupabaseService()
    private init() {}

    private var deviceID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    // MARK: Save tile

    func saveTile(_ tile: AccessibilityTile, label: String, profile: AccessibilityProfile) async {
        guard SupabaseConfig.projectURL != "https://YOUR_PROJECT_ID.supabase.co" else { return }

        let payload = TilePayload(
            latitude:           tile.coordinate.latitude,
            longitude:          tile.coordinate.longitude,
            accessibility_score: tile.accessibilityScore,
            confidence_score:   tile.confidenceScore,
            reasons:            tile.reasons,
            is_user_scanned:    tile.isUserScanned,
            is_simulated:       false,
            source:             tile.isUserScanned ? "camera" : "mock",
            label:              label,
            device_id:          deviceID,
            profile_used:       profile.rawValue
        )

        do {
            var request = makeRequest(path: "/rest/v1/accessibility_tiles", method: "POST")
            request.httpBody = try JSONEncoder().encode(payload)
            _ = try await URLSession.shared.data(for: request)
        } catch {
            // fire-and-forget — silent failure is acceptable
        }
    }

    // MARK: Fetch nearby tiles

    func fetchNearbyTiles(
        lat: Double,
        lng: Double,
        radiusDeg: Double = 0.015
    ) async -> [AccessibilityTile] {
        guard SupabaseConfig.projectURL != "https://YOUR_PROJECT_ID.supabase.co" else { return [] }

        let minLat = lat - radiusDeg
        let maxLat = lat + radiusDeg
        let minLng = lng - radiusDeg
        let maxLng = lng + radiusDeg

        let query = "latitude=gte.\(minLat)&latitude=lte.\(maxLat)" +
                    "&longitude=gte.\(minLng)&longitude=lte.\(maxLng)" +
                    "&is_simulated=eq.false"

        var request = makeRequest(path: "/rest/v1/accessibility_tiles?\(query)", method: "GET")
        request.httpBody = nil

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let remote = try JSONDecoder().decode([RemoteTile].self, from: data)
            return remote.map { $0.toAccessibilityTile() }
        } catch {
            return []
        }
    }

    // MARK: Save profile

    func saveProfile(_ profile: AccessibilityProfile) async {
        guard SupabaseConfig.projectURL != "https://YOUR_PROJECT_ID.supabase.co" else { return }

        let payload = ProfilePayload(
            device_id:             deviceID,
            user_id:               AuthService.shared.currentUser?.id,
            first_name:            AuthService.shared.currentUser?.firstName,
            last_name:             AuthService.shared.currentUser?.lastName,
            phone:                 AuthService.shared.currentUser?.phone,
            accessibility_profile: profile.rawValue
        )

        do {
            var request = makeRequest(path: "/rest/v1/user_profiles", method: "POST")
            // upsert: overwrite if device_id already exists
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONEncoder().encode(payload)
            _ = try await URLSession.shared.data(for: request)
        } catch {
            // fire-and-forget
        }
    }

    // MARK: Fetch profile

    func fetchProfile() async -> AccessibilityProfile? {
        guard SupabaseConfig.projectURL != "https://YOUR_PROJECT_ID.supabase.co" else { return nil }

        let query = "device_id=eq.\(deviceID)&limit=1"
        var request = makeRequest(path: "/rest/v1/user_profiles?\(query)", method: "GET")
        request.httpBody = nil

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let profiles = try JSONDecoder().decode([RemoteProfile].self, from: data)
            guard let first = profiles.first else { return nil }
            return AccessibilityProfile(rawValue: first.accessibility_profile)
        } catch {
            return nil
        }
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
