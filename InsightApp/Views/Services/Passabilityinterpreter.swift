//
//  Passabilityinterpreter.swift
//  InsightApp
//
//  Created by Guillermo Lira on 18/04/26.
//

//
//  Punto 5: capa de interpretación real.
//  Infraestructura detectada ≠ accesibilidad real.
//  Accesibilidad real = infraestructura + comportamiento + sensores.
//
//  La distinción clave:
//    • CoreML detecta QUÉ hay (rampa, escalera, superficie plana)
//    • PassabilityInterpreter determina si eso ES USABLE para este usuario
//
//  Uso:
//    let verdict = PassabilityInterpreter.evaluate(
//        label:       result.label,
//        vibration:   terrain?.accessibilityVibrationScore,
//        slope:       terrain?.accessibilitySlopeScore,
//        confidence:  terrain?.motionConfidence,
//        profile:     ProfileService.shared.currentProfile,
//        humanFeedback: nil
//    )
//    // verdict.passabilityScore, verdict.usabilityLevel, verdict.explanation
//

import Foundation

// MARK: - Usability Level

enum UsabilityLevel {
    case fullyUsable       // pasable sin problemas para este perfil
    case usableWithCaution // pasable pero con dificultad o riesgo
    case borderline        // depende — se necesita confirmación humana
    case notUsable         // no recomendado para este perfil

    var label: String {
        switch self {
        case .fullyUsable:       return "Transitable"
        case .usableWithCaution: return "Con precaución"
        case .borderline:        return "Dudoso"
        case .notUsable:         return "No transitable"
        }
    }

    var icon: String {
        switch self {
        case .fullyUsable:       return "checkmark.circle.fill"
        case .usableWithCaution: return "exclamationmark.triangle.fill"
        case .borderline:        return "questionmark.circle.fill"
        case .notUsable:         return "xmark.circle.fill"
    }
    }
}

// MARK: - Verdict

struct PassabilityVerdict {
    /// Score 0.0–1.0. 1.0 = completamente transitable para este perfil.
    let passabilityScore: Double

    /// Nivel cualitativo de usabilidad.
    let usabilityLevel: UsabilityLevel

    /// Explicación generada para el usuario (para mostrar en BottomSheet / RouteView).
    let explanation: String

    /// Si es true, se recomienda pedir confirmación humana antes de confiar en el dato.
    let needsHumanConfirmation: Bool

    /// Factores que contribuyeron a la decisión, para reasons del tile.
    let contributingFactors: [String]
}

// MARK: - Interpreter

enum PassabilityInterpreter {

    // MARK: - Main evaluate

    /// Evalúa si una infraestructura detectada es realmente usable.
    ///
    /// - Parameters:
    ///   - label: Etiqueta de CoreML ("flat", "ramp", "stairs", "obstacle")
    ///   - vibrationScore: 1.0 = liso, 0.0 = rugoso. nil si no hay datos de movimiento.
    ///   - slopeScore: 1.0 = plano, 0.0 = muy inclinado. nil si no hay datos.
    ///   - motionConfidence: Confianza de los sensores (0.0–1.0). nil si no hay.
    ///   - profile: Perfil de accesibilidad del usuario.
    ///   - humanFeedback: Confirmación humana previa si existe. true = pasó bien.
    static func evaluate(
        label: String?,
        vibrationScore: Double?,
        slopeScore: Double?,
        motionConfidence: Double?,
        profile: AccessibilityProfile,
        humanFeedback: Bool? = nil
    ) -> PassabilityVerdict {

        let lowerLabel = label?.lowercased()
        let hasMotion  = (motionConfidence ?? 0) > 0.3
        var factors: [String] = []

        // ── Si hay feedback humano explícito, tiene prioridad total ──────
        if let feedback = humanFeedback {
            return humanFeedbackVerdict(positive: feedback, label: lowerLabel, profile: profile)
        }

        // ── Evaluación por tipo de infraestructura ────────────────────────
        switch lowerLabel {

        case "flat":
            return evaluateFlat(
                vibration: vibrationScore,
                slope: slopeScore,
                hasMotion: hasMotion,
                profile: profile,
                factors: &factors
            )

        case "ramp":
            return evaluateRamp(
                vibration: vibrationScore,
                slope: slopeScore,
                hasMotion: hasMotion,
                profile: profile,
                factors: &factors
            )

        case "stairs":
            return evaluateStairs(profile: profile, factors: &factors)

        case "obstacle":
            return evaluateObstacle(profile: profile, factors: &factors)

        default:
            // Etiqueta desconocida: usar solo sensores si hay, sino borderline
            if hasMotion, let vib = vibrationScore, let sl = slopeScore {
                let combined = vib * 0.4 + sl * 0.6
                return PassabilityVerdict(
                    passabilityScore: combined,
                    usabilityLevel: combined > 0.6 ? .usableWithCaution : .borderline,
                    explanation: "Zona analizada. Se recomienda verificar en persona.",
                    needsHumanConfirmation: true,
                    contributingFactors: ["Zona sin clasificación visual clara"]
                )
            }
            return PassabilityVerdict(
                passabilityScore: 0.5,
                usabilityLevel: .borderline,
                explanation: "Sin datos suficientes para determinar transitabilidad.",
                needsHumanConfirmation: true,
                contributingFactors: ["Datos insuficientes"]
            )
        }
    }

    // MARK: - Flat surface

    private static func evaluateFlat(
        vibration: Double?,
        slope: Double?,
        hasMotion: Bool,
        profile: AccessibilityProfile,
        factors: inout [String]
    ) -> PassabilityVerdict {

        // Sin sensores: confiar en la etiqueta visual pero pedir confirmación
        guard hasMotion, let vib = vibration, let sl = slope else {
            factors.append("Superficie plana detectada por cámara")
            return PassabilityVerdict(
                passabilityScore: 0.75,
                usabilityLevel: .usableWithCaution,
                explanation: "Superficie plana detectada. Sin datos de sensores para confirmar.",
                needsHumanConfirmation: true,
                contributingFactors: factors
            )
        }

        factors.append("Superficie plana confirmada por cámara")

        // Vibración alta en superficie "plana" → puede ser adoquín, tierra, etc.
        if vib < 0.35 {
            factors.append("Vibración elevada (superficie irregular a pesar de ser plana)")
        }
        // Pendiente inesperada
        if sl < 0.40 {
            factors.append("Inclinación significativa detectada")
        }

        let combined = (vib * 0.35 + sl * 0.35 + 0.75 * 0.30).clamped(to: 0...1)

        let level: UsabilityLevel
        let explanation: String

        switch combined {
        case 0.75...:
            level = .fullyUsable
            explanation = "Superficie plana y suave. Condiciones óptimas de transitabilidad."
        case 0.50..<0.75:
            level = .usableWithCaution
            explanation = "Superficie plana pero con irregularidades o ligera inclinación."
        default:
            level = .borderline
            explanation = "Superficie plana visualmente pero los sensores detectan problemas."
        }

        // Perfil específico: wheelchair es más sensible a vibración
        let profileAdjusted = applyProfilePenalty(score: combined, label: "flat", profile: profile)
        return PassabilityVerdict(
            passabilityScore: profileAdjusted,
            usabilityLevel: level,
            explanation: explanation,
            needsHumanConfirmation: combined < 0.55,
            contributingFactors: factors
        )
    }

    // MARK: - Ramp
    // Una rampa NO es automáticamente accesible. Depende del ángulo y la superficie.

    private static func evaluateRamp(
        vibration: Double?,
        slope: Double?,
        hasMotion: Bool,
        profile: AccessibilityProfile,
        factors: inout [String]
    ) -> PassabilityVerdict {

        factors.append("Rampa detectada por cámara")

        // Sin sensores: rampa detectada es DUDOSA, no accesible automáticamente
        guard hasMotion, let vib = vibration, let sl = slope else {
            let needsConfirm = (profile == .wheelchair || profile == .elderly)
            return PassabilityVerdict(
                passabilityScore: 0.55,
                usabilityLevel: .borderline,
                explanation: "Rampa detectada. Sin datos de inclinación para confirmar usabilidad.",
                needsHumanConfirmation: needsConfirm,
                contributingFactors: factors
            )
        }

        // Inclinación medida: si slope < 0.45 la rampa es demasiado inclinada
        if sl < 0.45 {
            factors.append("Inclinación excesiva para rampa estándar")
        }
        if vib < 0.40 {
            factors.append("Superficie rugosa en la rampa")
        }

        // Rampa usable: surface suave (vib > 0.5) + inclinación moderada (sl > 0.5)
        let rampScore = (vib * 0.40 + sl * 0.60).clamped(to: 0...1)
        let profileScore = applyProfilePenalty(score: rampScore, label: "ramp", profile: profile)

        let level: UsabilityLevel
        let explanation: String

        switch profileScore {
        case 0.70...:
            level = .fullyUsable
            explanation = "Rampa con inclinación y superficie adecuadas para este perfil."
        case 0.45..<0.70:
            level = .usableWithCaution
            explanation = "Rampa transitable pero con precaución. \(sl < 0.50 ? "Inclinación elevada." : "Superficie irregular.")"
        default:
            level = .notUsable
            explanation = "Rampa con condiciones difíciles para este perfil. Se recomienda ruta alternativa."
        }

        return PassabilityVerdict(
            passabilityScore: profileScore,
            usabilityLevel: level,
            explanation: explanation,
            needsHumanConfirmation: profileScore < 0.60,
            contributingFactors: factors
        )
    }

    // MARK: - Stairs

    private static func evaluateStairs(
        profile: AccessibilityProfile,
        factors: inout [String]
    ) -> PassabilityVerdict {
        factors.append("Escaleras detectadas por cámara")

        switch profile {
        case .wheelchair:
            factors.append("Escaleras: barrera total para silla de ruedas")
            return PassabilityVerdict(
                passabilityScore: 0.02,
                usabilityLevel: .notUsable,
                explanation: "Escaleras detectadas. No transitable en silla de ruedas. Se recomienda ruta alternativa.",
                needsHumanConfirmation: false,
                contributingFactors: factors
            )
        case .elderly:
            factors.append("Escaleras: dificultad alta para adulto mayor")
            return PassabilityVerdict(
                passabilityScore: 0.25,
                usabilityLevel: .notUsable,
                explanation: "Escaleras detectadas. Dificultad alta para adulto mayor.",
                needsHumanConfirmation: true,
                contributingFactors: factors
            )
        case .reducedMobility:
            factors.append("Escaleras: dificultad significativa")
            return PassabilityVerdict(
                passabilityScore: 0.30,
                usabilityLevel: .usableWithCaution,
                explanation: "Escaleras detectadas. Evalúa si hay alternativa más accesible.",
                needsHumanConfirmation: true,
                contributingFactors: factors
            )
        case .standard:
            return PassabilityVerdict(
                passabilityScore: 0.55,
                usabilityLevel: .usableWithCaution,
                explanation: "Escaleras detectadas en el trayecto.",
                needsHumanConfirmation: false,
                contributingFactors: factors
            )
        }
    }

    // MARK: - Obstacle

    private static func evaluateObstacle(
        profile: AccessibilityProfile,
        factors: inout [String]
    ) -> PassabilityVerdict {
        factors.append("Obstáculo detectado por cámara")

        let score: Double
        let level: UsabilityLevel
        let explanation: String

        switch profile {
        case .wheelchair:
            score = 0.10
            level = .notUsable
            explanation = "Obstáculo detectado. Zona de riesgo para silla de ruedas."
            factors.append("Obstáculo: bloqueo crítico para silla de ruedas")
        case .elderly:
            score = 0.25
            level = .notUsable
            explanation = "Obstáculo detectado. Se recomienda evitar esta zona."
        case .reducedMobility:
            score = 0.30
            level = .usableWithCaution
            explanation = "Obstáculo detectado. Transitar con cuidado."
        case .standard:
            score = 0.50
            level = .usableWithCaution
            explanation = "Obstáculo detectado en la zona."
        }

        return PassabilityVerdict(
            passabilityScore: score,
            usabilityLevel: level,
            explanation: explanation,
            needsHumanConfirmation: true,
            contributingFactors: factors
        )
    }

    // MARK: - Human feedback override

    private static func humanFeedbackVerdict(
        positive: Bool,
        label: String?,
        profile: AccessibilityProfile
    ) -> PassabilityVerdict {
        if positive {
            return PassabilityVerdict(
                passabilityScore: 0.88,
                usabilityLevel: .fullyUsable,
                explanation: "Confirmado por usuario: pasó sin problemas.",
                needsHumanConfirmation: false,
                contributingFactors: ["Confirmación humana positiva"]
            )
        } else {
            let score: Double = profile == .wheelchair ? 0.05 : 0.20
            return PassabilityVerdict(
                passabilityScore: score,
                usabilityLevel: .notUsable,
                explanation: "Reportado por usuario: dificultad al pasar.",
                needsHumanConfirmation: false,
                contributingFactors: ["Reporte negativo del usuario"]
            )
        }
    }

    // MARK: - Profile penalty helper

    private static func applyProfilePenalty(
        score: Double,
        label: String,
        profile: AccessibilityProfile
    ) -> Double {
        switch profile {
        case .wheelchair:
            if label == "ramp"     { return score * 0.90 }  // aún sensible a calidad de rampa
            if label == "flat"     { return score * 0.85 }  // superficie importa más
            return score
        case .elderly:
            // Mayor sensibilidad a vibración/slope
            return score * 0.88
        case .reducedMobility:
            return score * 0.92
        case .standard:
            return score
        }
    }
}
