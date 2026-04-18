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

    // Hashable manual porque CLLocationCoordinate2D no conforma Hashable
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MockDestination, rhs: MockDestination) -> Bool { lhs.id == rhs.id }

    // Destinos demo alrededor del campus Tec de Monterrey (25.6714, -100.3098)
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
    let accessibilityScore: Int          // 0–100
    let tilesNearby: [TileImpact]        // tiles que afectan esta ruta
    let explanations: [String]           // frases human-readable del por qué

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
        let meters = route.distance
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }

    var timeText: String {
        let minutes = Int(route.expectedTravelTime / 60)
        if minutes < 1 { return "< 1 min" }
        return "\(minutes) min"
    }
}

struct TileImpact {
    let tile: AccessibilityTile
    let penalty: Int
    let distanceToRoute: CLLocationDistance  // metros
}

// MARK: - Route Engine

final class RouteEngine {

    // Distancia máxima en metros para considerar que un tile "está cerca" de la ruta
    static let proximityThreshold: CLLocationDistance = 60

    // MARK: Evaluate a route against heatmap tiles

    static func evaluate(route: MKRoute, tiles: [AccessibilityTile]) -> RouteEvaluation {
        let routePoints = extractPoints(from: route.polyline)
        var score = 100
        var impacts: [TileImpact] = []
        var explanationSet: [String] = []

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

        // Generar explicaciones legibles
        let notAccessibleCount = impacts.filter { $0.tile.accessibilityLevel == .notAccessible }.count
        let limitedCount       = impacts.filter { $0.tile.accessibilityLevel == .limited }.count
        let userScannedCount   = impacts.filter { $0.tile.isUserScanned }.count

        if notAccessibleCount > 0 {
            explanationSet.append("Cruza \(notAccessibleCount) zona\(notAccessibleCount > 1 ? "s" : "") no accesible\(notAccessibleCount > 1 ? "s" : "")")
        }
        if limitedCount > 0 {
            explanationSet.append("Pasa por \(limitedCount) tramo\(limitedCount > 1 ? "s" : "") con accesibilidad limitada")
        }
        if userScannedCount > 0 {
            explanationSet.append("Incluye \(userScannedCount) zona\(userScannedCount > 1 ? "s" : "") escaneada\(userScannedCount > 1 ? "s" : "") por usuarios")
        }

        // Razones específicas de los tiles cercanos
        let allReasons = impacts.flatMap { $0.tile.reasons }.filter { !$0.isEmpty }
        let uniqueReasons = Array(Set(allReasons)).prefix(2)
        explanationSet.append(contentsOf: uniqueReasons)

        if impacts.isEmpty {
            explanationSet.append("No se detectaron obstáculos en el trayecto")
            explanationSet.append("Todas las zonas cercanas son accesibles")
        }

        return RouteEvaluation(
            route: route,
            accessibilityScore: score,
            tilesNearby: impacts,
            explanations: Array(explanationSet.prefix(4))
        )
    }

    // MARK: Penalty logic

    private static func penaltyFor(tile: AccessibilityTile) -> Int {
        var base: Int
        switch tile.accessibilityLevel {
        case .notAccessible: base = 25
        case .limited:       base = 10
        case .accessible:    return 0   // tiles azules no penalizan
        case .noData:        return 0
        }

        // Tiles escaneados por el usuario tienen más peso (más confiables)
        if tile.isUserScanned {
            base = Int(Double(base) * 1.4)
        }

        // Reducir penalización si la confianza es baja
        if tile.confidenceScore < 0.4 {
            base = Int(Double(base) * 0.6)
        }

        return base
    }

    // MARK: Geometry helpers

    /// Extrae los puntos de una polyline de MapKit como array de CLLocationCoordinate2D
    static func extractPoints(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return coords
    }

    /// Distancia mínima de una coordenada a cualquier punto del array de puntos de ruta
    static func minDistance(
        from coord: CLLocationCoordinate2D,
        toRoutePoints points: [CLLocationCoordinate2D]
    ) -> CLLocationDistance {
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        var minDist = CLLocationDistance.greatestFiniteMagnitude
        for point in points {
            let d = loc.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            if d < minDist { minDist = d }
        }
        return minDist
    }

    // MARK: Pick best accessible route from alternatives

    /// Dado un array de evaluaciones, devuelve la de mayor score de accesibilidad.
    /// Si ninguna supera la base en +10 puntos, devuelve la primera (más rápida).
    static func pickMostAccessible(from evaluations: [RouteEvaluation]) -> RouteEvaluation? {
        guard !evaluations.isEmpty else { return nil }
        let best = evaluations.max { $0.accessibilityScore < $1.accessibilityScore }
        let first = evaluations.first!
        // Solo promover la "más accesible" si gana por margen significativo
        if let best, best.accessibilityScore >= first.accessibilityScore + 10 {
            return best
        }
        return first
    }
}
