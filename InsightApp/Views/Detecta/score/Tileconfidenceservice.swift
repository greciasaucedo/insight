//
//  Tileconfidenceservice.swift
//  InsightApp
//
//  Created by Guillermo Lira on 18/04/26.

//  Capa de recencia y confianza real.
//  Resuelve el punto 4 del checklist:
//    • datos viejos valen menos
//    • múltiples observaciones aumentan confianza
//    • scans aislados no dominan la ruta
//    • datos simulados se tratan diferente
//
//  Uso desde HeatmapStore o RouteEngine:
//
//    let merged = TileConfidenceService.merge(observations: tilesEnZona)
//    // merged.accessibilityScore, merged.confidenceScore, merged.passabilityScore
//

import Foundation
import CoreLocation

// MARK: - Observation

/// Una observación individual de un punto del mapa.
/// Puede venir de un scan del usuario, de Supabase o de los datos mock.
struct TileObservation {
    let score: Int                  // 0–100
    let confidence: Double          // 0.0–1.0
    let sourceType: TileSourceType
    let createdAt: Date
    let userConfirmation: Bool?     // feedback explícito del usuario
    let passabilityScore: Double?

    /// Peso base de esta observación antes de aplicar decay.
    var baseWeight: Double {
        switch sourceType {
        case .fused:            return 1.0   // mejor fuente posible
        case .camera:           return 0.85
        case .userConfirmation: return 0.95  // humano explícito
        case .motion:           return 0.70
        case .remote:           return 0.60
        case .mock:             return 0.10  // nunca domina
        }
    }

    /// Peso efectivo = baseWeight × recencyDecay.
    var effectiveWeight: Double {
        (baseWeight * recencyDecay).clamped(to: 0...1)
    }

    /// Decaimiento por tiempo. 1.0 = dato de hoy, tiende a 0 en 30 días.
    var recencyDecay: Double {
        let age = Date().timeIntervalSince(createdAt)
        let halfLife: Double = 7 * 24 * 3600   // 7 días = mitad del peso
        // Decaimiento exponencial: w = e^(-age / halfLife)
        return exp(-age / halfLife).clamped(to: 0.05...1.0)
        // Mínimo 0.05: datos viejos aún cuentan un poco para evitar ruido
    }
}

// MARK: - Merged result

struct MergedTileResult {
    let accessibilityScore: Int
    let confidenceScore: Double
    let passabilityScore: Double
    let observationCount: Int
    let dominantSourceType: TileSourceType
    let reasons: [String]
}

// MARK: - Service

enum TileConfidenceService {

    // MARK: - computeConfidence

    /// Calcula la confianza fusionada de un conjunto de observaciones
    /// para el mismo punto del mapa.
    ///
    /// Reglas:
    /// • Más observaciones → mayor confianza (logarítmico, no lineal)
    /// • Observaciones recientes pesan más
    /// • Datos simulados apenas contribuyen
    /// • Consenso entre fuentes distintas sube la confianza extra
    static func computeConfidence(tileObservations: [TileObservation]) -> Double {
        let real = tileObservations.filter { $0.sourceType != .mock }
        guard !real.isEmpty else { return 0.10 }   // solo simulados: confianza mínima

        // 1. Confianza base = promedio ponderado de confidence × effectiveWeight
        let totalWeight = real.map(\.effectiveWeight).reduce(0, +)
        guard totalWeight > 0 else { return 0.10 }

        let weightedConf = real.map { $0.confidence * $0.effectiveWeight }.reduce(0, +)
        var base = weightedConf / totalWeight

        // 2. Bonus logarítmico por número de observaciones reales
        //    1 obs → +0, 4 obs → +0.15, 10 obs → +0.23
        let countBonus = min(0.25, log(Double(real.count) + 1) / log(12))
        base += countBonus

        // 3. Bonus de consenso: si hay ≥ 2 fuentes distintas de tipo real
        let distinctSources = Set(real.map(\.sourceType)).subtracting([.mock, .remote])
        if distinctSources.count >= 2 { base += 0.10 }

        // 4. Bonus si hay confirmación explícita de usuario
        if real.contains(where: { $0.userConfirmation != nil }) { base += 0.10 }

        return base.clamped(to: 0...1)
    }

    // MARK: - merge

    /// Fusiona múltiples observaciones del mismo punto en un único resultado.
    /// Usa media ponderada por `effectiveWeight`.
    static func merge(observations: [TileObservation]) -> MergedTileResult {
        guard !observations.isEmpty else {
            return MergedTileResult(
                accessibilityScore: 50,
                confidenceScore:    0.10,
                passabilityScore:   0.50,
                observationCount:   0,
                dominantSourceType: .remote,
                reasons:            []
            )
        }

        let real = observations.filter { $0.sourceType != .mock }
        let working = real.isEmpty ? observations : real

        let totalWeight = working.map(\.effectiveWeight).reduce(0, +)

        // ── Score ponderado ───────────────────────────────────────────────
        let weightedScore = working
            .map { Double($0.score) * $0.effectiveWeight }
            .reduce(0, +)
        let finalScore = totalWeight > 0
            ? (weightedScore / totalWeight).clamped(to: 0...100)
            : 50

        // ── Passability ponderada ─────────────────────────────────────────
        let withPass = working.compactMap { obs -> (Double, Double)? in
            guard let p = obs.passabilityScore else { return nil }
            return (p, obs.effectiveWeight)
        }
        let passTotal = withPass.map(\.1).reduce(0, +)
        let finalPass: Double
        if passTotal > 0 {
            finalPass = withPass.map { $0.0 * $0.1 }.reduce(0, +) / passTotal
        } else {
            finalPass = finalScore / 100.0
        }

        // ── Confianza fusionada ───────────────────────────────────────────
        let confidence = computeConfidence(tileObservations: working)

        // ── Fuente dominante = la de mayor effectiveWeight ───────────────
        let dominant = working.max(by: { $0.effectiveWeight < $1.effectiveWeight })?.sourceType ?? .remote

        // ── Reasons ──────────────────────────────────────────────────────
        var reasons: [String] = []
        let realCount = real.count
        if realCount == 0 {
            reasons.append("Solo datos simulados disponibles")
        } else if realCount == 1 {
            reasons.append("Observación única — confianza limitada")
        } else {
            reasons.append("\(realCount) observaciones reales fusionadas")
        }

        // Advertir si el dato más reciente es viejo
        if let newest = working.max(by: { $0.createdAt < $1.createdAt }) {
            let age = Date().timeIntervalSince(newest.createdAt)
            if age > 14 * 24 * 3600 {
                reasons.append("Dato más reciente tiene más de 14 días")
            }
        }

        // Avisar si hay consenso entre fuentes
        let distinctSources = Set(working.map(\.sourceType)).subtracting([.mock])
        if distinctSources.count >= 2 {
            reasons.append("Consenso entre múltiples fuentes")
        }

        return MergedTileResult(
            accessibilityScore: Int(finalScore.rounded()),
            confidenceScore:    confidence,
            passabilityScore:   finalPass.clamped(to: 0...1),
            observationCount:   observations.count,
            dominantSourceType: dominant,
            reasons:            reasons
        )
    }

    // MARK: - shouldTrustNewScan

    /// Decide si un nuevo scan debe reemplazar, fusionarse o descartarse
    /// respecto al tile existente.
    static func shouldTrustNewScan(
        newConfidence: Double,
        existingTile: AccessibilityTile?
    ) -> ScanTrustDecision {
        guard let existing = existingTile else {
            return .accept   // no hay dato previo → aceptar siempre
        }

        // Dato simulado: nunca bloquea uno real
        if existing.sourceType == .mock { return .accept }

        // Si el existente es muy reciente y muy confiable, no sobreescribir con uno peor
        if existing.recencyWeight > 0.85, existing.confidenceScore > 0.75,
           newConfidence < existing.confidenceScore * 0.6 {
            return .ignore(reason: "Dato reciente y confiable ya existe")
        }

        // Si hay más de 30 días sin actualizar → aceptar cualquier lectura nueva
        if existing.recencyWeight < 0.10 { return .accept }

        // Caso general → fusionar
        return .merge
    }
}

// MARK: - Trust decision

enum ScanTrustDecision {
    case accept
    case merge
    case ignore(reason: String)
}

// MARK: - HeatmapStore extension
//
// Agrega en HeatmapStore.swift el método tileNear(coordinate:) que
// LayerScoringEngine necesita para buscar datos previos.
//
extension HeatmapStore {

    /// Devuelve el tile más cercano a la coordenada dada dentro de ~10 metros.
    func tileNear(_ coordinate: CLLocationCoordinate2D, radiusDeg: Double = 0.00009) -> AccessibilityTile? {
        allTiles.first { tile in
            abs(tile.coordinate.latitude  - coordinate.latitude)  < radiusDeg &&
            abs(tile.coordinate.longitude - coordinate.longitude) < radiusDeg
        }
    }

    /// Devuelve todas las observaciones (como TileObservation) en un radio dado.
    func observations(near coordinate: CLLocationCoordinate2D, radiusDeg: Double = 0.00009) -> [TileObservation] {
        allTiles
            .filter { tile in
                abs(tile.coordinate.latitude  - coordinate.latitude)  < radiusDeg &&
                abs(tile.coordinate.longitude - coordinate.longitude) < radiusDeg
            }
            .map { tile in
                TileObservation(
                    score:            tile.accessibilityScore,
                    confidence:       tile.confidenceScore,
                    sourceType:       tile.sourceType,
                    createdAt:        tile.createdAt,
                    userConfirmation: nil,
                    passabilityScore: tile.passabilityScore
                )
            }
    }
}
