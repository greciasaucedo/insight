//
//  Persistenceservice.swift
//  InsightApp
//
//  Created by Guillermo Lira on 18/04/26.
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

/// Versión Codable de AccessibilityTile para serialización
struct CodableTile: Codable {
    let id: String              // UUID string
    let coordinate: CodableCoordinate
    let accessibilityScore: Int
    let confidenceScore: Double
    let reasons: [String]
    let isUserScanned: Bool

    init(from tile: AccessibilityTile) {
        id                = tile.id.uuidString
        coordinate        = CodableCoordinate(tile.coordinate)
        accessibilityScore = tile.accessibilityScore
        confidenceScore   = tile.confidenceScore
        reasons           = tile.reasons
        isUserScanned     = tile.isUserScanned
    }

    func toTile() -> AccessibilityTile {
        AccessibilityTile(
            coordinate:        coordinate.coordinate,
            accessibilityScore: accessibilityScore,
            confidenceScore:   confidenceScore,
            reasons:           reasons,
            isUserScanned:     isUserScanned
        )
    }
}

// MARK: - PersistenceService

final class PersistenceService {
    static let shared = PersistenceService()
    private init() {}

    private let defaults = UserDefaults.standard
    private let scannedKey     = "insight.scannedTiles.v1"
    private let destKey        = "insight.lastDestination.v1"
    private let profileKey     = "insight.accessibilityProfile.v1"

    // MARK: Scanned Tiles

    /// Persiste el array de scannedTiles al disco.
    /// Se debe llamar cada vez que se agrega un tile nuevo.
    func saveScannedTiles(_ tiles: [AccessibilityTile]) {
        let codable = tiles.map { CodableTile(from: $0) }
        if let data = try? JSONEncoder().encode(codable) {
            defaults.set(data, forKey: scannedKey)
        }
    }

    /// Restaura los scannedTiles guardados. Devuelve [] si no hay nada o falla la decodificación.
    func loadScannedTiles() -> [AccessibilityTile] {
        guard let data = defaults.data(forKey: scannedKey),
              let codable = try? JSONDecoder().decode([CodableTile].self, from: data)
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

    // MARK: Accessibility Profile (para futuro uso)
    // Guarda el nombre del perfil elegido en Onboarding, útil para personalizar
    // las penalizaciones de RouteEngine según el tipo de usuario.

    func saveProfile(_ profile: String) {
        defaults.set(profile, forKey: profileKey)
    }

    func loadProfile() -> String? {
        defaults.string(forKey: profileKey)
    }

    // MARK: Clear (útil para tests / reset en ajustes)

    func clearAll() {
        [scannedKey, destKey, profileKey].forEach { defaults.removeObject(forKey: $0) }
    }
}
