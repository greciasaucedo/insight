//
//  HumanValidationService.swift
//  InsightApp
//
//  FIX 1: applyUserValidation usa un método público en HeatmapStore
//         en lugar de asignar directo a scannedTiles[idx] (que es private(set))
//  FIX 2: import CoreLocation agregado
//

import Foundation
import CoreLocation

// MARK: - UserValidation

struct UserValidation: Codable {
    enum PassExperience: String, Codable, CaseIterable {
        case fine        = "fine"
        case withTrouble = "withTrouble"
        case blocked     = "blocked"

        var label: String {
            switch self {
            case .fine:        return "Sin problema"
            case .withTrouble: return "Con dificultad"
            case .blocked:     return "No pude pasar"
            }
        }

        var icon: String {
            switch self {
            case .fine:        return "checkmark.circle.fill"
            case .withTrouble: return "exclamationmark.triangle.fill"
            case .blocked:     return "xmark.circle.fill"
            }
        }

        var color: String {
            switch self {
            case .fine:        return "green"
            case .withTrouble: return "orange"
            case .blocked:     return "red"
            }
        }
    }

    enum ManualFeedbackTag: String, Codable, CaseIterable {
        case elevatorOutOfService  = "elevatorOutOfService"
        case blocked               = "blocked"
        case excessiveSlope        = "excessiveSlope"
        case brokenSurface         = "brokenSurface"
        case temporaryObstacle     = "temporaryObstacle"
        case clearAndAccessible    = "clearAndAccessible"

        var label: String {
            switch self {
            case .elevatorOutOfService: return "Elevador fuera de servicio"
            case .blocked:              return "Bloqueo en zona"
            case .excessiveSlope:       return "Pendiente excesiva"
            case .brokenSurface:        return "Superficie dañada"
            case .temporaryObstacle:    return "Obstáculo temporal"
            case .clearAndAccessible:   return "Despejado y accesible"
            }
        }

        var icon: String {
            switch self {
            case .elevatorOutOfService: return "elevator"
            case .blocked:              return "nosign"
            case .excessiveSlope:       return "angle"
            case .brokenSurface:        return "road.lanes.curved.right"
            case .temporaryObstacle:    return "cone.fill"
            case .clearAndAccessible:   return "checkmark.seal.fill"
            }
        }
    }

    let tileID: UUID
    let coordinate: CodableCoordinate
    let passExperience: PassExperience
    let manualTags: [ManualFeedbackTag]
    let freeText: String?
    let createdAt: Date
    let profile: String

    var derivedPassabilityScore: Double {
        switch passExperience {
        case .fine:        return 0.90
        case .withTrouble: return 0.45
        case .blocked:     return 0.05
        }
    }

    var isPositive: Bool { passExperience == .fine }
}

// MARK: - HumanValidationService

final class HumanValidationService {
    static let shared = HumanValidationService()
    private init() {}

    private let defaults   = UserDefaults.standard
    private let storageKey = "insight.userValidations.v1"

    func save(_ validation: UserValidation) {
        var all = loadAll()
        all.removeAll { v in
            v.tileID == validation.tileID &&
            Calendar.current.isDate(v.createdAt, inSameDayAs: validation.createdAt)
        }
        all.append(validation)
        persist(all)
        // FIX: llamar al método público en lugar de tocar scannedTiles directamente
        HeatmapStore.shared.applyUserValidation(validation)
    }

    func loadAll() -> [UserValidation] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([UserValidation].self, from: data)
        else { return [] }
        return decoded
    }

    func validations(for tileID: UUID) -> [UserValidation] {
        loadAll().filter { $0.tileID == tileID }
    }

    private func persist(_ validations: [UserValidation]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(validations) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

// MARK: - HeatmapStore extension

extension HeatmapStore {
    func applyUserValidation(_ validation: UserValidation) {
        updateScannedTile(id: validation.tileID, applying: validation)
    }
}
