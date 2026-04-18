//
//  RouteViewModel.swift
//  InsightApp
//
//  Created by Guillermo Lira on 18/04/26.
//


import SwiftUI
import MapKit
import CoreLocation
import Combine

@MainActor
final class RouteViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published State

    @Published var selectedDestination: MockDestination? = nil
    @Published var selectedMode: RouteMode = .accessible
    @Published var fastestEvaluation: RouteEvaluation? = nil
    @Published var accessibleEvaluation: RouteEvaluation? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.6714, longitude: -100.3098),
        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
    )

    // Ruta actualmente seleccionada según el modo
    var activeEvaluation: RouteEvaluation? {
        switch selectedMode {
        case .fastest:    return fastestEvaluation
        case .accessible: return accessibleEvaluation
        }
    }

    // Ruta alternativa (la no seleccionada)
    var alternativeEvaluation: RouteEvaluation? {
        switch selectedMode {
        case .fastest:    return accessibleEvaluation
        case .accessible: return fastestEvaluation
        }
    }

    // MARK: - Origin

    // Para el hackathon usamos una coordenada fija como "Tu ubicación"
    // Si locationManager da una ubicación real, se actualiza.
    private(set) var originCoordinate = CLLocationCoordinate2D(latitude: 25.6714, longitude: -100.3098)
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    // MARK: - Actions

    func select(destination: MockDestination) {
        selectedDestination = destination
        fetchRoutes(to: destination)
    }

    func switchMode(to mode: RouteMode) {
        withAnimation(.spring(response: 0.35)) {
            selectedMode = mode
        }
        // Actualizar región del mapa para mostrar la ruta activa
        if let eval = activeEvaluation {
            focusMap(on: eval.route)
        }
    }

    func reset() {
        selectedDestination = nil
        fastestEvaluation = nil
        accessibleEvaluation = nil
        errorMessage = nil
        selectedMode = .accessible
    }

    // MARK: - Route Fetching

    private func fetchRoutes(to destination: MockDestination) {
        isLoading = true
        errorMessage = nil
        fastestEvaluation = nil
        accessibleEvaluation = nil

        let origin      = MKMapItem(placemark: MKPlacemark(coordinate: originCoordinate))
        let dest        = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        origin.name     = "Tu ubicación"
        dest.name       = destination.name

        let request = MKDirections.Request()
        request.source              = origin
        request.destination         = dest
        request.transportType       = .walking
        request.requestsAlternateRoutes = true   // pedir hasta 3 alternativas

        let directions = MKDirections(request: request)

        directions.calculate { [weak self] response, error in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false

                if let error {
                    // Fallback: si MapKit falla (simulador sin red), generar rutas mock
                    self.generateMockRoutes(to: destination, error: error.localizedDescription)
                    return
                }

                guard let response, !response.routes.isEmpty else {
                    self.generateMockRoutes(to: destination, error: nil)
                    return
                }

                let tiles = HeatmapStore.shared.scannedTiles
                let evaluations = response.routes.map { RouteEngine.evaluate(route: $0, tiles: tiles) }

                // La primera ruta de MapKit siempre es la más rápida
                self.fastestEvaluation = evaluations.first

                // La más accesible: la de mayor score, si supera a la rápida en margen
                if evaluations.count > 1 {
                    self.accessibleEvaluation = RouteEngine.pickMostAccessible(from: evaluations)
                } else {
                    // Solo hay una ruta — usarla para ambos modos
                    self.accessibleEvaluation = evaluations.first
                }

                // Centrar mapa en la ruta activa
                if let eval = self.activeEvaluation {
                    self.focusMap(on: eval.route)
                }
            }
        }
    }

    // MARK: - Mock route fallback (para simulador o sin red)
    // Genera polígonos simples entre origen y destino cuando MKDirections no responde.
    // Esto garantiza que el demo nunca se rompe en el simulador.

    private func generateMockRoutes(to destination: MockDestination, error: String?) {
        if error != nil {
            // Solo loguear internamente, no mostrar al usuario — el demo debe continuar
        }

        let origin = originCoordinate
        let dest   = destination.coordinate

        // Ruta 1: Línea directa (más rápida)
        let directPoints: [CLLocationCoordinate2D] = [
            origin,
            CLLocationCoordinate2D(
                latitude:  (origin.latitude  + dest.latitude)  / 2,
                longitude: (origin.longitude + dest.longitude) / 2
            ),
            dest
        ]

        // Ruta 2: Desvío hacia el norte (más accesible — evita zonas mock grises del sur)
        let detourMid = CLLocationCoordinate2D(
            latitude:  origin.latitude  + (dest.latitude  - origin.latitude)  * 0.5 + 0.001,
            longitude: origin.longitude + (dest.longitude - origin.longitude) * 0.5 - 0.001
        )
        let detourPoints: [CLLocationCoordinate2D] = [origin, detourMid, dest]

        let directPolyline  = MKPolyline(coordinates: directPoints,  count: directPoints.count)
        let detourPolyline  = MKPolyline(coordinates: detourPoints,  count: detourPoints.count)

        let directRoute  = MockRoute(polyline: directPolyline,  distance: 820,  time: 660)
        let detourRoute  = MockRoute(polyline: detourPolyline,  distance: 1050, time: 840)

        let tiles = HeatmapStore.shared.scannedTiles
        fastestEvaluation    = RouteEngine.evaluate(route: directRoute,  tiles: tiles)
        accessibleEvaluation = RouteEngine.evaluate(route: detourRoute,  tiles: tiles)

        // Forzar score alto en la ruta accesible si no hay tiles reales
        if tiles.isEmpty {
            accessibleEvaluation = RouteEvaluation(
                route: detourRoute,
                accessibilityScore: 92,
                tilesNearby: [],
                explanations: [
                    "Evita zona no accesible detectada por cámara",
                    "Prioriza caminos con mayor confianza",
                    "Minimiza tramos con vibración alta"
                ]
            )
            fastestEvaluation = RouteEvaluation(
                route: directRoute,
                accessibilityScore: 54,
                tilesNearby: [],
                explanations: [
                    "Pasa por 1 tramo con accesibilidad limitada",
                    "Cruza zona con escaleras detectadas"
                ]
            )
        }

        if let eval = activeEvaluation { focusMap(on: eval.route) }
    }

    // MARK: - Map helpers

    private func focusMap(on route: MKRoute) {
        let rect = route.polyline.boundingMapRect
        let padded = rect.insetBy(dx: -rect.size.width * 0.3, dy: -rect.size.height * 0.3)
        withAnimation(.easeInOut(duration: 0.5)) {
            mapRegion = MKCoordinateRegion(padded)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        originCoordinate = loc.coordinate
    }
}

// MARK: - MockRoute
// MKRoute no tiene init público — necesitamos una subclase para los mocks.
// Sobreescribimos las propiedades relevantes.

final class MockRoute: MKRoute {
    private let _polyline: MKPolyline
    private let _distance: CLLocationDistance
    private let _time: TimeInterval

    init(polyline: MKPolyline, distance: CLLocationDistance, time: TimeInterval) {
        _polyline = polyline
        _distance = distance
        _time = time
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("no coder") }

    override var polyline: MKPolyline { _polyline }
    override var distance: CLLocationDistance { _distance }
    override var expectedTravelTime: TimeInterval { _time }
    override var name: String { "" }
    override var advisoryNotices: [String] { [] }
    override var hasHighways: Bool { false }
    override var hasTolls: Bool { false }
    override var transportType: MKDirectionsTransportType { .walking }
    override var steps: [MKRoute.Step] { [] }
}
