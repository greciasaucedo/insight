//
//  Ghostlayerview.swift
//  InsightApp
//
//  Created by Guillermo Lira on 18/04/26.
//
//  Punto 13: Ghost Layer — visualización de comportamiento colectivo.
//  Se integra en MapView como una capa adicional independiente,
//  SIN modificar el código existente de HeatmapTileView.
//
//  INTEGRACIÓN en MapView.swift (solo 3 líneas):
//
//  1. Agregar @ObservedObject al inicio de MapView:
//       @ObservedObject private var ghostStore = GhostLayerStore.shared
//
//  2. Dentro del primer GeometryReader (Layer A), después del ForEach de HeatmapTileView:
//       if ghostStore.isVisible {
//           GhostLayerView(store: ghostStore, mapRegion: vm.region, geoSize: geo.size)
//       }
//
//  3. En el .task del MapView:
//       GhostLayerStore.shared.setup()
//
//  4. Agregar el botón ghost en floatingButtonsColumn (ver GhostToggleButton abajo).
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - GhostLayerView

/// Capa de visualización de comportamiento colectivo.
/// Se pinta encima del heatmap base, por debajo de los tap targets.
struct GhostLayerView: View {
    @ObservedObject var store: GhostLayerStore
    let mapRegion: MKCoordinateRegion
    let geoSize: CGSize

    var body: some View {
        ZStack {
            // ── Capa de densidad / flujo ─────────────────────────────────
            ForEach(store.visibleCells) { cell in
                GhostCellView(
                    cell:      cell,
                    position:  position(for: cell.coordinate),
                    mapRegion: mapRegion
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func position(for coord: CLLocationCoordinate2D) -> CGPoint {
        let latDelta = coord.latitude  - mapRegion.center.latitude
        let lonDelta = coord.longitude - mapRegion.center.longitude
        let x = geoSize.width  / 2 + CGFloat(lonDelta / mapRegion.span.longitudeDelta) * geoSize.width
        let y = geoSize.height / 2 - CGFloat(latDelta / mapRegion.span.latitudeDelta)  * geoSize.height
        return CGPoint(x: x, y: y)
    }
}

// MARK: - GhostCellView

/// Una celda individual del ghost layer.
/// El color codifica el tipo de comportamiento:
///   • Teal suave   → zona muy transitada y accesible (flow positivo)
///   • Naranja      → zona evitada / limitada
///   • Rojo translúcido → zona bloqueada / no accesible para el perfil
///   • Blanco/gris  → zona con datos pero sin patrón claro
struct GhostCellView: View {
    let cell: GhostCell
    let position: CGPoint
    let mapRegion: MKCoordinateRegion

    // Radio en puntos — proporcional al zoom
    private var radius: CGFloat {
        let degreesPerPoint = mapRegion.span.latitudeDelta / 400
        let cellDeg = 0.0005
        return CGFloat(cellDeg / degreesPerPoint) * 0.85
    }

    private var cellColor: Color {
        if cell.avoidance > 0.65 {
            // Zona muy evitada
            return Color(red: 255/255, green: 80/255, blue: 80/255)
        } else if cell.avoidance > 0.35 {
            // Zona parcialmente problemática
            return Color(red: 255/255, green: 160/255, blue: 50/255)
        } else if cell.passability > 0.70 {
            // Flujo accesible positivo
            return Color(red: 100/255, green: 220/255, blue: 200/255)
        } else {
            // Datos neutros
            return Color(white: 0.75)
        }
    }

    /// Opacidad base según intensidad visual de la celda
    private var baseOpacity: Double {
        (0.12 + cell.visualIntensity * 0.30).clamped(to: 0.10...0.45)
    }

    var body: some View {
        ZStack {
            // ── Halo exterior difuso ─────────────────────────────────────
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: cellColor.opacity(baseOpacity * 0.9), location: 0.0),
                            .init(color: cellColor.opacity(baseOpacity * 0.4), location: 0.55),
                            .init(color: cellColor.opacity(0),                 location: 1.0)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
                .frame(width: radius * 2, height: radius * 2)
                .position(position)

            // ── Punto central (solo si hay muchas observaciones) ─────────
            if cell.observationCount >= 2 {
                Circle()
                    .fill(cellColor.opacity(baseOpacity * 1.8))
                    .frame(width: max(4, radius * 0.18), height: max(4, radius * 0.18))
                    .position(position)
            }

            // ── Anillo de perfil dominante ───────────────────────────────
            if cell.density > 0.5 {
                Circle()
                    .stroke(profileRingColor, lineWidth: 1.2)
                    .opacity(0.35)
                    .frame(width: radius * 0.55, height: radius * 0.55)
                    .position(position)
            }
        }
    }

    private var profileRingColor: Color {
        switch cell.dominantProfile {
        case .wheelchair:      return Color(red: 100/255, green: 180/255, blue: 255/255)
        case .elderly:         return Color(red: 255/255, green: 200/255, blue: 100/255)
        case .reducedMobility: return Color(red: 200/255, green: 150/255, blue: 255/255)
        case .standard:        return Color.white
        }
    }
}

// MARK: - GhostLayerControlPanel

/// Panel flotante de control del ghost layer.
/// Se muestra cuando isVisible = true, encima del mapa.
struct GhostLayerControlPanel: View {
    @ObservedObject var store: GhostLayerStore
    let teal: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ───────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(teal)
                Text("Comportamiento colectivo")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        store.isVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 14)

            // ── Filtros de tipo ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Mostrar")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                HStack(spacing: 8) {
                    GhostFilterChip(
                        label: "Evitadas",
                        icon:  "arrow.triangle.turn.up.right.circle.fill",
                        color: Color(red: 1, green: 0.35, blue: 0.35),
                        isOn:  $store.filter.showAvoided
                    )
                    GhostFilterChip(
                        label: "Flujo",
                        icon:  "figure.walk",
                        color: teal,
                        isOn:  $store.filter.showFlow
                    )
                    GhostFilterChip(
                        label: "Densidad",
                        icon:  "circle.grid.3x3.fill",
                        color: Color(white: 0.65),
                        isOn:  $store.filter.showDensity
                    )
                }
                .padding(.horizontal, 14)
            }

            // ── Filtro por perfil ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Perfil")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.top, 10)
                    .padding(.horizontal, 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // "Todos" opción
                        ProfileFilterChip(
                            label:     "Todos",
                            icon:      "person.3.fill",
                            isSelected: store.filter.activeProfile == nil,
                            color:     teal
                        ) {
                            withAnimation { store.filter.activeProfile = nil }
                            store.recompute()
                        }

                        ForEach(AccessibilityProfile.allCases) { profile in
                            ProfileFilterChip(
                                label:     profile.displayName,
                                icon:      profile.icon,
                                isSelected: store.filter.activeProfile == profile,
                                color:     profileColor(profile)
                            ) {
                                withAnimation {
                                    store.filter.activeProfile = profile
                                }
                                store.recompute()
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }

            // ── Leyenda de colores ───────────────────────────────────────
            HStack(spacing: 16) {
                GhostLegendDot(color: Color(red: 1, green: 0.35, blue: 0.35),
                               label: "Zona evitada")
                GhostLegendDot(color: Color(red: 255/255, green: 160/255, blue: 50/255),
                               label: "Limitada")
                GhostLegendDot(color: teal,
                               label: "Flujo positivo")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)

            // ── Estadística rápida ───────────────────────────────────────
            if !store.cells.isEmpty {
                Divider().padding(.horizontal, 14)
                HStack(spacing: 0) {
                    GhostStat(
                        value: "\(store.cells.count)",
                        label: "Zonas",
                        color: teal
                    )
                    Divider().frame(height: 30)
                    GhostStat(
                        value: "\(store.cells.filter { $0.avoidance > 0.5 }.count)",
                        label: "Evitadas",
                        color: Color(red: 1, green: 0.35, blue: 0.35)
                    )
                    Divider().frame(height: 30)
                    GhostStat(
                        value: String(format: "%.0f%%", avgPassability * 100),
                        label: "Accesible",
                        color: .green
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 4)
        .frame(width: 280)
    }

    private var avgPassability: Double {
        guard !store.cells.isEmpty else { return 0 }
        return store.cells.map(\.passability).reduce(0, +) / Double(store.cells.count)
    }

    private func profileColor(_ profile: AccessibilityProfile) -> Color {
        switch profile {
        case .wheelchair:      return Color(red: 100/255, green: 180/255, blue: 255/255)
        case .elderly:         return Color(red: 255/255, green: 200/255, blue: 100/255)
        case .reducedMobility: return Color(red: 200/255, green: 150/255, blue: 255/255)
        case .standard:        return Color.white.opacity(0.8)
        }
    }
}

// MARK: - GhostToggleButton

/// Botón flotante para activar/desactivar el ghost layer.
/// Agregar en floatingButtonsColumn de MapView después del botón de leyenda:
///
///   GhostToggleButton(store: GhostLayerStore.shared, teal: teal)
///
struct GhostToggleButton: View {
    @ObservedObject var store: GhostLayerStore
    let teal: Color

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35)) {
                store.isVisible.toggle()
                if store.isVisible { store.recompute() }
            }
        } label: {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(store.isVisible ? .black : teal)
                .frame(width: 44, height: 44)
                // FIX: dos .background separados evitan el mismatch Color vs some View
                .background(store.isVisible ? teal : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12))
                .background(.regularMaterial,
                             in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
        }
        .accessibilityLabel(store.isVisible ? "Ocultar capa de comportamiento" : "Mostrar capa de comportamiento")
    }
}

// MARK: - Supporting subviews

private struct GhostFilterChip: View {
    let label: String
    let icon: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25)) { isOn.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isOn ? .black : .secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isOn ? color : color.opacity(0.08),
                        in: Capsule())
        }
    }
}

private struct ProfileFilterChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .black : .secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isSelected ? color : Color.secondary.opacity(0.10),
                        in: Capsule())
        }
    }
}

private struct GhostLegendDot: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}

private struct GhostStat: View {
    let value: String
    let label: String
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
