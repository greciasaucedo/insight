//
//  MapView.swift
//  InsightApp
//

import SwiftUI
import MapKit
import CoreHaptics
import CoreLocation
import Combine

// MARK: - TileSourceType

enum TileSourceType: String, Codable, CaseIterable {
    case camera           = "camera"
    case motion           = "motion"
    case fused            = "fused"
    case userConfirmation = "userConfirmation"
    case mock             = "mock"
    case remote           = "remote"

    var displayName: String {
        switch self {
        case .camera:           return "Cámara"
        case .motion:           return "Movimiento"
        case .fused:            return "Cámara + Movimiento"
        case .userConfirmation: return "Confirmado"
        case .mock:             return "Demo"
        case .remote:           return "Remoto"
        }
    }

    var icon: String {
        switch self {
        case .camera:           return "camera.fill"
        case .motion:           return "waveform.path.ecg"
        case .fused:            return "sensor.tag.radiowaves.forward.fill"
        case .userConfirmation: return "hand.thumbsup.fill"
        case .mock:             return "wand.and.stars"
        case .remote:           return "icloud.and.arrow.down"
        }
    }
}

// MARK: - AccessibilityTile

struct AccessibilityTile: Identifiable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    var accessibilityScore: Int
    var confidenceScore: Double
    var vibrationScore: Double?
    var slopeScore: Double?
    var passabilityScore: Double?
    var sourceType: TileSourceType
    var detectedLabel: String?
    var profileUsed: String?
    var createdAt: Date

    var recencyWeight: Double {
        let ageSeconds = Date().timeIntervalSince(createdAt)
        let thirtyDays: Double = 30 * 24 * 3600
        return max(0, 1.0 - (ageSeconds / thirtyDays))
    }

    var reasons: [String]
    var isUserScanned: Bool
    var scanImageURL: String?

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

    var effectiveScore: Double {
        Double(accessibilityScore) * recencyWeight * confidenceScore
    }

    init(
        id: UUID = UUID(),
        coordinate: CLLocationCoordinate2D,
        accessibilityScore: Int,
        confidenceScore: Double,
        reasons: [String],
        isUserScanned: Bool = false,
        vibrationScore: Double? = nil,
        slopeScore: Double? = nil,
        passabilityScore: Double? = nil,
        sourceType: TileSourceType = .mock,
        detectedLabel: String? = nil,
        profileUsed: String? = nil,
        createdAt: Date = Date(),
        scanImageURL: String? = nil
    ) {
        self.id                 = id
        self.coordinate         = coordinate
        self.accessibilityScore = accessibilityScore
        self.confidenceScore    = confidenceScore
        self.reasons            = reasons
        self.isUserScanned      = isUserScanned
        self.vibrationScore     = vibrationScore
        self.slopeScore         = slopeScore
        self.passabilityScore   = passabilityScore
        self.sourceType         = sourceType
        self.detectedLabel      = detectedLabel
        self.profileUsed        = profileUsed
        self.createdAt          = createdAt
        self.scanImageURL       = scanImageURL
    }
}

enum AccessibilityLevel {
    case accessible, limited, notAccessible, noData

    var color: Color {
        switch self {
        case .accessible:    return ThemeManager.shared.primaryColor
        case .limited:       return ThemeManager.shared.secondaryColor
        case .notAccessible: return ThemeManager.shared.neutralColor
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

// MARK: - HeatmapStore

class HeatmapStore: ObservableObject {
    static let shared = HeatmapStore()

    @Published private(set) var baseTiles: [AccessibilityTile] = []
    @Published private(set) var scannedTiles: [AccessibilityTile] = []

    var allTiles: [AccessibilityTile] { baseTiles + scannedTiles }

    init() {
        loadBaseTiles()
        let saved = PersistenceService.shared.loadScannedTiles()
        if !saved.isEmpty { scannedTiles = saved }
    }

    @MainActor
    func loadRemoteTiles(near coordinate: CLLocationCoordinate2D) async {
        do {
            let remote = try await TileAPIService.shared.fetchNearbyTiles(
                lat: coordinate.latitude, lng: coordinate.longitude
            )
            guard !remote.isEmpty else { return }

            let existing = allTiles
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
        }
    }

    private func loadBaseTiles() {
        let origin = CLLocationCoordinate2D(latitude: 25.6714, longitude: -100.3098)
        let configs: [(Double, Double, Int, Double, [String], Double?, Double?, Double?, String)] = [
            ( 0.000,  0.000, 85, 0.90, [],                                              0.9,  0.95, 0.90, "flat"),
            ( 0.001,  0.001, 78, 0.80, [],                                              0.8,  0.85, 0.82, "flat"),
            ( 0.002, -0.001, 55, 0.60, ["Inclinación detectada"],                       0.6,  0.45, 0.55, "ramp"),
            ( 0.001, -0.002, 45, 0.50, ["Desvíos frecuentes"],                          0.5,  0.50, 0.48, "ramp"),
            (-0.001,  0.002, 30, 0.70, ["Vibración elevada", "Desvíos frecuentes"],     0.2,  0.60, 0.30, "obstacle"),
            (-0.002, -0.001, 20, 0.40, ["Vibración elevada", "Inclinación detectada"],  0.1,  0.30, 0.20, "stairs"),
            ( 0.003,  0.002, 90, 0.95, [],                                              0.95, 0.97, 0.93, "flat"),
            (-0.001, -0.003, 60, 0.65, ["Inclinación detectada"],                       0.65, 0.55, 0.60, "ramp"),
            ( 0.002,  0.003, 35, 0.30, ["Vibración elevada"],                           0.25, 0.70, 0.35, "obstacle"),
            (-0.003,  0.001, 72, 0.80, [],                                              0.80, 0.88, 0.78, "flat"),
            ( 0.000, -0.003, 10, 0.90, ["Vibración elevada", "Desvíos frecuentes", "Inclinación detectada"], 0.05, 0.20, 0.10, "stairs"),
            ( 0.004, -0.001, 80, 0.85, [],                                              0.85, 0.90, 0.83, "flat"),
        ]

        baseTiles = configs.map { dlat, dlon, score, conf, reasons, vib, slope, pass, label in
            AccessibilityTile(
                coordinate: CLLocationCoordinate2D(
                    latitude: origin.latitude + dlat,
                    longitude: origin.longitude + dlon
                ),
                accessibilityScore: score,
                confidenceScore: conf,
                reasons: reasons,
                isUserScanned: false,
                vibrationScore: vib,
                slopeScore: slope,
                passabilityScore: pass,
                sourceType: .mock,
                detectedLabel: label,
                profileUsed: nil,
                createdAt: Date()
            )
        }
    }

    func addTile(
        coordinate: CLLocationCoordinate2D,
        score: Int,
        confidence: Double,
        reasons: [String],
        vibrationScore: Double? = nil,
        slopeScore: Double? = nil,
        passabilityScore: Double? = nil,
        sourceType: TileSourceType = .camera,
        detectedLabel: String? = nil,
        profileUsed: String? = nil,
        scanImageURL: String? = nil
    ) {
        let tile = AccessibilityTile(
            coordinate: coordinate,
            accessibilityScore: score,
            confidenceScore: confidence,
            reasons: reasons,
            isUserScanned: true,
            vibrationScore: vibrationScore,
            slopeScore: slopeScore,
            passabilityScore: passabilityScore,
            sourceType: sourceType,
            detectedLabel: detectedLabel,
            profileUsed: profileUsed,
            createdAt: Date(),
            scanImageURL: scanImageURL
        )

        scannedTiles.append(tile)
        PersistenceService.shared.saveScannedTiles(scannedTiles)
    }

    func updateTileScanImageURL(id: UUID, url: String) {
        if let idx = scannedTiles.firstIndex(where: { $0.id == id }) {
            scannedTiles[idx].scanImageURL = url
        }
    }

    func updateTile(id: UUID, newScore: ScoringOutput) {
        if let index = scannedTiles.firstIndex(where: { $0.id == id }) {
            scannedTiles[index].accessibilityScore = newScore.accessibilityScore
            scannedTiles[index].confidenceScore = newScore.confidenceScore
            scannedTiles[index].passabilityScore = newScore.passabilityScore
            scannedTiles[index].reasons = newScore.reasons
            scannedTiles[index].sourceType = newScore.effectiveSourceType

            PersistenceService.shared.saveScannedTiles(scannedTiles)
        }

        if let index = baseTiles.firstIndex(where: { $0.id == id }) {
            baseTiles[index].accessibilityScore = newScore.accessibilityScore
            baseTiles[index].confidenceScore = newScore.confidenceScore
            baseTiles[index].passabilityScore = newScore.passabilityScore
            baseTiles[index].reasons = newScore.reasons
            baseTiles[index].sourceType = .userConfirmation
        }
    }

    func updateScannedTile(id: UUID, applying validation: UserValidation) {
        guard let idx = scannedTiles.firstIndex(where: { $0.id == id }) else { return }

        let old = scannedTiles[idx]
        let newScore = validation.isPositive
            ? max(old.accessibilityScore, 70)
            : min(old.accessibilityScore, 35)

        scannedTiles[idx] = AccessibilityTile(
            id:                 old.id,
            coordinate:         old.coordinate,
            accessibilityScore: newScore,
            confidenceScore:    min(1.0, old.confidenceScore + 0.15),
            reasons:            old.reasons + [validation.passExperience.label],
            isUserScanned:      true,
            vibrationScore:     old.vibrationScore,
            slopeScore:         old.slopeScore,
            passabilityScore:   validation.derivedPassabilityScore,
            sourceType:         .userConfirmation,
            detectedLabel:      old.detectedLabel,
            profileUsed:        old.profileUsed,
            createdAt:          old.createdAt
        )

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

    func processNewScans(_ scannedTiles: [AccessibilityTile]) {
        for tile in scannedTiles where !knownScannedIDs.contains(tile.id) {
            knownScannedIDs.insert(tile.id)
            newTileFlash = tile.id

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.newTileFlash == tile.id {
                    self.newTileFlash = nil
                }
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
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch {
        }
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
                events.append(
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                        ],
                        relativeTime: 0
                    )
                )

            case .notAccessible:
                events.append(
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                        ],
                        relativeTime: 0,
                        duration: 0.3
                    )
                )

            default:
                break
            }

            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: 0)
        } catch {
        }
    }
}

// MARK: - Main Map View

struct MapView: View {
    @StateObject private var vm = MapViewModel()
    @ObservedObject private var store = HeatmapStore.shared
    @ObservedObject private var ghostStore = GhostLayerStore.shared

    @EnvironmentObject var themeManager: ThemeManager

    @State private var showScan        = false
    @State private var showRoute       = false
    @State private var showProfile     = false
    @State private var showBottomSheet = false
    @State private var searchText      = ""

    @FocusState private var searchFocused: Bool

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

                // Ghost Layer — capa de comportamiento colectivo
                if ghostStore.isVisible {
                    GhostLayerView(
                        store: ghostStore,
                        mapRegion: vm.region,
                        geoSize: geo.size
                    )
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()

            // Layer B — transparent tap targets
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

            // Search bar top
            VStack(spacing: 0) {
                searchBar
                Spacer()
            }

            // Leyenda — esquina inferior izquierda
            VStack {
                Spacer()
                HStack {
                    legendPanel
                        .padding(.leading, 16)
                        .padding(.bottom, showBottomSheet ? 340 : 32)
                        .animation(.spring(response: 0.4), value: showBottomSheet)
                    Spacer()
                }
            }

            // Ghost control panel — esquina inferior izquierda, arriba de la leyenda
            if ghostStore.isVisible {
                VStack {
                    Spacer()
                    HStack {
                        GhostLayerControlPanel(
                            store: ghostStore,
                            teal: themeManager.primaryColor
                        )
                        .padding(.leading, 16)

                        Spacer()
                    }
                }
                .padding(.bottom, showBottomSheet ? 360 : 110)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: ghostStore.isVisible)
            }

            // Botones — esquina inferior derecha
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    floatingButtonsColumn
                        .padding(.trailing, 16)
                        .padding(.bottom, showBottomSheet ? 340 : 32)
                        .animation(.spring(response: 0.4), value: showBottomSheet)
                }
            }

            if !vm.hasData && !vm.isLoading {
                emptyStateHint
            }

            if vm.isLoading {
                loadingIndicator
            }

            if let error = vm.errorMessage {
                errorBanner(message: error)
            }

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
                        primaryColor: themeManager.primaryColor
                    )
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showBottomSheet)
            }
        }
        .task {
            await store.loadRemoteTiles(near: vm.region.center)
            GhostLayerStore.shared.setup()
        }
        .onChange(of: store.scannedTiles.count) { _, _ in
            Task { @MainActor in
                vm.processNewScans(store.scannedTiles)
            }
        }
        .fullScreenCover(isPresented: $showScan) {
            ScanView().environmentObject(themeManager)
        }
        .sheet(isPresented: $showRoute) {
            RouteView()
                .environmentObject(themeManager)
        }
        .fullScreenCover(isPresented: $showProfile) {
            ProfileView().environmentObject(themeManager)
        }
    }

    // MARK: Search bar

    var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 15, weight: .medium))

                TextField("¿A dónde quieres ir?", text: $searchText)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        if !searchText.isEmpty {
                            showRoute = true
                        }
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)

            Button {
                showProfile = true
            } label: {
                Group {
                    if let urlStr = AuthService.shared.currentUser?.avatarURL,
                       let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                                    .frame(width: 40, height: 40).clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 34)).foregroundStyle(themeManager.primaryColor)
                            }
                        }
                        .frame(width: 40, height: 40)
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 34)).foregroundStyle(themeManager.primaryColor)
                    }
                }
                .background(Circle().fill(.regularMaterial))
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: Floating buttons

    var floatingButtonsColumn: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Button {
                showRoute = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "figure.roll")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Crear ruta")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(themeManager.primaryColor, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: themeManager.primaryColor.opacity(0.5), radius: 8, x: 0, y: 4)
            }
            .accessibilityLabel("Crear ruta accesible")

            Button {
                showScan = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Escanear")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(themeManager.primaryColor.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            }
            .accessibilityLabel("Escanear área")

            HStack(spacing: 8) {
                FloatingIconButton(
                    icon: "location.fill",
                    color: themeManager.primaryColor
                ) {
                    vm.centerOnUser()
                }

                FloatingIconButton(
                    icon: "square.3.layers.3d",
                    color: themeManager.primaryColor
                ) {
                }

                GhostToggleButton(
                    store: ghostStore,
                    teal: themeManager.primaryColor
                )
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
                    Circle()
                        .fill(level.color)
                        .frame(width: 12, height: 12)

                    Text(level.label)
                        .font(.system(size: 13, design: .rounded))
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
            Image(systemName: "map")
                .font(.system(size: 22))
                .foregroundColor(themeManager.primaryColor)

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
                ProgressView()
                    .tint(themeManager.primaryColor)
                    .scaleEffect(0.8)

                Text("Cargando datos...")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 110)
        }
    }

    private func tilePosition(_ tile: AccessibilityTile, size: CGSize) -> CGPoint {
        let latDelta = tile.coordinate.latitude - vm.region.center.latitude
        let lonDelta = tile.coordinate.longitude - vm.region.center.longitude

        let x = size.width / 2 + CGFloat(lonDelta / vm.region.span.longitudeDelta) * size.width
        let y = size.height / 2 - CGFloat(latDelta / vm.region.span.latitudeDelta) * size.height

        return CGPoint(x: x, y: y)
    }

    func errorBanner(message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)

                Text(message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))

                Spacer()

                Button {
                    vm.errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 120)

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

        let x = geoSize.width / 2 + CGFloat(lonDelta / mapRegion.span.longitudeDelta) * geoSize.width
        let y = geoSize.height / 2 - CGFloat(latDelta / mapRegion.span.latitudeDelta) * geoSize.height

        return CGPoint(x: x, y: y)
    }

    let tileRadius: CGFloat = 72

    var tileColor: Color { tile.accessibilityLevel.color }
    var baseOpacity: Double { max(0.18, tile.recencyWeight * 0.42) }

    var body: some View {
        if tile.accessibilityLevel != .noData {
            ZStack {
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

                Ellipse()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                tileColor.opacity(animated ? baseOpacity : 0),
                                tileColor.opacity(animated ? baseOpacity * 0.45 : 0),
                                tileColor.opacity(0)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: tileRadius
                        )
                    )
                    .frame(width: tileRadius * 2, height: tileRadius * 1.5)
                    .position(position)
                    .animation(.easeInOut(duration: 0.28), value: animated)

                if tile.isUserScanned {
                    Circle()
                        .fill(tileColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .shadow(color: tileColor.opacity(0.6), radius: 4, x: 0, y: 2)
                        .position(position)
                        .scaleEffect(animated ? 1.0 : 0.0)
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.6).delay(0.1),
                            value: animated
                        )
                }
            }
            .allowsHitTesting(true)
            .onChange(of: isPulsing) { _, newVal in
                if newVal {
                    pulseScale = 0.8
                    pulseOpacity = 0.6
                }
            }
        }
    }
}

// MARK: - FloatingIconButton

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

// MARK: - BottomSheetView

struct BottomSheetView: View {
    let tile: AccessibilityTile
    @Binding var isShowing: Bool
    @Binding var userFeedback: [UUID: Bool]
    let primaryColor: Color

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.locale = Locale(identifier: "es_MX")
        return f
    }()

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
        if first.contains("rampa")     { return "road.lanes" }
        if first.contains("escalera")  { return "figure.stairs" }
        if first.contains("obstáculo") { return "exclamationmark.triangle.fill" }
        if first.contains("plana")     { return "checkmark.seal.fill" }
        return "camera.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 38, height: 5)
                Spacer()
            }
            .padding(.top, 10)
            .padding(.bottom, 18)

            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(statusColor)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(tile.accessibilityLevel.label)
                            .font(.system(size: 20, weight: .bold, design: .rounded))

                        if tile.isUserScanned {
                            let isSimulated = tile.reasons.first?.contains("(simulado)") ?? false

                            Label(
                                isSimulated ? "Demo" : "Escaneado",
                                systemImage: isSimulated ? "wand.and.stars" : "camera.fill"
                            )
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(isSimulated ? .orange : primaryColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                (isSimulated ? Color.orange : primaryColor).opacity(0.12),
                                in: Capsule()
                            )
                        }
                    }

                    Text("Confianza: \(tile.confidenceLabel)")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(tile.accessibilityScore)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(statusColor)
                +
                Text(" / 100")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Label(tile.sourceType.displayName, systemImage: tile.sourceType.icon)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()

                let rw = tile.recencyWeight
                let recencyColor: Color = rw > 0.7 ? .green : (rw > 0.3 ? .orange : .red)

                Label(dateFormatter.string(from: tile.createdAt), systemImage: "clock")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(recencyColor)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            if let urlStr = tile.scanImageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(maxWidth: .infinity).frame(height: 160)
                            .clipped().cornerRadius(12)
                            .padding(.horizontal, 20).padding(.top, 12)
                    default:
                        EmptyView()
                    }
                }
            }

            if tile.vibrationScore != nil || tile.slopeScore != nil || tile.passabilityScore != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Detalles de superficie")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.top, 16)

                    HStack(spacing: 12) {
                        if let v = tile.vibrationScore {
                            MiniScoreChip(label: "Vibración", value: v, icon: "waveform.path", color: statusColor)
                        }
                        if let s = tile.slopeScore {
                            MiniScoreChip(label: "Pendiente", value: s, icon: "angle", color: statusColor)
                        }
                        if let p = tile.passabilityScore {
                            MiniScoreChip(label: "Transitabilidad", value: p, icon: "figure.walk", color: statusColor)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            if tile.isUserScanned, let mainReason = tile.reasons.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Detección por cámara")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.top, 20)

                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: typeIcon(from: tile.reasons))
                                .font(.system(size: 13))
                                .foregroundColor(statusColor)

                            Text(mainReason)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                        Spacer()

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
                                Circle()
                                    .fill(statusColor.opacity(0.6))
                                    .frame(width: 6, height: 6)

                                Text(reason)
                                    .font(.system(size: 15, design: .rounded))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            if let profile = tile.profileUsed {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text("Perfil: \(profile)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            Divider()
                .padding(.vertical, 18)
                .padding(.horizontal, 20)

            if let feedback = userFeedback[tile.id] {
                HStack(spacing: 8) {
                    Image(systemName: feedback ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .foregroundColor(primaryColor)

                    Text(feedback ? "¡Gracias por confirmar!" : "Gracias por tu reporte")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("¿Pasaste bien aquí?")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))

                    HStack(spacing: 12) {
                        FeedbackButton(label: "Sí", icon: "hand.thumbsup", color: primaryColor) {
                            let input = ScoringInput(
                                detectedLabel:    tile.detectedLabel,
                                visualConfidence: tile.confidenceScore,
                                vibrationScore:   tile.vibrationScore,
                                slopeScore:       tile.slopeScore,
                                motionConfidence: nil,
                                profile:          ProfileService.shared.currentProfile,
                                existingTile:     tile,
                                userConfirmation: true
                            )

                            let rescored = LayerScoringEngine.score(input)
                            HeatmapStore.shared.updateTile(id: tile.id, newScore: rescored)

                            withAnimation {
                                userFeedback[tile.id] = true
                            }
                        }

                        FeedbackButton(
                            label: "No",
                            icon: "hand.thumbsdown",
                            color: Color(red: 1, green: 0.42, blue: 0.42)
                        ) {
                            let input = ScoringInput(
                                detectedLabel:    tile.detectedLabel,
                                visualConfidence: tile.confidenceScore,
                                vibrationScore:   tile.vibrationScore,
                                slopeScore:       tile.slopeScore,
                                motionConfidence: nil,
                                profile:          ProfileService.shared.currentProfile,
                                existingTile:     tile,
                                userConfirmation: false
                            )

                            let rescored = LayerScoringEngine.score(input)
                            HeatmapStore.shared.updateTile(id: tile.id, newScore: rescored)

                            withAnimation {
                                userFeedback[tile.id] = false
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: -4)
        )
    }
}

// MARK: - MiniScoreChip

struct MiniScoreChip: View {
    let label: String
    let value: Double
    let icon: String
    let color: Color

    var pct: Int { Int(value * 100) }

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)

            Text("\(pct)%")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(color)

            Text(label)
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

#Preview {
    MapView()
        .environmentObject(ThemeManager.shared)
}
