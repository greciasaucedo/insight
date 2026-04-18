//
//  RouteView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 17/04/26.
//


import SwiftUI
import MapKit

// MARK: - Route Map Overlay
// Renderiza polylines y heatmap sobre un Map de SwiftUI.
// Se usa UIViewRepresentable porque SwiftUI Map no expone overlays en iOS 16.

struct RouteMapView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let activeEvaluation: RouteEvaluation?
    let alternativeEvaluation: RouteEvaluation?
    let heatmapTiles: [AccessibilityTile]

    let primaryColor = UIColor(red: 136/255, green: 205/255, blue: 212/255, alpha: 1)

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

        // Actualizar región si cambió
        if !regionsEqual(map.region, region) {
            map.setRegion(region, animated: true)
        }

        // Heatmap circles
        for tile in heatmapTiles where tile.accessibilityLevel != .noData {
            let circle = MKCircle(center: tile.coordinate, radius: 55)
            circle.title = tileOverlayTitle(tile)
            map.addOverlay(circle, level: .aboveRoads)
        }

        // Ruta alternativa (gris, debajo)
        if let alt = alternativeEvaluation {
            let overlay = RouteOverlay(polyline: alt.route.polyline, isActive: false)
            map.addOverlay(overlay, level: .aboveRoads)
        }

        // Ruta activa (color primario, encima)
        if let active = activeEvaluation {
            let overlay = RouteOverlay(polyline: active.route.polyline, isActive: true)
            map.addOverlay(overlay, level: .aboveRoads)

            // Pin de destino
            if let lastCoord = RouteEngine.extractPoints(from: active.route.polyline).last {
                let annotation = MKPointAnnotation()
                annotation.coordinate = lastCoord
                annotation.title = "Destino"
                map.addAnnotation(annotation)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(primaryColor: primaryColor) }

    private func tileOverlayTitle(_ tile: AccessibilityTile) -> String {
        switch tile.accessibilityLevel {
        case .accessible:    return "accessible"
        case .limited:       return "limited"
        case .notAccessible: return "notAccessible"
        case .noData:        return "noData"
        }
    }

    private func regionsEqual(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion) -> Bool {
        abs(a.center.latitude  - b.center.latitude)  < 0.0001 &&
        abs(a.center.longitude - b.center.longitude) < 0.0001
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        let primaryColor: UIColor

        init(primaryColor: UIColor) { self.primaryColor = primaryColor }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {

            // Heatmap circles
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.lineWidth = 0
                switch circle.title {
                case "accessible":
                    renderer.fillColor = UIColor(red: 136/255, green: 205/255, blue: 212/255, alpha: 0.35)
                case "limited":
                    renderer.fillColor = UIColor(red: 255/255, green: 214/255, blue: 102/255, alpha: 0.35)
                case "notAccessible":
                    renderer.fillColor = UIColor(red: 160/255, green: 160/255, blue: 165/255, alpha: 0.40)
                default:
                    renderer.fillColor = .clear
                }
                return renderer
            }

            // Route polylines
            if let routeOverlay = overlay as? RouteOverlay {
                let renderer = MKPolylineRenderer(polyline: routeOverlay)
                if routeOverlay.isActive {
                    renderer.strokeColor = primaryColor
                    renderer.lineWidth   = 5
                    renderer.lineCap     = .round
                    renderer.lineJoin    = .round
                } else {
                    renderer.strokeColor = UIColor.systemGray3.withAlphaComponent(0.7)
                    renderer.lineWidth   = 3
                    renderer.lineCap     = .round
                    renderer.lineDashPattern = [8, 6]
                }
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "dest")
            view.markerTintColor = primaryColor
            view.glyphImage = UIImage(systemName: "mappin.circle.fill")
            return view
        }
    }
}

// RouteOverlay: wrapper para diferenciar activa de alternativa
final class RouteOverlay: MKPolyline {
    var isActive: Bool = false

    convenience init(polyline: MKPolyline, isActive: Bool) {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        self.init(coordinates: &coords, count: coords.count)
        self.isActive = isActive
    }
}

// MARK: - Main Route View

struct RouteView: View {
    @StateObject private var vm = RouteViewModel()
    @ObservedObject private var heatmapStore = HeatmapStore.shared
    @Environment(\.dismiss) private var dismiss

    let primaryColor = Color(red: 136/255, green: 205/255, blue: 212/255)

    var body: some View {
        ZStack(alignment: .top) {
            Color(UIColor.systemBackground).ignoresSafeArea()

            if vm.selectedDestination == nil {
                // Pantalla de selección de destino
                destinationPicker
            } else {
                // Pantalla de ruta con mapa
                routeScreen
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Destination Picker

    var destinationPicker: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 40, height: 40)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Volver al mapa")

                Spacer()

                Text("Ruta accesible")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))

                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 24)

            // Tarjeta origen
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("¿A dónde quieres ir?")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                } icon: {
                    Image(systemName: "location.fill")
                        .foregroundColor(primaryColor)
                        .font(.system(size: 14))
                }

                HStack(spacing: 10) {
                    Circle()
                        .fill(primaryColor.opacity(0.2))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(primaryColor, lineWidth: 1.5))

                    Text("Tu ubicación")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 2)

                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 1.5, height: 16)
                    .padding(.leading, 4)
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)

            // Destinos
            VStack(alignment: .leading, spacing: 8) {
                Text("Destinos disponibles")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 28)

                ForEach(MockDestination.all) { dest in
                    Button { vm.select(destination: dest) } label: {
                        DestinationCard(destination: dest, primaryColor: primaryColor)
                    }
                    .padding(.horizontal, 20)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ir a \(dest.name), \(dest.subtitle)")
                }
            }

            Spacer()
        }
    }

    // MARK: - Route Screen

    var routeScreen: some View {
        VStack(spacing: 0) {
            // Header con origen/destino
            routeHeader
                .background(.regularMaterial)
                .zIndex(2)

            // Mapa — ocupa la mitad superior
            ZStack {
                if let activeEval = vm.activeEvaluation {
                    RouteMapView(
                        region: vm.mapRegion,
                        activeEvaluation: activeEval,
                        alternativeEvaluation: vm.alternativeEvaluation,
                        heatmapTiles: allTiles
                    )
                } else {
                    // Skeleton mientras carga
                    Rectangle()
                        .fill(Color.secondary.opacity(0.08))
                        .overlay(
                            ProgressView().tint(primaryColor)
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: UIScreen.main.bounds.height * 0.38)

            // Panel inferior con resumen y CTA
            ScrollView {
                VStack(spacing: 16) {
                    // Selector de modo
                    modePicker
                        .padding(.top, 20)

                    // Tarjeta resumen
                    if vm.isLoading {
                        loadingCard
                    } else if let eval = vm.activeEvaluation {
                        summaryCard(eval: eval)
                    }

                    // Botón CTA
                    if vm.activeEvaluation != nil {
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

    // MARK: - Route Header

    var routeHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.35)) { vm.reset() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 38, height: 38)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Cambiar destino")

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(primaryColor.opacity(0.25))
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(primaryColor, lineWidth: 1.2))
                        Text("Tu ubicación")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: vm.selectedDestination?.icon ?? "mappin")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(primaryColor)
                        Text(vm.selectedDestination?.name ?? "")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                }

                Spacer()

                // Mini score badge
                if let eval = vm.activeEvaluation {
                    VStack(spacing: 1) {
                        Text("\(eval.accessibilityScore)")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(eval.accessibilityColor.color)
                        Text("score")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 52, height: 52)
                    .background(eval.accessibilityColor.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(eval.accessibilityColor.color.opacity(0.25), lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Mode Picker

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
                    .background(
                        isSelected
                            ? primaryColor
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.rawValue)\(isSelected ? ", seleccionado" : "")")
            }
        }
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
        .animation(.spring(response: 0.3), value: vm.selectedMode)
    }

    // MARK: - Summary Card

    func summaryCard(eval: RouteEvaluation) -> some View {
        VStack(spacing: 0) {
            // Métricas top
            HStack(spacing: 0) {
                MetricCell(
                    value: eval.distanceText,
                    label: "Distancia",
                    icon: "ruler",
                    color: primaryColor
                )
                Divider().frame(height: 44)
                MetricCell(
                    value: eval.timeText,
                    label: "Tiempo est.",
                    icon: "clock",
                    color: primaryColor
                )
                Divider().frame(height: 44)
                MetricCell(
                    value: "\(eval.accessibilityScore)",
                    label: eval.accessibilityLabel,
                    icon: "figure.roll",
                    color: eval.accessibilityColor.color
                )
            }
            .padding(.vertical, 16)

            Divider().padding(.horizontal, 16)

            // Explicación — por qué se eligió esta ruta
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(primaryColor)
                    Text("Por qué esta ruta")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 14)

                ForEach(eval.explanations, id: \.self) { explanation in
                    ExplanationRow(text: explanation, color: eval.accessibilityColor.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // Comparativa con la otra ruta (si existe y es diferente)
            if let alt = vm.alternativeEvaluation,
               alt.accessibilityScore != eval.accessibilityScore {
                Divider().padding(.horizontal, 16)

                HStack(spacing: 8) {
                    Image(systemName: vm.selectedMode == .accessible ? "bolt.fill" : "figure.roll")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Text("Ruta alternativa: score \(alt.accessibilityScore) · \(alt.distanceText) · \(alt.timeText)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        vm.switchMode(to: vm.selectedMode == .accessible ? .fastest : .accessible)
                    } label: {
                        Text("Ver")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(primaryColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Ruta \(vm.selectedMode.rawValue.lowercased()). " +
            "\(eval.distanceText), \(eval.timeText). " +
            "\(eval.accessibilityLabel), score \(eval.accessibilityScore). " +
            "Explicación: \(eval.explanations.joined(separator: ". "))"
        )
    }

    // MARK: - Loading Card

    var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView().tint(primaryColor).scaleEffect(1.2)
            Text("Calculando ruta accesible...")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - CTA Button

    var ctaButton: some View {
        Button {
            // Para hackathon: dismiss y mostrar confirmación
            // En producción: iniciaría navegación turn-by-turn
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 16, weight: .bold))
                Text("Usar esta ruta")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(primaryColor, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: primaryColor.opacity(0.4), radius: 10, x: 0, y: 4)
        }
        .accessibilityLabel("Iniciar ruta \(vm.selectedMode.rawValue.lowercased())")
    }

    // MARK: - Helpers

    var allTiles: [AccessibilityTile] {
        heatmapStore.scannedTiles
    }
}

// MARK: - Supporting Views

struct DestinationCard: View {
    let destination: MockDestination
    let primaryColor: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(primaryColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: destination.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(primaryColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(destination.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(destination.subtitle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
    }
}

struct MetricCell: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ExplanationRow: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color.opacity(0.7))
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            Text(text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        RouteView()
    }
}
