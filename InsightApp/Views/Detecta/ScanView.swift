//
//  ScanView.swift
//  InsightApp
//
//  Created by Guillermo Lira on 18/04/26.
//

import SwiftUI
import UIKit
import AVFoundation
import CoreML
@preconcurrency import Vision
import CoreLocation
import Combine

// MARK: - Scan Result Model

struct ScanResult {
    let label: String
    let confidence: Float
    let coordinate: CLLocationCoordinate2D

    var accessibilityScore: Int {
        switch label.lowercased() {
        case "obstacle": return 25
        case "flat":     return 85
        case "ramp":     return 80
        case "stairs":   return 55
        default:         return 50
        }
    }

    var accessibilityLevel: AccessibilityLevel {
        switch accessibilityScore {
        case 70...100: return .accessible
        case 40...69:  return .limited
        case 0...39:   return .notAccessible
        default:       return .noData
        }
    }

    var localizedLabel: String {
        switch label.lowercased() {
        case "stairs":   return "Escaleras"
        case "ramp":     return "Rampa"
        case "obstacle": return "Obstáculo"
        case "flat":     return "Superficie plana"
        default:         return label.capitalized
        }
    }

    var icon: String {
        switch label.lowercased() {
        case "stairs":   return "figure.stairs"
        case "ramp":     return "road.lanes"
        case "obstacle": return "exclamationmark.triangle.fill"
        case "flat":     return "checkmark.seal.fill"
        default:         return "questionmark.circle"
        }
    }

    var description: String {
        switch label.lowercased() {
        case "stairs":   return "Puede presentar dificultades para sillas de ruedas."
        case "ramp":     return "Acceso facilitado para movilidad reducida."
        case "obstacle": return "Obstáculo detectado. Zona de precaución."
        case "flat":     return "Superficie accesible sin barreras detectadas."
        default:         return "Zona analizada."
        }
    }

    var reasons: [String] {
        switch label.lowercased() {
        case "obstacle": return ["Obstáculo detectado por cámara"]
        case "stairs":   return ["Escaleras detectadas por cámara"]
        case "ramp":     return ["Rampa detectada por cámara"]
        case "flat":     return ["Superficie plana detectada por cámara"]
        default:         return ["Zona analizada por cámara"]
        }
    }
}

// MARK: - Camera ViewModel

@MainActor
final class ScanViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var capturedImage: UIImage? = nil
    @Published var scanResult: ScanResult? = nil
    @Published var isAnalyzing = false
    @Published var errorMessage: String? = nil
    @Published var showSuccess = false
    @Published var isUsingDemo = false
    @Published var motionResult: TerrainMotionResult? = nil
    @Published var isMeasuringMotion = false

    private let locationManager = CLLocationManager()
    private(set) var currentLocation = CLLocationCoordinate2D(
        latitude: 25.6714,
        longitude: -100.3098
    )

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func analyze(image: UIImage) {
        capturedImage = image
        scanResult = nil
        motionResult = nil
        errorMessage = nil
        isAnalyzing = true
        isMeasuringMotion = false

        guard let cgImage = image.cgImage else {
            errorMessage = "No se pudo procesar la imagen."
            isAnalyzing = false
            return
        }

        if let model = try? AccessibilitySurfaceClassifier_1(configuration: MLModelConfiguration()),
           let visionModel = try? VNCoreMLModel(for: model.model) {
            isUsingDemo = false
            runVision(cgImage: cgImage, model: visionModel)
        } else {
            isUsingDemo = true
            simulatePrediction()
        }
    }

    private func runVision(cgImage: CGImage, model: VNCoreMLModel) {
        let request = VNCoreMLRequest(model: model) { [weak self] request, _ in
            guard let self else { return }

            DispatchQueue.main.async {
                self.isAnalyzing = false

                if let results = request.results as? [VNClassificationObservation],
                   let top = results.first {
                    let coord = self.locationManager.location?.coordinate ?? self.currentLocation
                    self.scanResult = ScanResult(
                        label: top.identifier,
                        confidence: top.confidence,
                        coordinate: coord
                    )
                } else {
                    self.errorMessage = "No se pudo clasificar la imagen."
                }
            }
        }

        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "No se pudo analizar la imagen."
                self.isAnalyzing = false
            }
        }
    }

    private func simulatePrediction() {
        let classes: [(String, Float)] = [
            ("flat",     Float(0.93)),
            ("ramp",     Float(0.88)),
            ("stairs",   Float(0.79)),
            ("obstacle", Float(0.71))
        ]

        let pick = classes.randomElement()!

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let coord = self.locationManager.location?.coordinate ?? self.currentLocation
            self.scanResult = ScanResult(
                label: pick.0,
                confidence: pick.1,
                coordinate: coord
            )
            self.isAnalyzing = false
        }
    }

    func useScan() {
        guard let result = scanResult, !isMeasuringMotion else { return }
        saveToMap(result: result, isDemo: isUsingDemo)
    }

    func reset() {
        capturedImage = nil
        scanResult = nil
        showSuccess = false
        errorMessage = nil
        isUsingDemo = false
        motionResult = nil
        isMeasuringMotion = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate
    }
}

// MARK: - Save to Map Extension

extension ScanViewModel {

    /// Mide el terreno con Core Motion, fusiona visión + motion + recencia
    /// y luego guarda el tile con scores reales.
    func saveToMap(result: ScanResult, isDemo: Bool) {
        Task { @MainActor in
            isMeasuringMotion = true
            defer { isMeasuringMotion = false }

            // 1. Medir terreno si no es demo
            var terrain: TerrainMotionResult? = nil
            if !isDemo {
                terrain = await MotionAccessibilityService.shared.measureTerrain()
            }

            motionResult = terrain

            let coordinate = result.coordinate

            // 2. Buscar tile previo en esa zona
            let existingTile = HeatmapStore.shared.tileNear(coordinate)

            // 3. Calcular score fusionado
            let input = ScoringInput(
                detectedLabel:    isDemo ? nil : result.label,
                visualConfidence: Double(result.confidence),
                vibrationScore:   terrain?.accessibilityVibrationScore,
                slopeScore:       terrain?.accessibilitySlopeScore,
                motionConfidence: terrain?.motionConfidence,
                profile:          ProfileService.shared.currentProfile,
                existingTile:     existingTile,
                userConfirmation: nil
            )

            let scored = LayerScoringEngine.score(input)

            // 4. Decidir si este scan se acepta, se fusiona o se ignora
            let trust = TileConfidenceService.shouldTrustNewScan(
                newConfidence: scored.confidenceScore,
                existingTile: existingTile
            )

            switch trust {
            case .accept, .merge:
                break

            case .ignore(let reason):
                print("[Scoring] Scan ignorado: \(reason)")

                withAnimation {
                    showSuccess = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    self.reset()
                }
                return
            }

            // 5. Reasons finales
            let reasons: [String]
            if isDemo {
                reasons = scored.reasons.map { $0 + " (simulado)" }
            } else {
                reasons = scored.reasons
            }

            // 6. Source type final
            let sourceType: TileSourceType
            if isDemo {
                sourceType = .mock
            } else {
                sourceType = scored.effectiveSourceType
            }

            // 7. Guardar tile con scores fusionados
            HeatmapStore.shared.addTile(
                coordinate:       coordinate,
                score:            scored.accessibilityScore,
                confidence:       scored.confidenceScore,
                reasons:          reasons,
                vibrationScore:   terrain?.accessibilityVibrationScore,
                slopeScore:       terrain?.accessibilitySlopeScore,
                passabilityScore: scored.passabilityScore,
                sourceType:       sourceType,
                detectedLabel:    result.label,
                profileUsed:      ProfileService.shared.currentProfile.rawValue
            )

            // 8. Upload en background
            if let lastTile = HeatmapStore.shared.scannedTiles.last {
                let image = capturedImage
                Task {
                    try? await TileAPIService.shared.saveTile(lastTile, image: image, isSimulated: isDemo)
                }
            }

            withAnimation {
                showSuccess = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                self.reset()
            }
        }
    }
}

// MARK: - Main Scan View

struct ScanView: View {
    @StateObject private var vm = ScanViewModel()
    @Environment(\.dismiss) private var dismiss

    let primaryColor = Color(red: 136/255, green: 205/255, blue: 212/255)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if vm.capturedImage == nil {
                CameraPreviewView { image in
                    vm.analyze(image: image)
                }
                .ignoresSafeArea()

                cameraOverlay
            } else {
                resultView
            }

            if vm.showSuccess {
                successOverlay
            }
        }
        .statusBarHidden(true)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Camera Overlay

    var cameraOverlay: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .accessibilityLabel("Cerrar escáner")

                Spacer()

                Text("Escanear zona")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)

            Spacer()

            RoundedRectangle(cornerRadius: 20)
                .stroke(primaryColor.opacity(0.7), lineWidth: 2)
                .frame(width: 280, height: 280)
                .overlay(
                    Image(systemName: "viewfinder")
                        .font(.system(size: 40))
                        .foregroundColor(primaryColor.opacity(0.5))
                )
                .accessibilityHidden(true)

            Text("Apunta hacia el área que deseas evaluar")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .padding(.top, 16)
                .accessibilityLabel("Apunta la cámara hacia el área que deseas evaluar")

            Spacer()

            CaptureButton(color: primaryColor)
                .allowsHitTesting(false)
                .padding(.bottom, 48)
        }
    }

    // MARK: - Result View

    var resultView: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                if let img = vm.capturedImage {
                    ZStack(alignment: .bottom) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: proxy.size.height * 0.55)
                            .clipped()
                            .accessibilityLabel("Foto capturada para análisis")

                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.6)]),
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .frame(height: 120)

                        if vm.isAnalyzing {
                            analyzingBadge
                                .padding(.bottom, 20)
                        } else if vm.isMeasuringMotion {
                            measuringBadge
                                .padding(.bottom, 20)
                        }
                    }
                }

                ZStack {
                    Color.black

                    VStack(spacing: 0) {
                        if vm.isAnalyzing {
                            analyzingPlaceholder
                        } else if vm.isMeasuringMotion {
                            measuringTerrainPlaceholder
                        } else if let result = vm.scanResult {
                            predictionCard(result: result)
                        } else if let error = vm.errorMessage {
                            errorCard(message: error)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Prediction Card

    func predictionCard(result: ScanResult) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(result.accessibilityLevel.color.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: result.icon)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(result.accessibilityLevel.color)
                }

                Text(result.localizedLabel)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 11))
                    Text("Score: \(result.accessibilityScore) / 100")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(result.accessibilityLevel.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(result.accessibilityLevel.color.opacity(0.15), in: Capsule())

                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 11))
                    Text("Confianza: \(Int(result.confidence * 100))%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.white.opacity(0.08), in: Capsule())

                if vm.isUsingDemo {
                    HStack(spacing: 5) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 11))
                        Text("Modo demo")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke(.orange.opacity(0.3), lineWidth: 1))
                }

                Text(result.description)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if let reason = result.reasons.first {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                        Text(vm.isUsingDemo ? "\(reason) (simulado)" : reason)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(result.localizedLabel). \(result.description). " +
                "Score: \(result.accessibilityScore). " +
                "Confianza: \(Int(result.confidence * 100)) por ciento." +
                (vm.isUsingDemo ? " Modo demo activo." : "")
            )

            HStack(spacing: 8) {
                Circle()
                    .fill(result.accessibilityLevel.color)
                    .frame(width: 10, height: 10)

                Text("Se agregará como: \(result.accessibilityLevel.label)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 14) {
                Button {
                    withAnimation(.spring(response: 0.35)) {
                        vm.reset()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .semibold))

                        Text("Repetir")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
                }
                .accessibilityLabel("Repetir captura")

                Button {
                    vm.useScan()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))

                        Text("Usar")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(primaryColor, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: primaryColor.opacity(0.4), radius: 10, x: 0, y: 4)
                }
                .disabled(vm.isMeasuringMotion)
                .opacity(vm.isMeasuringMotion ? 0.6 : 1)
                .accessibilityLabel("Usar esta clasificación y agregarla al mapa")
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 28)
        .padding(.bottom, 40)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.scanResult != nil)
    }

    // MARK: - States

    var analyzingBadge: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.8)

            Text("Analizando...")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6), in: Capsule())
        .accessibilityLabel("Analizando la imagen con inteligencia artificial")
    }

    var measuringBadge: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.8)

            Text("Midiendo terreno...")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6), in: Capsule())
        .accessibilityLabel("Midiendo el terreno con sensores de movimiento")
    }

    var analyzingPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(primaryColor)
                .scaleEffect(1.4)

            Text("Clasificando superficie...")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.top, 40)
    }

    var measuringTerrainPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(primaryColor)
                .scaleEffect(1.4)

            Text("Midiendo terreno...")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))

            Text("Estamos calculando vibración, inclinación y transitabilidad.")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 40)
    }

    func errorCard(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 36))
                .foregroundColor(.orange)

            Text(message)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Intentar de nuevo") {
                vm.reset()
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundColor(primaryColor)
        }
        .padding(.top, 40)
    }

    // MARK: - Success Overlay

    var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "map.fill")
                    .font(.system(size: 44))
                    .foregroundColor(primaryColor)

                Text("¡Agregado al mapa!")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                if let result = vm.scanResult {
                    HStack(spacing: 6) {
                        Image(systemName: result.icon)
                            .font(.system(size: 14))
                            .foregroundColor(result.accessibilityLevel.color)
                        Text("\(result.localizedLabel) · Score \(result.accessibilityScore)")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(result.accessibilityLevel.color)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(result.accessibilityLevel.color.opacity(0.15), in: Capsule())
                }

                Text("La zona ya aparece en el heatmap")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(36)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: primaryColor.opacity(0.3), radius: 20)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .animation(.spring(response: 0.4), value: vm.showSuccess)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Zona agregada al mapa de accesibilidad correctamente")
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onCapture = onCapture
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

final class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onCapture: ((UIImage) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var captureButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupShutterButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupCamera() {
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(output) else { return }

        session.addInput(input)
        session.addOutput(output)

        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    private func setupShutterButton() {
        captureButton = UIButton(type: .custom)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.backgroundColor = .clear

        captureButton.layer.cornerRadius = 38
        captureButton.layer.borderWidth = 2.5
        captureButton.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        captureButton.layer.shadowColor = UIColor.black.cgColor
        captureButton.layer.shadowOpacity = 0.22
        captureButton.layer.shadowRadius = 10
        captureButton.layer.shadowOffset = CGSize(width: 0, height: 4)

        let inner = UIView()
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.isUserInteractionEnabled = false
        inner.backgroundColor = UIColor(
            red: 136 / 255,
            green: 205 / 255,
            blue: 212 / 255,
            alpha: 0.95
        )
        inner.layer.cornerRadius = 29
        inner.layer.borderWidth = 1
        inner.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        inner.clipsToBounds = true

        let highlight = CAGradientLayer()
        highlight.colors = [
            UIColor.white.withAlphaComponent(0.45).cgColor,
            UIColor.clear.cgColor
        ]
        highlight.startPoint = CGPoint(x: 0.5, y: 0.0)
        highlight.endPoint = CGPoint(x: 0.5, y: 1.0)
        highlight.frame = CGRect(x: 0, y: 0, width: 58, height: 30)
        highlight.cornerRadius = 29
        inner.layer.addSublayer(highlight)

        captureButton.addSubview(inner)
        view.addSubview(captureButton)

        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            captureButton.widthAnchor.constraint(equalToConstant: 76),
            captureButton.heightAnchor.constraint(equalToConstant: 76),

            inner.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor),
            inner.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            inner.widthAnchor.constraint(equalToConstant: 58),
            inner.heightAnchor.constraint(equalToConstant: 58)
        ])

        captureButton.addTarget(self, action: #selector(capture), for: .touchUpInside)
        captureButton.accessibilityLabel = "Tomar foto"
    }

    @objc private func capture() {
        UIView.animate(withDuration: 0.12, animations: {
            self.captureButton.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            self.captureButton.alpha = 0.9
        }) { _ in
            UIView.animate(withDuration: 0.16) {
                self.captureButton.transform = .identity
                self.captureButton.alpha = 1.0
            }
        }

        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        session.stopRunning()

        DispatchQueue.main.async {
            self.onCapture?(image)
        }
    }
}

// MARK: - Decorative Capture Button

struct CaptureButton: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            color.opacity(0.18),
                            color.opacity(0.08),
                            .clear
                        ]),
                        center: .center,
                        startRadius: 8,
                        endRadius: 42
                    )
                )
                .frame(width: 92, height: 92)
                .blur(radius: 2)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.85),
                            color.opacity(0.95),
                            .white.opacity(0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: 74, height: 74)
                .shadow(color: color.opacity(0.25), radius: 10, x: 0, y: 4)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.95),
                            color.opacity(0.92),
                            color.opacity(0.78)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 58, height: 58)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.45),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .padding(6)
                )
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 5)

            Circle()
                .fill(.white.opacity(0.22))
                .frame(width: 18, height: 18)
                .offset(x: -14, y: -14)
                .blur(radius: 0.5)
        }
        .frame(width: 92, height: 92)
        .accessibilityHidden(true)
    }
}

#Preview {
    ScanView()
}
