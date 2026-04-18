//
//  Ghostlayerstore.swift
//  InsightApp
//
//  Created by Guillermo Lira on 18/04/26.
//
//  Fuente de datos para la capa ghost.
//  Agrega observaciones de HeatmapStore y construye:
//    • zonas de densidad por perfil (cuántos tiles de un perfil hay cerca)
//    • segmentos evitados (tiles con score < umbral para ese perfil)
//    • flujo de accesibilidad (passabilityScore promedio por celda de grilla)
//
//  Todos los datos son calculados sobre los tiles existentes,
//  sin necesidad de backend extra. En producción se reemplazaría
//  por un endpoint de agregados en Supabase.
//

import Foundation
import CoreLocation
import Combine

// MARK: - GhostCell

/// Una celda de la grilla ghost con densidad e intensidad calculadas.
struct GhostCell: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D   // centro de la celda
    let density: Double                      // 0.0–1.0 cuántos tiles hay en esta zona
    let avoidance: Double                    // 0.0–1.0 qué tan evitada es (1 = muy evitada)
    let passability: Double                  // 0.0–1.0 passabilityScore promedio
    let dominantProfile: AccessibilityProfile // perfil con más observaciones en esta celda
    let observationCount: Int

    /// Intensidad visual = combinación de densidad y evitance
    var visualIntensity: Double {
        (density * 0.4 + avoidance * 0.6).clamped(to: 0...1)
    }
}

// MARK: - GhostLayerFilter

struct GhostLayerFilter {
    var activeProfile: AccessibilityProfile?   // nil = todos los perfiles
    var showAvoided: Bool   = true             // zonas evitadas (rojo/naranja)
    var showFlow: Bool      = true             // flujo accesible (teal)
    var showDensity: Bool   = true             // densidad de uso
    var minDensity: Double  = 0.0             // filtrar celdas con poca actividad
}

// MARK: - GhostLayerStore

@MainActor
final class GhostLayerStore: ObservableObject {
    static let shared = GhostLayerStore()
    private init() {}

    @Published private(set) var cells: [GhostCell] = []
    @Published var filter = GhostLayerFilter()
    @Published var isVisible = false

    private var cancellables = Set<AnyCancellable>()

    // Tamaño de celda en grados (~55m × 55m)
    private let cellSizeDeg: Double = 0.0005

    // MARK: - Setup

    func setup() {
        // Recalcular cuando cambian los tiles
        HeatmapStore.shared.$baseTiles
            .combineLatest(HeatmapStore.shared.$scannedTiles)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.recompute()
            }
            .store(in: &cancellables)

        recompute()
    }

    // MARK: - Recompute

    func recompute() {
        let tiles = HeatmapStore.shared.allTiles
        guard !tiles.isEmpty else { cells = []; return }

        // Agrupar tiles en celdas de la grilla
        var grid: [String: [AccessibilityTile]] = [:]

        for tile in tiles {
            let key = cellKey(tile.coordinate)
            grid[key, default: []].append(tile)
        }

        // Calcular valores por celda
        let maxCount = grid.values.map(\.count).max() ?? 1

        cells = grid.compactMap { key, tilesInCell -> GhostCell? in
            guard let center = cellCenter(from: key) else { return nil }

            // Densidad normalizada
            let density = Double(tilesInCell.count) / Double(maxCount)

            // Evitance: proporción de tiles con score bajo
            let profile = filter.activeProfile ?? ProfileService.shared.currentProfile
            let avoidThreshold = profile.thresholds.alertThreshold
            let avoided = tilesInCell.filter { $0.accessibilityScore < avoidThreshold }
            let avoidance = Double(avoided.count) / Double(tilesInCell.count)

            // Passability promedio
            let passValues = tilesInCell.compactMap(\.passabilityScore)
            let passability = passValues.isEmpty
                ? Double(tilesInCell.map(\.accessibilityScore).reduce(0, +)) / Double(tilesInCell.count) / 100.0
                : passValues.reduce(0, +) / Double(passValues.count)

            // Perfil dominante
            let profileCounts = Dictionary(
                grouping: tilesInCell.compactMap(\.profileUsed),
                by: { $0 }
            ).mapValues(\.count)
            let dominantRaw = profileCounts.max(by: { $0.value < $1.value })?.key ?? "standard"
            let dominantProfile = AccessibilityProfile(rawValue: dominantRaw) ?? .standard

            // Filtrar si no cumple densidad mínima
            guard density >= filter.minDensity else { return nil }

            // Filtrar por perfil activo si hay uno seleccionado
            if let activeProfile = filter.activeProfile {
                let hasProfileData = tilesInCell.contains { tile in
                    tile.profileUsed == activeProfile.rawValue ||
                    tile.sourceType == .mock  // mock tiles siempre visibles
                }
                guard hasProfileData else { return nil }
            }

            return GhostCell(
                coordinate:       center,
                density:          density,
                avoidance:        avoidance,
                passability:      passability,
                dominantProfile:  dominantProfile,
                observationCount: tilesInCell.count
            )
        }
        .sorted { $0.visualIntensity < $1.visualIntensity }  // dibujar menos intensas primero
    }

    // MARK: - Filtered cells for rendering

    var visibleCells: [GhostCell] {
        cells.filter { cell in
            if filter.showAvoided  && cell.avoidance > 0.5 { return true }
            if filter.showFlow     && cell.passability > 0.6 { return true }
            if filter.showDensity  && cell.density > 0.3 { return true }
            return false
        }
    }

    // MARK: - Grid helpers

    private func cellKey(_ coord: CLLocationCoordinate2D) -> String {
        let latBucket = Int(coord.latitude  / cellSizeDeg)
        let lonBucket = Int(coord.longitude / cellSizeDeg)
        return "\(latBucket)_\(lonBucket)"
    }

    private func cellCenter(from key: String) -> CLLocationCoordinate2D? {
        let parts = key.split(separator: "_").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CLLocationCoordinate2D(
            latitude:  parts[0] * cellSizeDeg + cellSizeDeg / 2,
            longitude: parts[1] * cellSizeDeg + cellSizeDeg / 2
        )
    }
}
