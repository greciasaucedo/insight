//
//  Accessibilityprofile+extended.swift
//  InsightApp
//
//  Created by Guillermo Lira on 18/04/26.
//

//
//  AccessibilityProfile+Extended.swift
//  InsightApp
//
//  Punto 8: el perfil ahora gobierna score final, umbrales de riesgo,
//  tipo de alertas y sensibilidad de señales.
//
//  Este archivo EXTIENDE AccessibilityProfile sin modificar el original.
//  Agrega computed properties que ya se pueden usar directamente en
//  LayerScoringEngine, PassabilityInterpreter y RouteEngine.
//

import SwiftUI

// MARK: - Profile thresholds

/// Umbrales específicos por perfil. Definen cuándo una señal es "problemática".
struct ProfileThresholds {
    /// vibrationScore por debajo del cual se considera superficie problemática
    let vibrationWarning: Double
    let vibrationCritical: Double
    /// slopeScore por debajo del cual se considera inclinación problemática
    let slopeWarning: Double
    let slopeCritical: Double
    /// passabilityScore mínimo para que una ruta sea recomendada
    let minPassability: Double
    /// accessibilityScore por debajo del cual se muestra alerta
    let alertThreshold: Int
}

// MARK: - Signal fusion weights

/// Pesos que determinan cuánto pesa cada señal en el score fusionado.
struct SignalWeights {
    let visual: Double      // CoreML
    let vibration: Double   // acelerómetro
    let slope: Double       // giroscopio
    let recency: Double     // cuánto importa la antigüedad
    let human: Double       // confirmación del usuario
}

// MARK: - Alert config

struct ProfileAlertConfig {
    let showVibrationWarning: Bool
    let showSlopeWarning: Bool
    let showStairsWarning: Bool
    let alertStyle: AlertStyle

    enum AlertStyle {
        case subtle    // badge pequeño, sin sonido
        case prominent // banner + haptico suave
        case critical  // banner + haptico fuerte + voz
    }
}

// MARK: - AccessibilityProfile extension

extension AccessibilityProfile {

    // MARK: Thresholds

    var thresholds: ProfileThresholds {
        switch self {
        case .wheelchair:
            return ProfileThresholds(
                vibrationWarning:  0.55,   // más sensible a superficie rugosa
                vibrationCritical: 0.30,
                slopeWarning:      0.55,   // inclinación mínima tolerable mayor
                slopeCritical:     0.30,
                minPassability:    0.60,
                alertThreshold:    65
            )
        case .elderly:
            return ProfileThresholds(
                vibrationWarning:  0.50,
                vibrationCritical: 0.25,
                slopeWarning:      0.45,   // pendiente pesa mucho
                slopeCritical:     0.25,
                minPassability:    0.50,
                alertThreshold:    55
            )
        case .reducedMobility:
            return ProfileThresholds(
                vibrationWarning:  0.45,   // superficie irregular pesa mucho
                vibrationCritical: 0.20,
                slopeWarning:      0.50,
                slopeCritical:     0.30,
                minPassability:    0.45,
                alertThreshold:    50
            )
        case .standard:
            return ProfileThresholds(
                vibrationWarning:  0.25,
                vibrationCritical: 0.10,
                slopeWarning:      0.25,
                slopeCritical:     0.10,
                minPassability:    0.30,
                alertThreshold:    35
            )
        }
    }

    // MARK: Signal weights

    var signalWeights: SignalWeights {
        switch self {
        case .wheelchair:
            // Slope dominante (rampas/escaleras críticas), vibración alta
            return SignalWeights(visual: 0.40, vibration: 0.20, slope: 0.25, recency: 0.08, human: 0.07)
        case .elderly:
            // Slope y vibración equilibrados, recencia importa más (infraestructura puede cambiar)
            return SignalWeights(visual: 0.35, vibration: 0.22, slope: 0.25, recency: 0.10, human: 0.08)
        case .reducedMobility:
            // Vibración es lo más importante (superficie irregular es el mayor obstáculo)
            return SignalWeights(visual: 0.38, vibration: 0.28, slope: 0.18, recency: 0.08, human: 0.08)
        case .standard:
            // Confianza visual alta, movimiento como verificación secundaria
            return SignalWeights(visual: 0.50, vibration: 0.15, slope: 0.15, recency: 0.10, human: 0.10)
        }
    }

    // MARK: Alert config

    var alertConfig: ProfileAlertConfig {
        switch self {
        case .wheelchair:
            return ProfileAlertConfig(
                showVibrationWarning: true,
                showSlopeWarning:     true,
                showStairsWarning:    true,
                alertStyle:           .critical
            )
        case .elderly:
            return ProfileAlertConfig(
                showVibrationWarning: true,
                showSlopeWarning:     true,
                showStairsWarning:    true,
                alertStyle:           .prominent
            )
        case .reducedMobility:
            return ProfileAlertConfig(
                showVibrationWarning: true,
                showSlopeWarning:     true,
                showStairsWarning:    false,
                alertStyle:           .prominent
            )
        case .standard:
            return ProfileAlertConfig(
                showVibrationWarning: false,
                showSlopeWarning:     false,
                showStairsWarning:    false,
                alertStyle:           .subtle
            )
        }
    }

    // MARK: Risk label for a tile

    /// Genera una alerta de riesgo específica para este perfil y tile.
    /// Retorna nil si no hay riesgo relevante.
    func riskAlert(for tile: AccessibilityTile) -> String? {
        let t = thresholds
        let label = tile.detectedLabel?.lowercased()

        if label == "stairs" && alertConfig.showStairsWarning {
            switch self {
            case .wheelchair: return "⚠️ Escaleras: barrera total. Busca ruta alternativa."
            case .elderly:    return "⚠️ Escaleras detectadas. Considera ruta alternativa."
            default:          return "Escaleras en el trayecto."
            }
        }

        if let vib = tile.vibrationScore, vib < t.vibrationCritical {
            return "⚠️ Superficie muy irregular para \(displayName.lowercased())."
        }

        if let sl = tile.slopeScore, sl < t.slopeCritical {
            return "⚠️ Inclinación excesiva para \(displayName.lowercased())."
        }

        if let vib = tile.vibrationScore, vib < t.vibrationWarning, alertConfig.showVibrationWarning {
            return "Superficie con irregularidades. Procede con cuidado."
        }

        if let sl = tile.slopeScore, sl < t.slopeWarning, alertConfig.showSlopeWarning {
            return "Pendiente notable. Evalúa si es transitable."
        }

        return nil
    }

    // MARK: Score interpretation

    /// Interpreta un accessibilityScore según el umbral de este perfil.
    func scoreInterpretation(_ score: Int) -> ScoreInterpretation {
        let t = thresholds
        if score >= 80 { return .excellent }
        if score >= t.alertThreshold { return .acceptable }
        if score >= t.alertThreshold - 15 { return .risky }
        return .avoid
    }

    enum ScoreInterpretation {
        case excellent, acceptable, risky, avoid

        var label: String {
            switch self {
            case .excellent:  return "Excelente"
            case .acceptable: return "Aceptable"
            case .risky:      return "Con riesgo"
            case .avoid:      return "Evitar"
            }
        }

        var color: Color {
            switch self {
            case .excellent:  return Color(red: 136/255, green: 205/255, blue: 212/255)
            case .acceptable: return Color(red: 100/255, green: 200/255, blue: 120/255)
            case .risky:      return Color(red: 255/255, green: 180/255, blue: 50/255)
            case .avoid:      return Color(red: 220/255, green: 80/255, blue: 80/255)
            }
        }
    }
}
