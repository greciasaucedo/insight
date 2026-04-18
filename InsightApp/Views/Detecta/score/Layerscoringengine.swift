//
//  Layerscoringengine.swift
//  InsightApp
//
//  Created by Guillermo Lira on 18/04/26.
//  LayerScoringEngine.swift
//  InsightApp
//
//  Motor de scoring fusionado. Combina señales visuales (CoreML),
//  de movimiento (Core Motion), recencia, consistencia y confirmación
//  del usuario en un resultado unificado.
//
//  Uso desde ScanViewModel (después de medir terreno):
//
//    let input = ScoringInput(
//        detectedLabel:    result.label,
//        visualConfidence: Double(result.confidence),
//        vibrationScore:   terrain?.accessibilityVibrationScore,
//        slopeScore:       terrain?.accessibilitySlopeScore,
//        motionConfidence: terrain?.motionConfidence,
//        profile:          ProfileService.shared.currentProfile,
//        existingTile:     HeatmapStore.shared.tileNear(coordinate)
//    )
//    let output = LayerScoringEngine.score(input)
//    // output.accessibilityScore, output.confidenceScore, output.passabilityScore
//

import Foundation

// MARK: - Input

/// Todas las señales disponibles para un punto del mapa.
/// Todos los campos opcionales tienen fallback razonado interno.
struct ScoringInput {

    // ── Señal visual (CoreML) ────────────────────────────────────────────
    /// Etiqueta detectada por el modelo: "flat", "ramp", "stairs", "obstacle", nil
    let detectedLabel: String?
    /// Confianza del modelo de visión (0.0–1.0)
    let visualConfidence: Double

    // ── Señal de movimiento (Core Motion) ───────────────────────────────
    /// 1.0 = liso, 0.0 = muy rugoso. nil si no hay datos de movimiento.
    let vibrationScore: Double?
    /// 1.0 = plano, 0.0 = muy inclinado. nil si no hay datos de movimiento.
    let slopeScore: Double?
    /// Confianza de la medición de movimiento (0.0–1.0). nil si no hay.
    let motionConfidence: Double?

    // ── Contexto del usuario ─────────────────────────────────────────────
    let profile: AccessibilityProfile

    // ── Tile existente en esa zona (para consistencia y recencia) ────────
    /// Si ya hay un tile guardado cerca, se usa para ponderar el nuevo resultado.
    let existingTile: AccessibilityTile?

    // ── Confirmación explícita del usuario ───────────────────────────────
    /// true = pasó bien, false = reportó problema, nil = sin feedback
    let userConfirmation: Bool?

    init(
        detectedLabel: String?,
        visualConfidence: Double,
        vibrationScore: Double? = nil,
        slopeScore: Double? = nil,
        motionConfidence: Double? = nil,
        profile: AccessibilityProfile = .standard,
        existingTile: AccessibilityTile? = nil,
        userConfirmation: Bool? = nil
    ) {
        self.detectedLabel    = detectedLabel
        self.visualConfidence = visualConfidence
        self.vibrationScore   = vibrationScore
        self.slopeScore       = slopeScore
        self.motionConfidence = motionConfidence
        self.profile          = profile
        self.existingTile     = existingTile
        self.userConfirmation = userConfirmation
    }
}

// MARK: - Output

struct ScoringOutput {
    /// Score global de accesibilidad (0–100). Listo para AccessibilityTile.accessibilityScore.
    let accessibilityScore: Int

    /// Confianza fusionada del resultado (0.0–1.0).
    let confidenceScore: Double

    /// Estimación de transitabilidad (0.0–1.0). Tiene en cuenta perfil + señales.
    let passabilityScore: Double

    /// Etiqueta explicativa del factor dominante que determinó el score.
    let dominantReason: String

    /// Todas las señales que contribuyeron, listas para AccessibilityTile.reasons.
    let reasons: [String]

    /// Fuente efectiva del dato fusionado.
    let effectiveSourceType: TileSourceType
}

// MARK: - Engine

enum LayerScoringEngine {

    // MARK: Public entry point

    static func score(_ input: ScoringInput) -> ScoringOutput {
        let visual   = visualBaseScore(label: input.detectedLabel, confidence: input.visualConfidence)
        let motion   = motionAdjustment(vibration: input.vibrationScore,
                                        slope: input.slopeScore,
                                        confidence: input.motionConfidence)
        let recency  = recencyAdjustment(existingTile: input.existingTile)
        let userAdj  = userConfirmationAdjustment(confirmation: input.userConfirmation)
        let profile  = profileMultiplier(label: input.detectedLabel, profile: input.profile)

        // ── Fusión ───────────────────────────────────────────────────────
        // Base visual pesa 50%, movimiento 30%, recencia 10%, usuario 10%.
        // El multiplicador de perfil se aplica al final (puede bajar hasta 0.3x).
        var rawScore = (visual.score * 0.50)
                     + (motion.score * 0.30)
                     + (recency.score * 0.10)
                     + (userAdj.score * 0.10)
        rawScore *= profile.multiplier
        rawScore  = rawScore.clamped(to: 0...100)

        // ── Confianza fusionada ──────────────────────────────────────────
        let fusedConfidence = fuseConfidence(
            visualConfidence:  input.visualConfidence,
            motionConfidence:  input.motionConfidence,
            hasExistingData:   input.existingTile != nil,
            userConfirmation:  input.userConfirmation
        )

        // ── Passability ──────────────────────────────────────────────────
        let pass = computePassability(
            accessibilityScore: rawScore,
            vibration:          input.vibrationScore,
            slope:              input.slopeScore,
            label:              input.detectedLabel,
            profile:            input.profile
        )

        // ── Reasons ──────────────────────────────────────────────────────
        var reasons: [String] = []
        if let r = visual.reason   { reasons.append(r) }
        if let r = motion.reason   { reasons.append(r) }
        if let r = recency.reason  { reasons.append(r) }
        if let r = userAdj.reason  { reasons.append(r) }
        if let r = profile.reason  { reasons.append(r) }

        let dominant = reasons.first ?? "Zona analizada"

        // ── Source type ──────────────────────────────────────────────────
        let src: TileSourceType
        if input.motionConfidence ?? 0 > 0.5 {
            src = .fused
        } else if input.detectedLabel != nil {
            src = .camera
        } else {
            src = .remote
        }

        return ScoringOutput(
            accessibilityScore: Int(rawScore.rounded()),
            confidenceScore:    fusedConfidence,
            passabilityScore:   pass,
            dominantReason:     dominant,
            reasons:            reasons,
            effectiveSourceType: src
        )
    }

    // MARK: - Signal: Visual (CoreML)

    private struct SignalResult {
        let score: Double        // 0–100
        let reason: String?
    }

    private static func visualBaseScore(label: String?, confidence: Double) -> SignalResult {
        // Score base según etiqueta detectada
        let base: Double
        let reason: String?

        switch label?.lowercased() {
        case "flat":
            base   = 90
            reason = "Superficie plana detectada por cámara"
        case "ramp":
            base   = 72
            reason = "Rampa detectada por cámara"
        case "stairs":
            base   = 30
            reason = "Escaleras detectadas por cámara"
        case "obstacle":
            base   = 18
            reason = "Obstáculo detectado por cámara"
        case nil:
            base   = 50
            reason = nil
        default:
            base   = 50
            reason = "Zona analizada por cámara"
        }

        // Baja el score si la confianza visual es baja (< 0.5)
        let adjusted = confidence >= 0.5 ? base : base * (0.5 + confidence)
        return SignalResult(score: adjusted, reason: reason)
    }

    // MARK: - Signal: Motion

    private static func motionAdjustment(
        vibration: Double?,
        slope: Double?,
        confidence: Double?
    ) -> SignalResult {

        guard let conf = confidence, conf > 0.3 else {
            // Sin datos de movimiento confiables: no penalizar ni bonificar
            return SignalResult(score: 50, reason: nil)
        }

        let vib   = vibration ?? 0.5   // neutro si no hay dato
        let sl    = slope     ?? 0.5

        // score 0–100 basado en combinación vibración (40%) + pendiente (60%)
        let motionScore = ((vib * 0.4) + (sl * 0.6)) * 100

        var reason: String? = nil
        if vib < 0.35 {
            reason = "Vibración elevada detectada"
        } else if sl < 0.40 {
            reason = "Inclinación significativa detectada"
        } else if vib > 0.75 && sl > 0.75 {
            reason = "Superficie suave y plana confirmada por sensores"
        }

        return SignalResult(score: motionScore, reason: reason)
    }

    // MARK: - Signal: Recency

    private static func recencyAdjustment(existingTile: AccessibilityTile?) -> SignalResult {
        guard let tile = existingTile else {
            return SignalResult(score: 50, reason: nil)   // sin dato previo: neutro
        }

        let rw = tile.recencyWeight   // 0.0–1.0, calculado en AccessibilityTile

        if rw > 0.8 {
            // Dato muy reciente: refuerza la lectura anterior
            return SignalResult(
                score: Double(tile.accessibilityScore),
                reason: "Dato reciente disponible (< 6 días)"
            )
        } else if rw < 0.2 {
            // Dato muy antiguo: reducir su influencia, no bloquear nueva lectura
            return SignalResult(
                score: 50,
                reason: "Dato previo antiguo (> 24 días)"
            )
        } else {
            return SignalResult(score: Double(tile.accessibilityScore) * rw + 50 * (1 - rw), reason: nil)
        }
    }

    // MARK: - Signal: User Confirmation

    private static func userConfirmationAdjustment(confirmation: Bool?) -> SignalResult {
        switch confirmation {
        case true:
            return SignalResult(score: 85, reason: "Confirmado por usuario")
        case false:
            return SignalResult(score: 20, reason: "Problema reportado por usuario")
        case nil:
            return SignalResult(score: 50, reason: nil)
        }
    }

    // MARK: - Signal: Profile Multiplier

    private struct ProfileResult {
        let multiplier: Double
        let reason: String?
    }

    private static func profileMultiplier(
        label: String?,
        profile: AccessibilityProfile
    ) -> ProfileResult {
        let lower = label?.lowercased()

        switch profile {
        case .wheelchair:
            if lower == "stairs"   { return ProfileResult(multiplier: 0.20, reason: "Escaleras no accesibles para silla de ruedas") }
            if lower == "obstacle" { return ProfileResult(multiplier: 0.30, reason: "Obstáculo crítico para silla de ruedas") }
            if lower == "ramp"     { return ProfileResult(multiplier: 0.85, reason: nil) }
            return ProfileResult(multiplier: 1.0, reason: nil)

        case .elderly:
            if lower == "stairs"   { return ProfileResult(multiplier: 0.45, reason: "Escaleras de difícil acceso") }
            if lower == "obstacle" { return ProfileResult(multiplier: 0.55, reason: "Obstáculo en ruta") }
            return ProfileResult(multiplier: 1.0, reason: nil)

        case .reducedMobility:
            if lower == "stairs"   { return ProfileResult(multiplier: 0.55, reason: "Tramo de difícil tránsito") }
            if lower == "obstacle" { return ProfileResult(multiplier: 0.65, reason: "Obstáculo en ruta") }
            return ProfileResult(multiplier: 1.0, reason: nil)

        case .standard:
            return ProfileResult(multiplier: 1.0, reason: nil)
        }
    }

    // MARK: - Confidence fusion

    /// Combina las fuentes de confianza disponibles en un score único.
    static func fuseConfidence(
        visualConfidence: Double,
        motionConfidence: Double?,
        hasExistingData: Bool,
        userConfirmation: Bool?
    ) -> Double {
        var confidence = visualConfidence * 0.5   // base: confianza visual

        if let mc = motionConfidence, mc > 0 {
            confidence += mc * 0.3               // motion aporta hasta 30%
        } else {
            confidence += 0.15                   // bonus pequeño por tener al menos datos visuales
        }

        if hasExistingData  { confidence += 0.10 }   // consistencia con dato previo
        if userConfirmation != nil { confidence += 0.10 }   // feedback humano

        return confidence.clamped(to: 0...1)
    }

    // MARK: - Passability

    private static func computePassability(
        accessibilityScore: Double,
        vibration: Double?,
        slope: Double?,
        label: String?,
        profile: AccessibilityProfile
    ) -> Double {
        // Base desde el score global
        var pass = accessibilityScore / 100.0

        // Penalizar si la pendiente es muy alta para perfiles sensibles
        if let sl = slope, sl < 0.30 {
            switch profile {
            case .wheelchair:    pass *= 0.40
            case .elderly:       pass *= 0.60
            case .reducedMobility: pass *= 0.70
            case .standard:      break
            }
        }

        // Penalizar si vibración muy alta (superficie muy irregular)
        if let vib = vibration, vib < 0.20 {
            pass *= 0.75
        }

        // Stairs con wheelchair → prácticamente intransitable
        if label?.lowercased() == "stairs", profile == .wheelchair {
            pass = min(pass, 0.05)
        }

        return pass.clamped(to: 0...1)
    }
}
