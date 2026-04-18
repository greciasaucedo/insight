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
    @Published var fastestEvaluation: RouteEvaluation?    = nil
    @Published var accessibleEvaluation: RouteEvaluation? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.6714, longitude: -100.3098),
        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
    )

    // PASO 2: Bandera que indica que una reevaluación acaba de ocurrir,
    // usada por la UI para mostrar el banner "Ruta actualizada".
    @Published var routeJustUpdated = false

    // PASO 3: Estado de ruta activa
    @Published var isRouteActive = false

    // MARK: - Computed

    var activeEvaluation: RouteEvaluation? {
        selectedMode == .fastest ? fastestEvaluation : accessibleEvaluation
    }

    var alternativeEvaluation: RouteEvaluation? {
        selectedMode == .fastest ? accessibleEvaluation : fastestEvaluation
    }

    // MARK: - Privates

    private(set) var originCoordinate = CLLocationCoordinate2D(latitude: 25.6714, longitude: -100.3098)
    private let locationManager = CLLocationManager()

    // Guardamos las rutas "crudas" de MapKit para poder reevaluar sin volver a fetch
    private var cachedMKRoutes: [MKRoute] = []

    // PASO 2: Cancellable del sink que escucha HeatmapStore
    private var tileObserver: AnyCancellable?
    private var lastKnownTileCount = 0

    // MARK: - Init

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        subscribeToTileChanges()
    }

    // MARK: - PASO 2: Suscripción reactiva a HeatmapStore
    //
    // Cada vez que cambia allTiles (ya sea por scan nuevo o por carga inicial),
    // si ya tenemos rutas cacheadas, reevaluamos contra los tiles actuales.
    // Esto es lo que produce el "wow moment": el usuario escanea una zona,
    // y el score de la ruta baja en tiempo real sin tocar nada.

    private func subscribeToTileChanges() {
        tileObserver = HeatmapStore.shared.$scannedTiles
            .dropFirst()                          // ignorar el valor inicial
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newScanned in
                guard let self else { return }
                let total = HeatmapStore.shared.allTiles.count
                guard total != self.lastKnownTileCount else { return }
                self.lastKnownTileCount = total
                self.reevaluateWithCurrentTiles()
            }
    }

    private func reevaluateWithCurrentTiles() {
        guard !cachedMKRoutes.isEmpty else { return }
        let tiles = HeatmapStore.shared.allTiles
        let evaluations = cachedMKRoutes.map { RouteEngine.evaluate(route: $0, tiles: tiles) }

        let prevFastest    = fastestEvaluation?.accessibilityScore
        let prevAccessible = accessibleEvaluation?.accessibilityScore

        fastestEvaluation    = evaluations.first
        if evaluations.count > 1 {
            accessibleEvaluation = RouteEngine.pickMostAccessible(from: evaluations)
        } else {
            accessibleEvaluation = evaluations.first
        }

        // Solo disparar el banner si el score cambió perceptiblemente (±3 puntos)
        let fastChanged       = abs((fastestEvaluation?.accessibilityScore    ?? 0) - (prevFastest    ?? 0)) >= 3
        let accessibleChanged = abs((accessibleEvaluation?.accessibilityScore ?? 0) - (prevAccessible ?? 0)) >= 3

        if fastChanged || accessibleChanged {
            withAnimation(.spring(response: 0.4)) { routeJustUpdated = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation { self.routeJustUpdated = false }
            }
        }
    }

    // MARK: - Actions

    func select(destination: MockDestination) {
        selectedDestination = destination
        isRouteActive = false
        lastKnownTileCount = HeatmapStore.shared.allTiles.count
        fetchRoutes(to: destination)
    }

    func switchMode(to mode: RouteMode) {
        withAnimation(.spring(response: 0.35)) { selectedMode = mode }
        if let eval = activeEvaluation { focusMap(on: eval.route) }
    }

    // PASO 3: Inicia la ruta activa
    func startRoute() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isRouteActive = true
        }
        if let eval = activeEvaluation { focusMap(on: eval.route) }
    }

    func stopRoute() {
        withAnimation(.spring(response: 0.35)) { isRouteActive = false }
    }

    func reset() {
        selectedDestination  = nil
        fastestEvaluation    = nil
        accessibleEvaluation = nil
        errorMessage         = nil
        selectedMode         = .accessible
        isRouteActive        = false
        cachedMKRoutes       = []
    }

    // MARK: - Route Fetching

    private func fetchRoutes(to destination: MockDestination) {
        isLoading = true
        errorMessage = nil
        fastestEvaluation    = nil
        accessibleEvaluation = nil
        cachedMKRoutes       = []

        let origin = MKMapItem(placemark: MKPlacemark(coordinate: originCoordinate))
        let dest   = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        origin.name = "Tu ubicación"
        dest.name   = destination.name

        let request = MKDirections.Request()
        request.source      = origin
        request.destination = dest
        request.transportType = .walking
        request.requestsAlternateRoutes = true

        MKDirections(request: request).calculate { [weak self] response, error in
            guard let self else { return }
            Task { @MainActor in
                self.isLoading = false
                if let error {
                    self.generateMockRoutes(to: destination, errorMsg: error.localizedDescription)
                    return
                }
                guard let response, !response.routes.isEmpty else {
                    self.generateMockRoutes(to: destination, errorMsg: nil)
                    return
                }
                // Cachear las rutas crudas para reevaluar luego sin re-fetch
                self.cachedMKRoutes = response.routes

                let tiles = HeatmapStore.shared.allTiles        // ← usa allTiles
                let evaluations = response.routes.map { RouteEngine.evaluate(route: $0, tiles: tiles) }

                self.fastestEvaluation = evaluations.first
                self.accessibleEvaluation = evaluations.count > 1
                    ? RouteEngine.pickMostAccessible(from: evaluations)
                    : evaluations.first

                if let eval = self.activeEvaluation { self.focusMap(on: eval.route) }
            }
        }
    }

    // MARK: - Mock routes (fallback para simulador)

    private func generateMockRoutes(to destination: MockDestination, errorMsg: String?) {
        let origin = originCoordinate
        let dest   = destination.coordinate

        let directPoints: [CLLocationCoordinate2D] = [
            origin,
            CLLocationCoordinate2D(
                latitude:  (origin.latitude  + dest.latitude)  / 2,
                longitude: (origin.longitude + dest.longitude) / 2
            ),
            dest
        ]
        let detourMid = CLLocationCoordinate2D(
            latitude:  origin.latitude  + (dest.latitude  - origin.latitude)  * 0.5 + 0.001,
            longitude: origin.longitude + (dest.longitude - origin.longitude) * 0.5 - 0.001
        )
        let detourPoints: [CLLocationCoordinate2D] = [origin, detourMid, dest]

        let directPolyline = MKPolyline(coordinates: directPoints,  count: directPoints.count)
        let detourPolyline = MKPolyline(coordinates: detourPoints,  count: detourPoints.count)

        let directRoute = MockRoute(polyline: directPolyline,  distance: 820,  time: 660)
        let detourRoute = MockRoute(polyline: detourPolyline,  distance: 1050, time: 840)

        // Cachear también los mock routes para que reevalúen igual
        cachedMKRoutes = [directRoute, detourRoute]

        let tiles = HeatmapStore.shared.allTiles                // ← usa allTiles
        fastestEvaluation    = RouteEngine.evaluate(route: directRoute, tiles: tiles)
        accessibleEvaluation = RouteEngine.evaluate(route: detourRoute, tiles: tiles)

        // Si no hay tiles aún, inyectar scores narrativos para el demo
        if tiles.isEmpty {
            fastestEvaluation = RouteEvaluation(
                route: directRoute,
                accessibilityScore: 54,
                tilesNearby: [],
                explanations: [
                    "Pasa por 1 tramo con accesibilidad limitada",
                    "Cruza zona con escaleras detectadas"
                ]
            )
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
        }
        if let eval = activeEvaluation { focusMap(on: eval.route) }
    }

    // MARK: - Map helpers

    private func focusMap(on route: MKRoute) {
        let rect   = route.polyline.boundingMapRect
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

final class MockRoute: MKRoute {
    private let _polyline: MKPolyline
    private let _distance: CLLocationDistance
    private let _time: TimeInterval

    init(polyline: MKPolyline, distance: CLLocationDistance, time: TimeInterval) {
        _polyline = polyline; _distance = distance; _time = time
        super.init()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var polyline: MKPolyline              { _polyline }
    override var distance: CLLocationDistance      { _distance }
    override var expectedTravelTime: TimeInterval  { _time }
    override var name: String                      { "" }
    override var advisoryNotices: [String]         { [] }
    override var hasHighways: Bool                 { false }
    override var hasTolls: Bool                    { false }
    override var transportType: MKDirectionsTransportType { .walking }
    override var steps: [MKRoute.Step]             { [] }
}
