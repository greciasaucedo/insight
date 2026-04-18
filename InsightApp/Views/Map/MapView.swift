//
//  MapView.swift
//  InsightApp
//




import SwiftUI
import MapKit
import CoreHaptics
import CoreLocation
import Combine

// MARK: - Models

struct AccessibilityTile: Identifiable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D
    var accessibilityScore: Int
    var confidenceScore: Double
    var reasons: [String]
    var isUserScanned: Bool = false

    var accessibilityLevel: AccessibilityLevel {
        switch accessibilityScore {
        case 70...100: return .accessible
        case 40...69:  return .limited
        case 0...39:   return .notAccessible
        default:       return .noData
        }
    }

    var confidenceLabel: String {
        switch confidenceScore {
        case 0.66...1.0:  return "Alto"
        case 0.33...0.65: return "Medio"
        default:          return "Bajo"
        }
    }
}

enum AccessibilityLevel {
    case accessible, limited, notAccessible, noData

    var color: Color {
        switch self {
        case .accessible:    return Color(red: 136/255, green: 205/255, blue: 212/255)
        case .limited:       return Color(red: 255/255, green: 214/255, blue: 102/255)
        case .notAccessible: return Color(red: 160/255, green: 160/255, blue: 165/255)
        case .noData:        return Color.clear
        }
    }

    var label: String {
        switch self {
        case .accessible:    return "Accesible"
        case .limited:       return "Limitado"
        case .notAccessible: return "No accesible"
        case .noData:        return "Sin datos"
        }
    }

    var voiceOverLabel: String {
        switch self {
        case .accessible:    return "Zona accesible"
        case .limited:       return "Zona con accesibilidad limitada"
        case .notAccessible: return "Zona no accesible"
        case .noData:        return "Zona sin datos"
        }
    }
}

// MARK: - HeatmapStore  ← Fuente única de verdad (Paso 1)
//
// Antes: MapViewModel tenía sus propios mock tiles,
//        RouteViewModel evaluaba solo HeatmapStore.scannedTiles.
//        Resultado: el mapa mostraba zonas que la ruta ignoraba.
//
// Ahora: HeatmapStore tiene:
//   • baseTiles   — datos mock del campus (cargados al init)
//   • scannedTiles — scans del usuario (agregados por ScanView)
//   • allTiles     — unión; MapView y RouteViewModel leen exclusivamente de aquí
//
// Un solo cambio en baseTiles o scannedTiles se propaga automáticamente
// a cualquier vista que observe `allTiles` vía @Published.

class HeatmapStore: ObservableObject {
    static let shared = HeatmapStore()

    @Published private(set) var baseTiles: [AccessibilityTile] = []
    @Published private(set) var scannedTiles: [AccessibilityTile] = []

    /// Única propiedad que deben leer MapView y RouteViewModel.
    var allTiles: [AccessibilityTile] { baseTiles + scannedTiles }

    init() {
        loadBaseTiles()
        let saved = PersistenceService.shared.loadScannedTiles()
        if !saved.isEmpty { scannedTiles = saved }
        // Remote tiles are loaded by MapView's .task modifier
    }

    @MainActor
    func loadRemoteTiles(near coordinate: CLLocationCoordinate2D) async {
        do {
            let remote = try await TileAPIService.shared.fetchNearbyTiles(
                lat: coordinate.latitude, lng: coordinate.longitude
            )
            guard !remote.isEmpty else { return }
            let existing = allTiles
            // Dedup: skip any remote tile within ~5 m of an existing tile
            let newTiles = remote
                .map { $0.toAccessibilityTile() }
                .filter { remoteTile in
                    !existing.contains { local in
                        let dLat = abs(local.coordinate.latitude  - remoteTile.coordinate.latitude)
                        let dLng = abs(local.coordinate.longitude - remoteTile.coordinate.longitude)
                        return dLat < 0.000045 && dLng < 0.000045
                    }
                }
            if !newTiles.isEmpty {
                baseTiles.append(contentsOf: newTiles)
            }
        } catch {
            // Non-fatal; tile fetch failure never blocks UX
        }
    }

    private func loadBaseTiles() {
        let origin = CLLocationCoordinate2D(latitude: 25.6714, longitude: -100.3098)
        let configs: [(Double, Double, Int, Double, [String])] = [
            ( 0.000,  0.000, 85, 0.90, []),
            ( 0.001,  0.001, 78, 0.80, []),
            ( 0.002, -0.001, 55, 0.60, ["Inclinación detectada"]),
            ( 0.001, -0.002, 45, 0.50, ["Desvíos frecuentes"]),
            (-0.001,  0.002, 30, 0.70, ["Vibración elevada", "Desvíos frecuentes"]),
            (-0.002, -0.001, 20, 0.40, ["Vibración elevada", "Inclinación detectada"]),
            ( 0.003,  0.002, 90, 0.95, []),
            (-0.001, -0.003, 60, 0.65, ["Inclinación detectada"]),
            ( 0.002,  0.003, 35, 0.30, ["Vibración elevada"]),
            (-0.003,  0.001, 72, 0.80, []),
            ( 0.000, -0.003, 10, 0.90, ["Vibración elevada", "Desvíos frecuentes", "Inclinación detectada"]),
            ( 0.004, -0.001, 80, 0.85, []),
        ]
        baseTiles = configs.map { dlat, dlon, score, conf, reasons in
            AccessibilityTile(
                coordinate: CLLocationCoordinate2D(
                    latitude: origin.latitude + dlat,
                    longitude: origin.longitude + dlon
                ),
                accessibilityScore: score,
                confidenceScore: conf,
                reasons: reasons,
                isUserScanned: false
            )
        }
    }

    func addTile(coordinate: CLLocationCoordinate2D, score: Int, confidence: Double, reasons: [String]) {
        scannedTiles.append(AccessibilityTile(
            coordinate: coordinate,
            accessibilityScore: score,
            confidenceScore: confidence,
            reasons: reasons,
            isUserScanned: true
        ))
        // Persistencia (Item 12): guardar inmediatamente al disco
        PersistenceService.shared.saveScannedTiles(scannedTiles)
    }
}

// MARK: - Map ViewModel

@MainActor
class MapViewModel: ObservableObject {
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.6714, longitude: -100.3098),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @Published var selectedTile: AccessibilityTile? = nil
    @Published var showLegend = false
    @Published var isLoading = true
    @Published var errorMessage: String? = nil
    @Published var userFeedback: [UUID: Bool] = [:]
    @Published var newTileFlash: UUID? = nil
    @Published var animateTiles = false

    private var hapticEngine: CHHapticEngine?
    private var lastHapticLevel: AccessibilityLevel? = nil
    private var knownScannedIDs: Set<UUID> = []

    init() {
        setupHaptics()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeIn(duration: 0.5)) { self.animateTiles = true }
            self.isLoading = false
        }
    }

    var hasData: Bool { !HeatmapStore.shared.allTiles.isEmpty }

    // Detecta tiles nuevos del usuario y activa el pulso visual
    func processNewScans(_ scannedTiles: [AccessibilityTile]) {
        for tile in scannedTiles where !knownScannedIDs.contains(tile.id) {
            knownScannedIDs.insert(tile.id)
            newTileFlash = tile.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.newTileFlash == tile.id { self.newTileFlash = nil }
            }
        }
    }

    func centerOnUser() {
        withAnimation(.easeInOut(duration: 0.5)) {
            region.center = CLLocationCoordinate2D(latitude: 25.6714, longitude: -100.3098)
        }
    }

    func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do { hapticEngine = try CHHapticEngine(); try hapticEngine?.start() } catch {}
    }

    func triggerHaptic(for level: AccessibilityLevel) {
        guard level != lastHapticLevel else { return }
        lastHapticLevel = level
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        do {
            var events: [CHHapticEvent] = []
            switch level {
            case .limited:
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ], relativeTime: 0))
            case .notAccessible:
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ], relativeTime: 0, duration: 0.3))
            default: break
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: 0)
        } catch {}
    }
}

// MARK: - Main Map View

struct MapView: View {
    @StateObject private var vm = MapViewModel()
    @ObservedObject private var store = HeatmapStore.shared
    @State private var showScan    = false
    @State private var showRoute   = false
    @State private var showProfile = false
    @State private var showBottomSheet = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    let teal = Color(red: 136/255, green: 205/255, blue: 212/255)

    var body: some View {
        ZStack(alignment: .top) {
            Map(coordinateRegion: $vm.region, showsUserLocation: true)
                .ignoresSafeArea()

            // Layer A — visual only, no gestures
            GeometryReader { geo in
                ForEach(store.allTiles) { tile in
                    HeatmapTileView(
                        tile: tile,
                        mapRegion: vm.region,
                        geoSize: geo.size,
                        animated: vm.animateTiles,
                        isPulsing: vm.newTileFlash == tile.id
                    )
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()

            // Layer B — transparent tap targets, restricted to circle area
            GeometryReader { geo in
                ForEach(store.allTiles.filter { $0.accessibilityLevel != .noData }) { tile in
                    Color.clear
                        .frame(width: 100, height: 100)
                        .contentShape(Circle())
                        .position(tilePosition(tile, size: geo.size))
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                vm.selectedTile = tile
                                showBottomSheet = true
                            }
                            vm.triggerHaptic(for: tile.accessibilityLevel)
                        }
                        .accessibilityElement()
                        .accessibilityLabel(
                            "\(tile.accessibilityLevel.voiceOverLabel), confianza \(tile.confidenceLabel)" +
                            (tile.isUserScanned ? ", escaneado por ti" : "")
                        )
                        .accessibilityAddTraits(.isButton)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) { searchBar; Spacer() }

            VStack {
                Spacer()
                HStack { Spacer(); floatingButtonsColumn }
            }
            .padding(.trailing, 16)
            .padding(.bottom, showBottomSheet ? 340 : 100)
            .animation(.spring(response: 0.4), value: showBottomSheet)

            if vm.showLegend {
                VStack {
                    Spacer()
                    HStack { legendPanel.padding(.leading, 16); Spacer() }
                }
                .padding(.bottom, showBottomSheet ? 360 : 110)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: vm.showLegend)
            }

            if !vm.hasData && !vm.isLoading { emptyStateHint }
            if vm.isLoading { loadingIndicator }
            if let error = vm.errorMessage { errorBanner(message: error) }

            if showBottomSheet, let tile = vm.selectedTile {
                Color.black.opacity(0.001).ignoresSafeArea()
                    .onTapGesture { showBottomSheet = false }
                VStack {
                    Spacer()
                    BottomSheetView(
                        tile: tile, isShowing: $showBottomSheet,
                        userFeedback: $vm.userFeedback, primaryColor: teal
                    )
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showBottomSheet)
            }
        }
        .task { await store.loadRemoteTiles(near: vm.region.center) }
        .onChange(of: store.scannedTiles.count) { _, _ in
            Task { @MainActor in vm.processNewScans(store.scannedTiles) }
        }
        .fullScreenCover(isPresented: $showScan)    { ScanView() }
        .fullScreenCover(isPresented: $showRoute)   { NavigationStack { RouteView() } }
        .fullScreenCover(isPresented: $showProfile) { ProfileView() }
    }

    // MARK: Search bar

    var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary).font(.system(size: 15, weight: .medium))
                TextField("¿A dónde quieres ir?", text: $searchText)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .focused($searchFocused).submitLabel(.search)
                    .onSubmit { if !searchText.isEmpty { showRoute = true } }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)

            Button { showProfile = true } label: {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(teal)
                    .background(Circle().fill(.regularMaterial))
                    .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
            }
        }
        .padding(.horizontal, 16).padding(.top, 56).padding(.bottom, 8)
    }

    // MARK: Floating buttons

    var floatingButtonsColumn: some View {
        VStack(spacing: 12) {
            Button { showRoute = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "figure.roll").font(.system(size: 16, weight: .semibold))
                    Text("Crear ruta").font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(teal, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: teal.opacity(0.5), radius: 8, x: 0, y: 4)
            }
            .accessibilityLabel("Crear ruta accesible")

            Button { showScan = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 16, weight: .semibold))
                    Text("Scan Area").font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(teal.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            }
            .accessibilityLabel("Escanear área")

            FloatingIconButton(icon: "location.fill", color: teal) { vm.centerOnUser() }
            FloatingIconButton(icon: "square.3.layers.3d", color: vm.showLegend ? teal : .secondary) {
                withAnimation { vm.showLegend.toggle() }
            }
        }
    }

    // MARK: Legend

    var legendPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accesibilidad")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            ForEach([AccessibilityLevel.accessible, .limited, .notAccessible], id: \.label) { level in
                HStack(spacing: 8) {
                    Circle().fill(level.color).frame(width: 12, height: 12)
                    Text(level.label).font(.system(size: 13, design: .rounded))
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
    }

    // MARK: State helpers

    var emptyStateHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "map").font(.system(size: 22)).foregroundColor(teal)
            Text("Muévete o escanea para generar datos")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    var loadingIndicator: some View {
        VStack {
            Spacer()
            HStack {
                ProgressView().tint(teal).scaleEffect(0.8)
                Text("Cargando datos...").font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 110)
        }
    }

    private func tilePosition(_ tile: AccessibilityTile, size: CGSize) -> CGPoint {
        let latDelta = tile.coordinate.latitude  - vm.region.center.latitude
        let lonDelta = tile.coordinate.longitude - vm.region.center.longitude
        let x = size.width  / 2 + CGFloat(lonDelta / vm.region.span.longitudeDelta) * size.width
        let y = size.height / 2 - CGFloat(latDelta / vm.region.span.latitudeDelta)  * size.height
        return CGPoint(x: x, y: y)
    }

    func errorBanner(message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(message).font(.system(size: 13, weight: .medium, design: .rounded))
                Spacer()
                Button { vm.errorMessage = nil } label: {
                    Image(systemName: "xmark").foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16).padding(.top, 120)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - HeatmapTileView

struct HeatmapTileView: View {
    let tile: AccessibilityTile
    let mapRegion: MKCoordinateRegion
    let geoSize: CGSize
    let animated: Bool
    let isPulsing: Bool

    @State private var pulseOpacity: Double = 0.6
    @State private var pulseScale: CGFloat = 0.8

    var position: CGPoint {
        let latDelta = tile.coordinate.latitude - mapRegion.center.latitude
        let lonDelta = tile.coordinate.longitude - mapRegion.center.longitude
        let x = geoSize.width  / 2 + CGFloat(lonDelta / mapRegion.span.longitudeDelta) * geoSize.width
        let y = geoSize.height / 2 - CGFloat(latDelta / mapRegion.span.latitudeDelta)  * geoSize.height
        return CGPoint(x: x, y: y)
    }

    let tileRadius: CGFloat = 72
    var tileColor: Color { tile.accessibilityLevel.color }

    var body: some View {
        if tile.accessibilityLevel != .noData {
            ZStack {
                if isPulsing {
                    Circle()
                        .fill(tileColor.opacity(pulseOpacity))
                        .frame(width: tileRadius * 2.6, height: tileRadius * 2.6)
                        .scaleEffect(pulseScale).position(position)
                        .onAppear {
                            withAnimation(.easeOut(duration: 1.0)) {
                                pulseScale = 1.5; pulseOpacity = 0.0
                            }
                        }
                }
                Ellipse()
                    .fill(RadialGradient(
                        gradient: Gradient(colors: [
                            tileColor.opacity(animated ? 0.42 : 0),
                            tileColor.opacity(animated ? 0.18 : 0),
                            tileColor.opacity(0)
                        ]),
                        center: .center, startRadius: 0, endRadius: tileRadius
                    ))
                    .frame(width: tileRadius * 2, height: tileRadius * 1.5)
                    .position(position)
                    .animation(.easeInOut(duration: 0.28), value: animated)

                if tile.isUserScanned {
                    Circle()
                        .fill(tileColor).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .shadow(color: tileColor.opacity(0.6), radius: 4, x: 0, y: 2)
                        .position(position)
                        .scaleEffect(animated ? 1.0 : 0.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1), value: animated)
                }
            }
            .allowsHitTesting(true)
            .onChange(of: isPulsing) { _, newVal in
                if newVal { pulseScale = 0.8; pulseOpacity = 0.6 }
            }
        }
    }
}

// MARK: - FloatingIconButton

struct FloatingIconButton: View {
    let icon: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .medium))
                .foregroundColor(color).frame(width: 44, height: 44)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
        }
    }
}

// MARK: - BottomSheetView

struct BottomSheetView: View {
    let tile: AccessibilityTile
    @Binding var isShowing: Bool
    @Binding var userFeedback: [UUID: Bool]
    let primaryColor: Color

    var statusIcon: String {
        switch tile.accessibilityLevel {
        case .accessible:    return "checkmark.circle.fill"
        case .limited:       return "exclamationmark.triangle.fill"
        case .notAccessible: return "xmark.circle.fill"
        case .noData:        return "questionmark.circle.fill"
        }
    }
    var statusColor: Color { tile.accessibilityLevel.color }

    func typeIcon(from reasons: [String]) -> String {
        guard let first = reasons.first?.lowercased() else { return "camera.fill" }
        if first.contains("rampa")    { return "road.lanes" }
        if first.contains("escalera") { return "figure.stairs" }
        if first.contains("obstáculo"){ return "exclamationmark.triangle.fill" }
        if first.contains("plana")    { return "checkmark.seal.fill" }
        return "camera.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.35))
                    .frame(width: 38, height: 5)
                Spacer()
            }
            .padding(.top, 10).padding(.bottom, 18)

            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.system(size: 28, weight: .semibold)).foregroundColor(statusColor)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(tile.accessibilityLevel.label)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        if tile.isUserScanned {
                            let isSimulated = tile.reasons.first?.contains("(simulado)") ?? false
                            // Badge "Escaneado" (cámara real) o "Demo" (clasificación simulada)
                            Label(isSimulated ? "Demo" : "Escaneado",
                                  systemImage: isSimulated ? "wand.and.stars" : "camera.fill")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(isSimulated ? .orange : primaryColor)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(
                                    (isSimulated ? Color.orange : primaryColor).opacity(0.12),
                                    in: Capsule()
                                )
                        }
                    }
                    Text("Confianza: \(tile.confidenceLabel)")
                        .font(.system(size: 14, design: .rounded)).foregroundColor(.secondary)
                }
                Spacer()
                Text("\(tile.accessibilityScore)").font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(statusColor)
                + Text(" / 100").font(.system(size: 13, design: .rounded)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)

            if tile.isUserScanned, let mainReason = tile.reasons.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Detección por cámara")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary).padding(.top, 20)
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: typeIcon(from: tile.reasons))
                                .font(.system(size: 13)).foregroundColor(statusColor)
                            Text(mainReason)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Score").font(.system(size: 11, design: .rounded)).foregroundColor(.secondary)
                            Text("\(tile.accessibilityScore)")
                                .font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(statusColor)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            if !tile.reasons.isEmpty {
                let shown = tile.isUserScanned ? Array(tile.reasons.dropFirst()) : tile.reasons
                if !shown.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tile.isUserScanned ? "Factores adicionales" : "Factores detectados")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.top, tile.isUserScanned ? 12 : 20)
                        ForEach(shown, id: \.self) { reason in
                            HStack(spacing: 8) {
                                Circle().fill(statusColor.opacity(0.6)).frame(width: 6, height: 6)
                                Text(reason).font(.system(size: 15, design: .rounded))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            Divider().padding(.vertical, 18).padding(.horizontal, 20)

            if let feedback = userFeedback[tile.id] {
                HStack(spacing: 8) {
                    Image(systemName: feedback ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .foregroundColor(primaryColor)
                    Text(feedback ? "¡Gracias por confirmar!" : "Gracias por tu reporte")
                        .font(.system(size: 14, weight: .medium, design: .rounded)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("¿Pasaste bien aquí?")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    HStack(spacing: 12) {
                        FeedbackButton(label: "Sí", icon: "hand.thumbsup", color: primaryColor) {
                            withAnimation { userFeedback[tile.id] = true }
                        }
                        FeedbackButton(label: "No", icon: "hand.thumbsdown", color: Color(red: 1, green: 0.42, blue: 0.42)) {
                            withAnimation { userFeedback[tile.id] = false }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24).fill(.regularMaterial)
            .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: -4))
    }
}

struct FeedbackButton: View {
    let label: String; let icon: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

#Preview { MapView() }
