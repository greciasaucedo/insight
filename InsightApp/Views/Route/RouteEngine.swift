//
//  RouteEngine.swift
//  InsightApp
//
//  Created by Guillermo Lira on 18/04/26.
//


import Foundation
import MapKit
import CoreLocation

// MARK: - Mock Destinations

struct MockDestination: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let icon: String

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MockDestination, rhs: MockDestination) -> Bool { lhs.id == rhs.id }

    static let all: [MockDestination] = [
        MockDestination(
            name: "Biblioteca",
            subtitle: "Centro de información",
            coordinate: CLLocationCoordinate2D(latitude: 25.6728, longitude: -100.3085),
            icon: "books.vertical.fill"
        ),
        MockDestination(
            name: "Entrada principal",
            subtitle: "Acceso norte del campus",
            coordinate: CLLocationCoordinate2D(latitude: 25.6700, longitude: -100.3110),
            icon: "building.columns.fill"
        ),
        MockDestination(
            name: "Cafetería",
            subtitle: "Planta baja, edificio central",
            coordinate: CLLocationCoordinate2D(latitude: 25.6720, longitude: -100.3120),
            icon: "fork.knife"
        )
    ]
}

// MARK: - Route Mode

enum RouteMode: String, CaseIterable, Identifiable {
    case fastest    = "Más rápida"
    case accessible = "Más accesible"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fastest:    return "bolt.fill"
        case .accessible: return "figure.roll"
        }
    }
}

// MARK: - Route Evaluation Result

struct RouteEvaluation {
    let route: MKRoute
    let accessibilityScore: Int
    let tilesNearby: [TileImpact]
    let explanations: [String]

    var accessibilityLabel: String {
        switch accessibilityScore {
        case 80...100: return "Accesibilidad alta"
        case 50...79:  return "Accesibilidad media"
        default:       return "Accesibilidad baja"
        }
    }

    var accessibilityColor: AccessibilityLevel {
        switch accessibilityScore {
        case 70...100: return .accessible
        case 40...69:  return .limited
        default:       return .notAccessible
        }
    }

    var distanceText: String {
        let m = route.distance
        return m < 1000 ? "\(Int(m)) m" : String(format: "%.1f km", m / 1000)
    }

    var timeText: String {
        let minutes = Int(route.expectedTravelTime / 60)
        return minutes < 1 ? "< 1 min" : "\(minutes) min"
    }
}

struct TileImpact {
    let tile: AccessibilityTile
    let penalty: Int
    let distanceToRoute: CLLocationDistance
}

// MARK: - Route Engine

final class RouteEngine {

    /// Distancia máxima (metros) para considerar que un tile impacta la ruta
    static let proximityThreshold: CLLocationDistance = 60

    // MARK: Evaluate

    /// Evalúa una ruta contra un array de tiles.
    /// Llama con `HeatmapStore.shared.allTiles` para garantizar consistencia.
    static func evaluate(route: MKRoute, tiles: [AccessibilityTile]) -> RouteEvaluation {
        let routePoints = extractPoints(from: route.polyline)
        var score  = 100
        var impacts: [TileImpact] = []

        for tile in tiles {
            let dist = minDistance(from: tile.coordinate, toRoutePoints: routePoints)
            guard dist <= proximityThreshold else { continue }
            let penalty = penaltyFor(tile: tile)
            if penalty > 0 {
                score -= penalty
                impacts.append(TileImpact(tile: tile, penalty: penalty, distanceToRoute: dist))
            }
        }

        score = max(0, score)

        // Generar frases explicativas
        var explanations: [String] = []
        let notAccessible = impacts.filter { $0.tile.accessibilityLevel == .notAccessible }.count
        let limited       = impacts.filter { $0.tile.accessibilityLevel == .limited       }.count
        let userScanned   = impacts.filter { $0.tile.isUserScanned                        }.count

        if notAccessible > 0 {
            explanations.append("Cruza \(notAccessible) zona\(notAccessible > 1 ? "s" : "") no accesible\(notAccessible > 1 ? "s" : "")")
        }
        if limited > 0 {
            explanations.append("Pasa por \(limited) tramo\(limited > 1 ? "s" : "") con accesibilidad limitada")
        }
        if userScanned > 0 {
            explanations.append("\(userScanned) zona\(userScanned > 1 ? "s" : "") escaneada\(userScanned > 1 ? "s" : "") en el trayecto")
        }
        let uniqueReasons = Array(Set(impacts.flatMap { $0.tile.reasons }.filter { !$0.isEmpty })).prefix(2)
        explanations.append(contentsOf: uniqueReasons)

        if impacts.isEmpty {
            explanations = [
                "No se detectaron obstáculos en el trayecto",
                "Todas las zonas cercanas son accesibles"
            ]
        }

        return RouteEvaluation(
            route: route,
            accessibilityScore: score,
            tilesNearby: impacts,
            explanations: Array(explanations.prefix(4))
        )
    }

    // MARK: Penalty

    private static func penaltyFor(tile: AccessibilityTile) -> Int {
        var base: Int
        switch tile.accessibilityLevel {
        case .notAccessible: base = 25
        case .limited:       base = 10
        case .accessible:    return 0
        case .noData:        return 0
        }
        if tile.isUserScanned  { base = Int(Double(base) * 1.4) }   // +40% si lo escaneó el usuario
        if tile.confidenceScore < 0.4 { base = Int(Double(base) * 0.6) }  // -40% si confianza baja
        return base
    }

    // MARK: Geometry

    static func extractPoints(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return coords
    }

    static func minDistance(
        from coord: CLLocationCoordinate2D,
        toRoutePoints points: [CLLocationCoordinate2D]
    ) -> CLLocationDistance {
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return points.reduce(CLLocationDistance.greatestFiniteMagnitude) { best, pt in
            min(best, loc.distance(from: CLLocation(latitude: pt.latitude, longitude: pt.longitude)))
        }
    }

    // MARK: Pick best accessible

    static func pickMostAccessible(from evaluations: [RouteEvaluation]) -> RouteEvaluation? {
        guard !evaluations.isEmpty else { return nil }
        guard let best = evaluations.max(by: { $0.accessibilityScore < $1.accessibilityScore }),
              let first = evaluations.first else { return evaluations.first }
        // Solo promover si gana por margen significativo
        return best.accessibilityScore >= first.accessibilityScore + 10 ? best : first
    }
}
