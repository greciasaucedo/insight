//
//  Persistenceservice.swift
//  InsightApp
//
//  Serialización local de AccessibilityTile en UserDefaults.
//  CodableTile ahora incluye todos los campos del modelo expandido.
//

import Foundation
import CoreLocation

// MARK: - Codable wrappers

/// Wrapper Codable para CLLocationCoordinate2D
struct CodableCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ coord: CLLocationCoordinate2D) {
        latitude  = coord.latitude
        longitude = coord.longitude
    }
}

/// Versión Codable de AccessibilityTile para serialización en disco.
/// Los campos nuevos son opcionales para que versiones anteriores de la app
/// puedan leer datos guardados sin romper la decodificación.
struct CodableTile: Codable {
    // ── Campos originales ─────────────────────────────────────────────────
    let id: String                       // UUID string
    let coordinate: CodableCoordinate
    let accessibilityScore: Int
    let confidenceScore: Double
    let reasons: [String]
    let isUserScanned: Bool

    // ── Campos expandidos ─────────────────────────────────────────────────
    let vibrationScore: Double?
    let slopeScore: Double?
    let passabilityScore: Double?
    let sourceType: String               // TileSourceType.rawValue
    let detectedLabel: String?
    let profileUsed: String?
    let createdAt: Date                  // persiste el timestamp original

    // MARK: Init desde AccessibilityTile

    init(from tile: AccessibilityTile) {
        id                 = tile.id.uuidString
        coordinate         = CodableCoordinate(tile.coordinate)
        accessibilityScore = tile.accessibilityScore
        confidenceScore    = tile.confidenceScore
        reasons            = tile.reasons
        isUserScanned      = tile.isUserScanned
        vibrationScore     = tile.vibrationScore
        slopeScore         = tile.slopeScore
        passabilityScore   = tile.passabilityScore
        sourceType         = tile.sourceType.rawValue
        detectedLabel      = tile.detectedLabel
        profileUsed        = tile.profileUsed
        createdAt          = tile.createdAt
    }

    // MARK: Convert back

    func toTile() -> AccessibilityTile {
        AccessibilityTile(
            id:                UUID(uuidString: id) ?? UUID(),
            coordinate:        coordinate.coordinate,
            accessibilityScore: accessibilityScore,
            confidenceScore:   confidenceScore,
            reasons:           reasons,
            isUserScanned:     isUserScanned,
            vibrationScore:    vibrationScore,
            slopeScore:        slopeScore,
            passabilityScore:  passabilityScore,
            sourceType:        TileSourceType(rawValue: sourceType) ?? .camera,
            detectedLabel:     detectedLabel,
            profileUsed:       profileUsed,
            createdAt:         createdAt
        )
    }
}

// MARK: - PersistenceService

final class PersistenceService {
    static let shared = PersistenceService()
    private init() {}

    private let defaults = UserDefaults.standard

    // Bump la clave a v2 para evitar conflictos con tiles viejos que no tienen los campos nuevos.
    private let scannedKey  = "insight.scannedTiles.v2"
    private let destKey     = "insight.lastDestination.v1"
    private let profileKey  = "insight.accessibilityProfile.v1"

    // MARK: Scanned Tiles

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Persiste el array de scannedTiles al disco.
    func saveScannedTiles(_ tiles: [AccessibilityTile]) {
        let codable = tiles.map { CodableTile(from: $0) }
        if let data = try? encoder.encode(codable) {
            defaults.set(data, forKey: scannedKey)
        }
    }

    /// Restaura los scannedTiles guardados. Devuelve [] si no hay datos o falla la decodificación.
    func loadScannedTiles() -> [AccessibilityTile] {
        guard let data = defaults.data(forKey: scannedKey),
              let codable = try? decoder.decode([CodableTile].self, from: data)
        else { return [] }
        return codable.map { $0.toTile() }
    }

    // MARK: Last Destination

    func saveLastDestination(name: String) {
        defaults.set(name, forKey: destKey)
    }

    func loadLastDestination() -> String? {
        defaults.string(forKey: destKey)
    }

    // MARK: Accessibility Profile

    func saveProfile(_ profile: AccessibilityProfile) {
        defaults.set(profile.rawValue, forKey: profileKey)
    }

    func loadProfile() -> AccessibilityProfile {
        guard let raw = defaults.string(forKey: profileKey),
              let profile = AccessibilityProfile(rawValue: raw) else { return .standard }
        return profile
    }

    // MARK: Clear (útil para tests / reset en ajustes)

    func clearAll() {
        [scannedKey, destKey, profileKey].forEach { defaults.removeObject(forKey: $0) }
    }
}
