//
//  RouteView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 17/04/26.
//


import SwiftUI
import MapKit

// MARK: - Route Map (UIViewRepresentable)

struct RouteMapView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let activeEvaluation: RouteEvaluation?
    let alternativeEvaluation: RouteEvaluation?
    let heatmapTiles: [AccessibilityTile]

    private let tealUI = UIColor(red: 136/255, green: 205/255, blue: 212/255, alpha: 1)

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isPitchEnabled = false
        map.setRegion(region, animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })

        if !regionsApproxEqual(map.region, region) {
            map.setRegion(region, animated: true)
        }

        // Heatmap circles
        for tile in heatmapTiles where tile.accessibilityLevel != .noData {
            let circle = MKCircle(center: tile.coordinate, radius: 55)
            circle.title = tile.accessibilityLevel.rawOverlayID
            map.addOverlay(circle, level: .aboveRoads)
        }

        // Ruta alternativa primero (debajo)
        if let alt = alternativeEvaluation {
            map.addOverlay(RoutePolylineOverlay(polyline: alt.route.polyline, isActive: false), level: .aboveRoads)
        }
        // Ruta activa encima
        if let active = activeEvaluation {
            map.addOverlay(RoutePolylineOverlay(polyline: active.route.polyline, isActive: true), level: .aboveRoads)
            if let last = RouteEngine.extractPoints(from: active.route.polyline).last {
                let pin = MKPointAnnotation()
                pin.coordinate = last
                pin.title = "Destino"
                map.addAnnotation(pin)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(tealUI: tealUI) }

    private func regionsApproxEqual(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion) -> Bool {
        abs(a.center.latitude - b.center.latitude) < 0.0001 &&
        abs(a.center.longitude - b.center.longitude) < 0.0001
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let tealUI: UIColor
        init(tealUI: UIColor) { self.tealUI = tealUI }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let r = MKCircleRenderer(circle: circle)
                r.lineWidth = 0
                r.fillColor = uiColor(for: circle.title)
                return r
            }
            if let ro = overlay as? RoutePolylineOverlay {
                let r = MKPolylineRenderer(polyline: ro)

                if ro.isActive {
                    r.strokeColor = tealUI
                    r.lineWidth = 5
                    r.lineCap = CGLineCap.round
                    r.lineJoin = CGLineJoin.round
                } else {
                    r.strokeColor = UIColor.systemGray3.withAlphaComponent(0.6)
                    r.lineWidth = 3
                    r.lineDashPattern = [8, 6]
                }

                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let v = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "dest")
            v.markerTintColor = tealUI
            v.glyphImage = UIImage(systemName: "mappin.circle.fill")
            return v
        }

        private func uiColor(for id: String?) -> UIColor {
            switch id {
            case "accessible":    return UIColor(red: 136/255, green: 205/255, blue: 212/255, alpha: 0.35)
            case "limited":       return UIColor(red: 255/255, green: 214/255, blue: 102/255, alpha: 0.35)
            case "notAccessible": return UIColor(red: 160/255, green: 160/255, blue: 165/255, alpha: 0.40)
            default:              return .clear
            }
        }
    }
}

// Helper para exponer un String ID desde AccessibilityLevel
extension AccessibilityLevel {
    var rawOverlayID: String {
        switch self {
        case .accessible:    return "accessible"
        case .limited:       return "limited"
        case .notAccessible: return "notAccessible"
        case .noData:        return "noData"
        }
    }
}

final class RoutePolylineOverlay: MKPolyline {
    var isActive = false
    convenience init(polyline: MKPolyline, isActive: Bool) {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        self.init(coordinates: &coords, count: coords.count)
        self.isActive = isActive
    }
}

// MARK: - Main RouteView

struct RouteView: View {
    @StateObject private var vm = RouteViewModel()
    @ObservedObject private var store = HeatmapStore.shared
    @Environment(\.dismiss) private var dismiss

    let teal = Color(red: 136/255, green: 205/255, blue: 212/255)

    var body: some View {
        ZStack {
            if vm.isRouteActive {
                // PASO 3 — Pantalla de ruta activa
                ActiveRouteView(vm: vm, teal: teal)
                    .transition(.asymmetric(
                        insertion: .push(from: .bottom),
                        removal: .push(from: .top)
                    ))
            } else if vm.selectedDestination == nil {
                destinationPicker
                    .transition(.opacity)
            } else {
                routeScreen
                    .transition(.asymmetric(
                        insertion: .push(from: .trailing),
                        removal: .push(from: .leading)
                    ))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: vm.isRouteActive)
        .animation(.spring(response: 0.4), value: vm.selectedDestination == nil)
        .navigationBarHidden(true)
    }

    // MARK: - Destination Picker

    var destinationPicker: some View {
        ZStack(alignment: .top) {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 36, height: 36)
                            .background(.regularMaterial, in: Circle())
                    }
                    Spacer()
                    Text("Ruta accesible")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 28)

                // Origen mock
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(teal.opacity(0.15)).frame(width: 36, height: 36)
                        Circle().fill(teal).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tu ubicación").font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("Punto de partida").font(.system(size: 13, design: .rounded)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("Actual").font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(teal)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(teal.opacity(0.12), in: Capsule())
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)

                // Divisor con línea punteada
                HStack {
                    Spacer().frame(width: 38)
                    Rectangle().fill(Color.secondary.opacity(0.2))
                        .frame(width: 1.5, height: 20)
                    Spacer()
                }
                .padding(.leading, 20)

                // Label destinos
                HStack {
                    Text("Elige un destino")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                VStack(spacing: 10) {
                    ForEach(MockDestination.all) { dest in
                        Button { vm.select(destination: dest) } label: {
                            DestinationRow(destination: dest, teal: teal)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }
                }

                Spacer()

                // Hint de tiles cargados
                HStack(spacing: 6) {
                    Circle().fill(teal).frame(width: 7, height: 7)
                    Text("\(store.allTiles.count) zonas en el mapa")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 36)
            }
        }
    }

    // MARK: - Route Screen

    var routeScreen: some View {
        VStack(spacing: 0) {
            // Header
            routeHeader

            // Mapa
            ZStack(alignment: .topLeading) {
                if let active = vm.activeEvaluation {
                    RouteMapView(
                        region: vm.mapRegion,
                        activeEvaluation: active,
                        alternativeEvaluation: vm.alternativeEvaluation,
                        heatmapTiles: store.allTiles          // ← allTiles
                    )
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.07))
                        .overlay(ProgressView().tint(teal))
                }

                // PASO 2: Banner "Ruta actualizada"
                if vm.routeJustUpdated {
                    routeUpdatedBanner
                        .padding(12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: UIScreen.main.bounds.height * 0.36)
            .clipped()

            // Panel inferior
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    modePicker.padding(.top, 18)

                    if vm.isLoading {
                        loadingCard
                    } else if let eval = vm.activeEvaluation {
                        summaryCard(eval: eval)
                        ctaButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(UIColor.systemBackground))
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: Route header

    var routeHeader: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35)) { vm.reset() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial, in: Circle())
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle().fill(teal).frame(width: 7, height: 7)
                    Text("Tu ubicación")
                        .font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                }
                HStack(spacing: 5) {
                    Image(systemName: vm.selectedDestination?.icon ?? "mappin")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(teal)
                    Text(vm.selectedDestination?.name ?? "")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }

            Spacer()

            // Score badge
            if let eval = vm.activeEvaluation {
                VStack(spacing: 1) {
                    Text("\(eval.accessibilityScore)")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundColor(eval.accessibilityColor.color)
                        .contentTransition(.numericText())           // ← animación numérica al reevaluar
                        .animation(.spring(response: 0.4), value: eval.accessibilityScore)
                    Text("score")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .frame(width: 50, height: 50)
                .background(eval.accessibilityColor.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(eval.accessibilityColor.color.opacity(0.25), lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 58)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }

    // MARK: Mode picker

    var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(RouteMode.allCases) { mode in
                let isSelected = vm.selectedMode == mode
                Button { vm.switchMode(to: mode) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(mode.rawValue)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .regular, design: .rounded))
                    }
                    .foregroundColor(isSelected ? .black : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isSelected ? teal : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .animation(.spring(response: 0.3), value: vm.selectedMode)
    }

    // MARK: Summary card

    func summaryCard(eval: RouteEvaluation) -> some View {
        VStack(spacing: 0) {
            // 3 métricas
            HStack(spacing: 0) {
                MetricCell(value: eval.distanceText,          label: "Distancia",    icon: "ruler",       color: teal)
                Divider().frame(height: 44)
                MetricCell(value: eval.timeText,              label: "Tiempo est.",  icon: "clock",       color: teal)
                Divider().frame(height: 44)
                MetricCell(value: "\(eval.accessibilityScore)", label: eval.accessibilityLabel,
                           icon: "figure.roll", color: eval.accessibilityColor.color)
            }
            .padding(.vertical, 16)
            .animation(.spring(response: 0.4), value: eval.accessibilityScore)

            Divider().padding(.horizontal, 16)

            // Explicaciones
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(teal)
                    Text("Por qué esta ruta")
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(.secondary)
                }
                .padding(.top, 14)

                ForEach(eval.explanations, id: \.self) { exp in
                    ExplanationRow(text: exp, color: eval.accessibilityColor.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.bottom, 16)

            // Comparativa
            if let alt = vm.alternativeEvaluation,
               alt.accessibilityScore != eval.accessibilityScore {
                Divider().padding(.horizontal, 16)
                HStack(spacing: 8) {
                    Image(systemName: vm.selectedMode == .accessible ? "bolt.fill" : "figure.roll")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                    Text("Alternativa: score \(alt.accessibilityScore) · \(alt.distanceText) · \(alt.timeText)")
                        .font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                    Spacer()
                    Button {
                        vm.switchMode(to: vm.selectedMode == .accessible ? .fastest : .accessible)
                    } label: {
                        Text("Ver").font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(teal)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.1), lineWidth: 0.5))
    }

    // MARK: CTA button

    var ctaButton: some View {
        Button { vm.startRoute() } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.walk").font(.system(size: 16, weight: .bold))
                Text("Usar esta ruta").font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(teal, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: teal.opacity(0.4), radius: 10, x: 0, y: 4)
        }
    }

    // MARK: Misc

    var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView().tint(teal).scaleEffect(1.2)
            Text("Calculando ruta accesible...")
                .font(.system(size: 14, weight: .medium, design: .rounded)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    // PASO 2: Banner que aparece cuando un nuevo scan afecta el score de la ruta
    var routeUpdatedBanner: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(teal.opacity(0.2)).frame(width: 30, height: 30)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(teal)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Ruta actualizada")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("Nuevo scan afecta el trayecto")
                    .font(.system(size: 11, design: .rounded)).foregroundColor(.secondary)
            }
            Spacer()
            if let eval = vm.activeEvaluation {
                Text("\(eval.accessibilityScore)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(eval.accessibilityColor.color)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

// MARK: - PASO 3: Active Route View
//
// Pantalla que se muestra después de tap en "Usar esta ruta".
// Diseño Apple-level: mapa arriba, panel de glass abajo con estado completo.
// Muestra: destino, tiempo restante, score, zonas evitadas, botón parar.

struct ActiveRouteView: View {
    @ObservedObject var vm: RouteViewModel
    @ObservedObject private var store = HeatmapStore.shared
    let teal: Color

    @State private var elapsedSeconds = 0
    @State private var timer: Timer? = nil
    @State private var pulseScale: CGFloat = 1.0

    var eval: RouteEvaluation? { vm.activeEvaluation }

    var remainingTime: String {
        guard let eval else { return "--" }
        let total = Int(eval.route.expectedTravelTime)
        let remaining = max(0, total - elapsedSeconds)
        let m = remaining / 60
        let s = remaining % 60
        if m > 0 { return "\(m) min" }
        return "\(s) s"
    }

    var progressFraction: Double {
        guard let eval else { return 0 }
        let total = eval.route.expectedTravelTime
        return min(1.0, Double(elapsedSeconds) / total)
    }

    var notAccessibleCount: Int {
        eval?.tilesNearby.filter { $0.tile.accessibilityLevel == .notAccessible }.count ?? 0
    }

    var limitedCount: Int {
        eval?.tilesNearby.filter { $0.tile.accessibilityLevel == .limited }.count ?? 0
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Mapa de fondo
            if let active = eval {
                RouteMapView(
                    region: vm.mapRegion,
                    activeEvaluation: active,
                    alternativeEvaluation: nil,
                    heatmapTiles: store.allTiles
                )
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // Glass panel inferior
            VStack(spacing: 0) {
                // Handle
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10).padding(.bottom, 18)

                // Destino + modo
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(teal.opacity(0.15)).frame(width: 44, height: 44)
                        Image(systemName: vm.selectedDestination?.icon ?? "mappin")
                            .font(.system(size: 18, weight: .semibold)).foregroundColor(teal)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vm.selectedDestination?.name ?? "Destino")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("Ruta \(vm.selectedMode.rawValue.lowercased())")
                            .font(.system(size: 13, design: .rounded)).foregroundColor(.secondary)
                    }
                    Spacer()
                    // Indicador de navegación activa
                    HStack(spacing: 5) {
                        Circle().fill(teal)
                            .frame(width: 8, height: 8)
                            .scaleEffect(pulseScale)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                       value: pulseScale)
                        Text("En ruta")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(teal)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(teal.opacity(0.12), in: Capsule())
                }
                .padding(.horizontal, 20)

                // Barra de progreso
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.12))
                        Capsule().fill(teal)
                            .frame(width: geo.size.width * progressFraction)
                            .animation(.linear(duration: 1), value: progressFraction)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 20).padding(.vertical, 16)

                // Métricas en tiempo real
                HStack(spacing: 0) {
                    ActiveMetric(
                        value: remainingTime,
                        label: "Tiempo rest.",
                        icon: "clock.fill",
                        color: teal
                    )
                    Divider().frame(height: 40)
                    ActiveMetric(
                        value: eval?.distanceText ?? "--",
                        label: "Distancia",
                        icon: "ruler.fill",
                        color: teal
                    )
                    Divider().frame(height: 40)
                    ActiveMetric(
                        value: eval.map { "\($0.accessibilityScore)" } ?? "--",
                        label: eval?.accessibilityLabel ?? "Score",
                        icon: "figure.roll",
                        color: eval?.accessibilityColor.color ?? teal
                    )
                }
                .padding(.horizontal, 16)

                Divider().padding(.horizontal, 20).padding(.top, 16)

                // Zonas evitadas / info de accesibilidad
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 16)).foregroundColor(teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(avoidanceText)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        if let firstExp = eval?.explanations.first {
                            Text(firstExp)
                                .font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 14)

                // PASO 2 en ruta activa: si cambia el score, mostrar aviso
                if vm.routeJustUpdated {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13)).foregroundColor(.orange)
                        Text("Nuevo scan cerca — ruta reevaluada")
                            .font(.system(size: 12, design: .rounded)).foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Botón parar ruta
                Button {
                    timer?.invalidate()
                    vm.stopRoute()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "stop.circle.fill").font(.system(size: 16, weight: .bold))
                        Text("Parar ruta").font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 1, green: 0.28, blue: 0.28), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20).padding(.top, 18)
                .accessibilityLabel("Parar la ruta activa")

                Spacer(minLength: 36)
            }
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.14), radius: 24, x: 0, y: -6)
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            pulseScale = 1.3
            startTimer()
        }
        .onDisappear { timer?.invalidate() }
        // PASO 2: reevaluar métricas cuando cambia el score durante navegación
        .onChange(of: vm.routeJustUpdated) { _, _ in }
    }

    private var avoidanceText: String {
        if notAccessibleCount == 0 && limitedCount == 0 {
            return "Sin obstáculos en el trayecto"
        }
        var parts: [String] = []
        if notAccessibleCount > 0 { parts.append("\(notAccessibleCount) zona\(notAccessibleCount > 1 ? "s" : "") evitada\(notAccessibleCount > 1 ? "s" : "")") }
        if limitedCount > 0       { parts.append("\(limitedCount) tramo\(limitedCount > 1 ? "s" : "") limitado\(limitedCount > 1 ? "s" : "")") }
        return parts.joined(separator: " · ")
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard let eval else { return }
            if elapsedSeconds < Int(eval.route.expectedTravelTime) {
                elapsedSeconds += 1
            }
        }
    }
}

struct ActiveMetric: View {
    let value: String; let label: String; let icon: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundColor(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4), value: value)
            Text(label)
                .font(.system(size: 10, design: .rounded)).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Supporting Views

struct DestinationRow: View {
    let destination: MockDestination
    let teal: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(teal.opacity(0.12)).frame(width: 44, height: 44)
                Image(systemName: destination.icon)
                    .font(.system(size: 18, weight: .medium)).foregroundColor(teal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(destination.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(destination.subtitle)
                    .font(.system(size: 13, design: .rounded)).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.1), lineWidth: 0.5))
    }
}

struct MetricCell: View {
    let value: String; let label: String; let icon: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium)).foregroundColor(color)
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 11, design: .rounded)).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ExplanationRow: View {
    let text: String; let color: Color
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color.opacity(0.7)).frame(width: 6, height: 6).padding(.top, 5)
            Text(text).font(.system(size: 14, design: .rounded)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview { NavigationStack { RouteView() } }
