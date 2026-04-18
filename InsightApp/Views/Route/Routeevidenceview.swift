//
//  Routeevidenceview.swift
//  InsightApp
//
//  Created by Guillermo Lira on 18/04/26.
//

//
//  RouteEvidenceView.swift
//  InsightApp
//
//  Punto 7: explicaciones de ruta ligadas a evidencia concreta.
//  Se usa dentro de RouteView en lugar del ExplanationRow genérico.
//
//  También incluye:
//  • RouteEngine+Evidence: extensión que genera explicaciones ricas
//  • RouteEvaluation extendido con campo `evidenceItems`
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Evidence Item

/// Un item de evidencia específico ligado a un tile y a una razón concreta.
struct RouteEvidenceItem: Identifiable {
    let id = UUID()
    let tileID: UUID
    let headline: String          // frase principal, e.g. "Escaleras detectadas"
    let detail: String            // detalle, e.g. "Alta confianza · Observación reciente"
    let icon: String
    let severity: EvidenceSeverity
    let sourceType: TileSourceType
    let confidenceScore: Double
    let createdAt: Date
}

enum EvidenceSeverity {
    case positive, warning, critical

    var color: Color {
        switch self {
        case .positive:  return Color(red: 136/255, green: 205/255, blue: 212/255)
        case .warning:   return Color(red: 255/255, green: 214/255, blue: 102/255)
        case .critical:  return Color(red: 220/255, green: 80/255,  blue: 80/255)
        }
    }

    var icon: String {
        switch self {
        case .positive:  return "checkmark.circle.fill"
        case .warning:   return "exclamationmark.triangle.fill"
        case .critical:  return "xmark.octagon.fill"
        }
    }
}

// MARK: - RouteEngine extension (evidence-based explanations)

extension RouteEngine {

    /// Genera items de evidencia concretos para mostrar en RouteEvidenceView.
    static func buildEvidenceItems(
        from impacts: [TileImpact],
        profile: AccessibilityProfile
    ) -> [RouteEvidenceItem] {

        var items: [RouteEvidenceItem] = []

        for impact in impacts.prefix(6) {
            let tile   = impact.tile
            let label  = tile.detectedLabel?.lowercased()

            // ── Severidad ────────────────────────────────────────────────
            let severity: EvidenceSeverity
            switch tile.accessibilityLevel {
            case .accessible:    severity = .positive
            case .limited:       severity = .warning
            case .notAccessible: severity = .critical
            case .noData:        continue
            }

            // ── Headline por etiqueta + perfil ───────────────────────────
            let headline: String
            switch label {
            case "stairs":
                headline = profile == .wheelchair
                    ? "Escaleras — barrera total para silla de ruedas"
                    : "Escaleras en el trayecto"
            case "ramp":
                let slopeOk = (tile.slopeScore ?? 1.0) > 0.50
                headline = slopeOk
                    ? "Rampa accesible detectada"
                    : "Rampa con inclinación elevada"
            case "obstacle":
                headline = "Obstáculo detectado — zona de precaución"
            case "flat":
                let vibOk = (tile.vibrationScore ?? 1.0) > 0.60
                headline = vibOk
                    ? "Superficie plana y suave"
                    : "Superficie plana con irregularidades"
            default:
                headline = tile.reasons.first ?? "Zona analizada"
            }

            // ── Detail: confianza + recencia + fuente ────────────────────
            var detailParts: [String] = []

            // Confianza
            switch tile.confidenceScore {
            case 0.75...: detailParts.append("Confianza alta")
            case 0.45..<0.75: detailParts.append("Confianza media")
            default: detailParts.append("Confianza baja")
            }

            // Recencia
            let age = Date().timeIntervalSince(tile.createdAt)
            switch age {
            case ..<(24 * 3600):
                detailParts.append("Observación de hoy")
            case ..<(7 * 24 * 3600):
                let days = Int(age / 86400)
                detailParts.append("Hace \(days) día\(days > 1 ? "s" : "")")
            default:
                detailParts.append("Dato de más de una semana")
            }

            // Fuente
            detailParts.append(tile.sourceType.displayName)

            // Sensores adicionales
            if let vib = tile.vibrationScore, vib < 0.35 {
                detailParts.append("Vibración elevada")
            }
            if let sl = tile.slopeScore, sl < 0.40 {
                detailParts.append("Inclinación significativa")
            }

            items.append(RouteEvidenceItem(
                tileID:          tile.id,
                headline:        headline,
                detail:          detailParts.joined(separator: " · "),
                icon:            tileIcon(label: label),
                severity:        severity,
                sourceType:      tile.sourceType,
                confidenceScore: tile.confidenceScore,
                createdAt:       tile.createdAt
            ))
        }

        // Si no hubo impactos negativos, agregar item positivo
        if items.isEmpty || items.allSatisfy({ $0.severity == .positive }) {
            items.insert(RouteEvidenceItem(
                tileID:          UUID(),
                headline:        "Sin obstáculos detectados en el trayecto",
                detail:          "Todas las zonas cercanas son accesibles",
                icon:            "checkmark.shield.fill",
                severity:        .positive,
                sourceType:      .remote,
                confidenceScore: 0.8,
                createdAt:       Date()
            ), at: 0)
        }

        return items
    }

    private static func tileIcon(label: String?) -> String {
        switch label {
        case "stairs":   return "figure.stairs"
        case "ramp":     return "road.lanes"
        case "obstacle": return "exclamationmark.triangle.fill"
        case "flat":     return "checkmark.seal.fill"
        default:         return "mappin.circle"
        }
    }
}

// MARK: - RouteEvidenceView

/// Reemplaza el listado genérico de ExplanationRow en RouteView.
/// Muestra score, confianza, motivo concreto y origen del dato.
struct RouteEvidenceView: View {
    let evaluation: RouteEvaluation
    let profile: AccessibilityProfile
    let teal: Color

    private var evidenceItems: [RouteEvidenceItem] {
        RouteEngine.buildEvidenceItems(from: evaluation.tilesNearby, profile: profile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header: score + confianza ─────────────────────────────────
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Análisis de ruta")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(evaluation.accessibilityScore)")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(evaluation.accessibilityColor.color)
                        Text("/ 100")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Text(evaluation.accessibilityLabel)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(evaluation.accessibilityColor.color)
                }

                Spacer()

                // Confianza promedio de los tiles cercanos
                let avgConf = averageConfidence(evaluation.tilesNearby)
                VStack(spacing: 4) {
                    Text("Confianza")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: avgConf)
                            .stroke(teal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.5), value: avgConf)
                        Text("\(Int(avgConf * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(width: 52, height: 52)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

            // ── Perfil activo ─────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: profile.icon)
                    .font(.system(size: 11)).foregroundColor(teal)
                Text("Optimizada para perfil: \(profile.displayName)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // ── Items de evidencia ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("Por qué se eligió esta ruta")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.top, 16)

                ForEach(evidenceItems) { item in
                    EvidenceRow(item: item)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func averageConfidence(_ impacts: [TileImpact]) -> Double {
        guard !impacts.isEmpty else { return 0.75 }
        return impacts.map(\.tile.confidenceScore).reduce(0, +) / Double(impacts.count)
    }
}

// MARK: - EvidenceRow

struct EvidenceRow: View {
    let item: RouteEvidenceItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icono con color de severidad
            ZStack {
                Circle()
                    .fill(item.severity.color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(item.severity.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.headline)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Icono de fuente
            Image(systemName: item.sourceType.icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - RouteView integration patch (comentado)
//
// En RouteView.swift, dentro del panel donde aparecen las explicaciones,
// reemplazar el bloque ForEach(eval.explanations) por:
//
//   RouteEvidenceView(
//       evaluation: eval,
//       profile: ProfileService.shared.currentProfile,
//       teal: teal
//   )
//
// También en ActiveRouteView, reemplazar el Text(firstExp) por:
//
//   if let first = RouteEngine.buildEvidenceItems(
//       from: eval.tilesNearby, profile: ProfileService.shared.currentProfile
//   ).first {
//       Text(first.headline)
//           .font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
//   }
