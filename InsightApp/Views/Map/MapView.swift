//
//  MapView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 17/04/26.
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

// MARK: - Shared Heatmap Store
// FIX 1: Eliminado DispatchQueue.main.async innecesario.
// HeatmapStore es observado desde SwiftUI (@ObservedObject), por lo que
// las mutaciones a @Published ya deben ocurrir en el main thread.
// Agregar un async innecesario causaba un ciclo extra que podía romper
// el .onChange de MapView en demos en vivo.

class HeatmapStore: ObservableObject {
    static let shared = HeatmapStore()
    @Published var scannedTiles: [AccessibilityTile] = []

    func addTile(coordinate: CLLocationCoordinate2D, score: Int, confidence: Double, reasons: [String]) {
        let tile = AccessibilityTile(
            coordinate: coordinate,
            accessibilityScore: score,
            confidenceScore: confidence,
            reasons: reasons,
            isUserScanned: true
        )
        // FIX 1: directo al array, sin DispatchQueue.main.async
        scannedTiles.append(tile)
    }
}

// MARK: - Map ViewModel

@MainActor
class MapViewModel: ObservableObject {
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.6714, longitude: -100.3098),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @Published var tiles: [AccessibilityTile] = []
    @Published var selectedTile: AccessibilityTile? = nil
    @Published var showLegend = false
    @Published var isLoading = false
    @Published var hasData = false
    @Published var errorMessage: String? = nil
    @Published var userFeedback: [UUID: Bool] = [:]
    @Published var newTileFlash: UUID? = nil

    private var hapticEngine: CHHapticEngine?
    private var lastHapticLevel: AccessibilityLevel? = nil
    private var knownScannedIDs: Set<UUID> = []

    init() {
        setupHaptics()
        loadMockData()
    }

    func mergeScan(_ scannedTiles: [AccessibilityTile]) {
        let newTiles = scannedTiles.filter { !knownScannedIDs.contains($0.id) }
        guard !newTiles.isEmpty else { return }
        for tile in newTiles {
            knownScannedIDs.insert(tile.id)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                tiles.append(tile)
            }
            // Activar pulso en el tile recién agregado
            newTileFlash = tile.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.newTileFlash == tile.id {
                    self.newTileFlash = nil
                }
            }
        }
        hasData = true
    }

    func loadMockData() {
        isLoading = true
        let base = CLLocationCoordinate2D(latitude: 25.6714, longitude: -100.3098)

        let configs: [(Double, Double, Int, Double, [String])] = [
            (0.000,  0.000,  85, 0.90, []),
            (0.001,  0.001,  78, 0.80, []),
            (0.002, -0.001,  55, 0.60, ["Inclinación detectada"]),
            (0.001, -0.002,  45, 0.50, ["Desvíos frecuentes"]),
            (-0.001, 0.002,  30, 0.70, ["Vibración elevada", "Desvíos frecuentes"]),
            (-0.002,-0.001,  20, 0.40, ["Vibración elevada", "Inclinación detectada"]),
            (0.003,  0.002,  90, 0.95, []),
            (-0.001,-0.003,  60, 0.65, ["Inclinación detectada"]),
            (0.002,  0.003,  35, 0.30, ["Vibración elevada"]),
            (-0.003, 0.001,  72, 0.80, []),
            (0.000, -0.003,  10, 0.90, ["Vibración elevada", "Desvíos frecuentes", "Inclinación detectada"]),
            (0.004, -0.001,  80, 0.85, []),
        ]

        var mockTiles: [AccessibilityTile] = []
        for (dlat, dlon, score, conf, reasons) in configs {
            mockTiles.append(AccessibilityTile(
                coordinate: CLLocationCoordinate2D(latitude: base.latitude + dlat, longitude: base.longitude + dlon),
                accessibilityScore: score,
                confidenceScore: conf,
                reasons: reasons
            ))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.tiles = mockTiles
            self.hasData = true
            self.isLoading = false
        }
    }

    func centerOnUser() {
        withAnimation(.easeInOut(duration: 0.5)) {
            region.center = CLLocationCoordinate2D(latitude: 25.6714, longitude: -100.3098)
        }
    }

    func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch {}
    }

    func triggerHaptic(for level: AccessibilityLevel) {
        guard level != lastHapticLevel else { return }
        lastHapticLevel = level
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = hapticEngine else { return }
        do {
            var events: [CHHapticEvent] = []
            switch level {
            case .limited:
                let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5)
                let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0))
            case .notAccessible:
                let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9)
                let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [i, s], relativeTime: 0, duration: 0.3))
            default: break
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {}
    }
}

// MARK: - Main Map View

struct MapView: View {
    @StateObject private var vm = MapViewModel()
    @ObservedObject private var heatmapStore = HeatmapStore.shared
    @State private var showScan = false
    @State private var showRoute = false
    @State private var searchText = ""
    @State private var showBottomSheet = false
    @State private var animateTiles = false
    @FocusState private var searchFocused: Bool

    let primaryColor = Color(red: 136/255, green: 205/255, blue: 212/255)

    var body: some View {
        ZStack(alignment: .top) {
            Map(coordinateRegion: $vm.region, showsUserLocation: true)
                .ignoresSafeArea()
                .accessibilityLabel("Mapa de accesibilidad del entorno")

            GeometryReader { geo in
                ForEach(vm.tiles) { tile in
                    HeatmapTileView(
                        tile: tile,
                        mapRegion: vm.region,
                        geoSize: geo.size,
                        animated: animateTiles,
                        isPulsing: vm.newTileFlash == tile.id
                    )
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
                HStack {
                    Spacer()
                    floatingButtonsColumn
                }
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
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { showBottomSheet = false }
                VStack {
                    Spacer()
                    BottomSheetView(
                        tile: tile,
                        isShowing: $showBottomSheet,
                        userFeedback: $vm.userFeedback,
                        primaryColor: primaryColor
                    )
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showBottomSheet)
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.5).delay(0.7)) { animateTiles = true }
        }
        // FIX 2: Firma compatible con iOS 16 y iOS 17+
        // En iOS 16 la firma de onChange es (oldValue, newValue) -> Void
        // En iOS 17+ es (newValue) -> Void
        // Usar la variante de dos parámetros cubre ambos casos sin warnings.
        .onChange(of: heatmapStore.scannedTiles.count) { _, _ in
            vm.mergeScan(heatmapStore.scannedTiles)
        }
        .fullScreenCover(isPresented: $showScan) {
            ScanView()
        }
        .fullScreenCover(isPresented: $showRoute) {
            NavigationStack {
                RouteView()
            }
        }
    }

    var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary).font(.system(size: 15, weight: .medium))
                TextField("¿A dónde quieres ir?", text: $searchText)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .focused($searchFocused).submitLabel(.search)
                    .accessibilityLabel("Campo de búsqueda de destino")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.accessibilityLabel("Limpiar búsqueda")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)

            Button { } label: {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(primaryColor)
                    .background(Circle().fill(.regularMaterial))
                    .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
            }.accessibilityLabel("Perfil de usuario")
        }
        .padding(.horizontal, 16).padding(.top, 56).padding(.bottom, 8)
    }

    var floatingButtonsColumn: some View {
        VStack(spacing: 12) {
            // Botón Crear Ruta
            Button { showRoute = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "figure.roll").font(.system(size: 16, weight: .semibold))
                    Text("Crear ruta").font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(primaryColor, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: primaryColor.opacity(0.45), radius: 8, x: 0, y: 4)
            }
            .accessibilityLabel("Crear ruta accesible hacia un destino")

            // Botón Scan Area
            Button { showScan = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 16, weight: .semibold))
                    Text("Scan Area").font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(primaryColor.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .accessibilityLabel("Escanear área para detectar accesibilidad")

            FloatingIconButton(icon: "location.fill", color: primaryColor) { vm.centerOnUser() }
                .accessibilityLabel("Centrar mapa en mi ubicación")

            FloatingIconButton(icon: "square.3.layers.3d", color: vm.showLegend ? primaryColor : .secondary) {
                withAnimation { vm.showLegend.toggle() }
            }
            .accessibilityLabel(vm.showLegend ? "Ocultar leyenda" : "Mostrar leyenda")
        }
    }

    var legendPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accesibilidad").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(.primary)
            ForEach([AccessibilityLevel.accessible, .limited, .notAccessible, .noData], id: \.label) { level in
                HStack(spacing: 8) {
                    Circle().fill(level == .noData ? Color.secondary.opacity(0.3) : level.color)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
                    Text(level.label).font(.system(size: 13, weight: .regular, design: .rounded)).foregroundColor(.primary)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Leyenda: Azul accesible, Amarillo limitado, Gris no accesible, Transparente sin datos")
    }

    var emptyStateHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "map").font(.system(size: 22)).foregroundColor(primaryColor)
            Text("Muévete o escanea para generar datos")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
    }

    var loadingIndicator: some View {
        VStack {
            Spacer()
            HStack {
                ProgressView().tint(primaryColor).scaleEffect(0.8)
                Text("Cargando datos...").font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            .padding(.bottom, 110)
        }
    }

    func errorBanner(message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.system(size: 14))
                Text(message).font(.system(size: 13, weight: .medium, design: .rounded))
                Spacer()
                Button { vm.errorMessage = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
            .padding(.horizontal, 16).padding(.top, 120)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Heatmap Tile View
// FIX 3: Animación de pulso corregida.
// El problema original era que la animación usaba el mismo booleano (isPulsing)
// para iniciar Y para terminar el efecto, causando que al poner isPulsing=false
// la animación se invirtiera visualmente (el tile "desaparecía").
// Solución: usar un @State local `pulseScale` que se anima de forma one-shot
// al detectar isPulsing=true, sin depender del valor de retorno.

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
        let x = geoSize.width / 2 + CGFloat(lonDelta / mapRegion.span.longitudeDelta) * geoSize.width
        let y = geoSize.height / 2 - CGFloat(latDelta / mapRegion.span.latitudeDelta) * geoSize.height
        return CGPoint(x: x, y: y)
    }

    var tileColor: Color { tile.accessibilityLevel.color }
    let tileRadius: CGFloat = 72

    var body: some View {
        if tile.accessibilityLevel != .noData {
            ZStack {
                // FIX 3: Onda de pulso — se expande hacia afuera y desvanece (one-shot)
                // No depende de isPulsing como estado de retorno, solo como trigger de entrada.
                if isPulsing {
                    Circle()
                        .fill(tileColor.opacity(pulseOpacity))
                        .frame(width: tileRadius * 2.6, height: tileRadius * 2.6)
                        .scaleEffect(pulseScale)
                        .position(position)
                        .onAppear {
                            withAnimation(.easeOut(duration: 1.0)) {
                                pulseScale = 1.5
                                pulseOpacity = 0.0
                            }
                        }
                }

                // Heatmap blob base
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

                // Punto central para tiles escaneados por el usuario
                if tile.isUserScanned {
                    Circle()
                        .fill(tileColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .shadow(color: tileColor.opacity(0.6), radius: 4, x: 0, y: 2)
                        .position(position)
                        // FIX 3: Entrada con spring para tiles nuevos
                        .scaleEffect(animated ? 1.0 : 0.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1), value: animated)
                }
            }
            .allowsHitTesting(true)
            // FIX 3: Reset del estado de pulso cuando isPulsing vuelve a false
            // para que el próximo scan pueda reutilizar la animación
            .onChange(of: isPulsing) { _, newValue in
                if newValue {
                    pulseScale = 0.8
                    pulseOpacity = 0.6
                }
            }
        }
    }
}

// MARK: - Floating Icon Button

struct FloatingIconButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
        }
    }
}

// MARK: - Bottom Sheet
// FIX 4: Para tiles escaneados por el usuario se muestra el tipo detectado
// (la primera entrada de `reasons`) junto con score y confianza.
// Esto completa el requisito Human-Centered AI: tipo + score + confianza + razón.

struct BottomSheetView: View {
    let tile: AccessibilityTile
    @Binding var isShowing: Bool
    @Binding var userFeedback: [UUID: Bool]
    let primaryColor: Color
    @State private var didReport = false

    var statusIcon: String {
        switch tile.accessibilityLevel {
        case .accessible:    return "checkmark.circle.fill"
        case .limited:       return "exclamationmark.triangle.fill"
        case .notAccessible: return "xmark.circle.fill"
        case .noData:        return "questionmark.circle.fill"
        }
    }

    var statusColor: Color { tile.accessibilityLevel.color }

    // FIX 4: Icono representativo del tipo detectado según la razón principal
    func typeIcon(from reasons: [String]) -> String {
        guard let first = reasons.first?.lowercased() else { return "camera.fill" }
        if first.contains("rampa")      { return "road.lanes" }
        if first.contains("escalera")   { return "figure.stairs" }
        if first.contains("obstáculo")  { return "exclamationmark.triangle.fill" }
        if first.contains("plana")      { return "checkmark.seal.fill" }
        return "camera.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.35)).frame(width: 38, height: 5)
                Spacer()
            }
            .padding(.top, 10).padding(.bottom, 18)

            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.system(size: 28, weight: .semibold)).foregroundColor(statusColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(tile.accessibilityLevel.label)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        if tile.isUserScanned {
                            Label("Escaneado", systemImage: "camera.fill")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(primaryColor)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(primaryColor.opacity(0.12), in: Capsule())
                        }
                    }
                    Text("Confianza: \(tile.confidenceLabel)")
                        .font(.system(size: 14, weight: .regular, design: .rounded)).foregroundColor(.secondary)
                }
                Spacer()
                (Text("\(tile.accessibilityScore)")
                    .font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(statusColor)
                + Text(" / 100")
                    .font(.system(size: 13, weight: .regular, design: .rounded)).foregroundColor(.secondary))
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(tile.accessibilityLevel.voiceOverLabel), puntuación \(tile.accessibilityScore) de 100, confianza \(tile.confidenceLabel)")

            // FIX 4: Bloque de tipo detectado — solo visible para tiles escaneados por el usuario
            // Muestra: tipo detectado + score en porcentaje + razón principal
            if tile.isUserScanned, let mainReason = tile.reasons.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Detección por cámara")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.top, 20)

                    HStack(spacing: 10) {
                        // Tipo detectado con ícono
                        HStack(spacing: 6) {
                            Image(systemName: typeIcon(from: tile.reasons))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(statusColor)
                            Text(mainReason)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                        Spacer()

                        // Score como porcentaje de confianza del modelo
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Score")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.secondary)
                            Text("\(tile.accessibilityScore)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(statusColor)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Detección por cámara: \(mainReason), score \(tile.accessibilityScore)")
            }

            // Factores adicionales (si hay más de uno)
            if tile.reasons.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Factores adicionales")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.top, tile.isUserScanned ? 12 : 20)
                    ForEach(tile.reasons.dropFirst(), id: \.self) { reason in
                        HStack(spacing: 8) {
                            Circle().fill(statusColor.opacity(0.6)).frame(width: 6, height: 6)
                            Text(reason).font(.system(size: 15, weight: .regular, design: .rounded))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Factores adicionales: \(tile.reasons.dropFirst().joined(separator: ", "))")
            } else if !tile.isUserScanned, !tile.reasons.isEmpty {
                // Para tiles no escaneados, mostrar todos los factores como antes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Factores detectados")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary).padding(.top, 20)
                    ForEach(tile.reasons, id: \.self) { reason in
                        HStack(spacing: 8) {
                            Circle().fill(statusColor.opacity(0.6)).frame(width: 6, height: 6)
                            Text(reason).font(.system(size: 15, weight: .regular, design: .rounded))
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Divider().padding(.vertical, 18).padding(.horizontal, 20)

            if let feedback = userFeedback[tile.id] {
                HStack(spacing: 8) {
                    Image(systemName: feedback ? "hand.thumbsup.fill" : "hand.thumbsdown.fill").foregroundColor(primaryColor)
                    Text(feedback ? "¡Gracias por confirmar!" : "Gracias por tu reporte")
                        .font(.system(size: 14, weight: .medium, design: .rounded)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("¿Pasaste bien aquí?")
                        .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.primary)
                    HStack(spacing: 12) {
                        FeedbackButton(label: "Sí", icon: "hand.thumbsup", color: primaryColor) {
                            withAnimation { userFeedback[tile.id] = true }
                        }
                        FeedbackButton(label: "No", icon: "hand.thumbsdown", color: Color(red: 255/255, green: 107/255, blue: 107/255)) {
                            withAnimation { userFeedback[tile.id] = false }
                        }
                        Spacer()
                        Button { didReport = true } label: {
                            Label("Reportar", systemImage: "flag")
                                .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundColor(.secondary)
                        }
                        .accessibilityLabel("Reportar obstáculo en esta zona")
                    }
                }
                .padding(.horizontal, 20)
            }
            Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24).fill(.regularMaterial).shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: -4))
    }
}

struct FeedbackButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(label == "Sí" ? "Sí, pasé bien" : "No, tuve dificultades")
    }
}

#Preview { MapView() }
