//
//  Motionaccessibilityservice.swift
//  InsightApp
//
//  Created by Guillermo Lira on 18/04/26.
//  Servicio de medición de terreno usando Core Motion.
//  Lee acelerómetro + device motion para calcular:
//    • vibrationScore  — qué tan rugosa/irregular es la superficie (0.0 liso → 1.0 muy rugoso)
//    • slopeScore      — qué tan inclinado está el terreno       (0.0 plano → 1.0 muy inclinado)
//    • motionConfidence — confianza del resultado según muestras recolectadas
//
//  Uso típico desde ScanViewModel:
//
//    Task {
//        let result = await MotionAccessibilityService.shared.measureTerrain()
//        // result.terrainVibration, result.terrainSlope, result.motionConfidence
//    }
//

import Foundation
import CoreMotion
import Combine

// MARK: - Result type

/// Resultado de una ventana de medición de terreno.
struct TerrainMotionResult {
    /// Rugosidad de la superficie. 0.0 = completamente liso, 1.0 = muy irregular.
    let terrainVibration: Double

    /// Inclinación del terreno. 0.0 = plano, 1.0 = pendiente máxima (≥ 30°).
    let terrainSlope: Double

    /// Confianza del resultado (0.0–1.0). Sube con el número de muestras válidas.
    let motionConfidence: Double

    /// Número de muestras de acelerómetro que formaron este resultado.
    let sampleCount: Int

    /// Duración real de la ventana de medición.
    let windowDuration: TimeInterval

    // MARK: Derived scores (invertidos para AccessibilityTile)

    /// `vibrationScore` para AccessibilityTile: 1.0 = liso (bueno), 0.0 = muy rugoso (malo).
    var accessibilityVibrationScore: Double { max(0, 1.0 - terrainVibration) }

    /// `slopeScore` para AccessibilityTile: 1.0 = plano (bueno), 0.0 = muy inclinado (malo).
    var accessibilitySlopeScore: Double { max(0, 1.0 - terrainSlope) }

    /// Estimación combinada de transitabilidad basada en vibración + pendiente.
    var passabilityScore: Double {
        let v = accessibilityVibrationScore
        let s = accessibilitySlopeScore
        // Peso: pendiente pesa más que vibración para accesibilidad en silla de ruedas
        return (v * 0.4 + s * 0.6).clamped(to: 0...1)
    }

    static let unavailable = TerrainMotionResult(
        terrainVibration: 0,
        terrainSlope: 0,
        motionConfidence: 0,
        sampleCount: 0,
        windowDuration: 0
    )
}

// MARK: - Service

@MainActor
final class MotionAccessibilityService: ObservableObject {

    static let shared = MotionAccessibilityService()
    private init() {}

    // MARK: Published state

    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var lastResult: TerrainMotionResult? = nil

    // MARK: Configuration

    /// Duración de la ventana de muestreo en segundos.
    private let windowDuration: TimeInterval = 3.0

    /// Frecuencia de muestreo del acelerómetro (Hz).
    private let accelerometerHz: Double = 50.0

    /// Ángulo de pendiente (grados) que se considera máximo para normalizar a 1.0.
    private let maxSlopeDegrees: Double = 30.0

    // MARK: Private

    private let motion = CMMotionManager()
    private let altimeter = CMAltimeter()

    // Buffers de muestras
    private var accelerationSamples: [Double] = []  // magnitud de aceleración filtrada
    private var attitudeSamples: [Double] = []       // ángulo de pitch en grados

    // MARK: - Availability

    /// Verifica si el hardware soporta los sensores necesarios.
    func checkAvailability() {
        isAvailable = motion.isAccelerometerAvailable && motion.isDeviceMotionAvailable
    }

    // MARK: - One-shot measurement

    /// Inicia una ventana de medición de `windowDuration` segundos y devuelve el resultado.
    /// Si el hardware no está disponible, devuelve `TerrainMotionResult.unavailable`.
    func measureTerrain() async -> TerrainMotionResult {
        guard motion.isAccelerometerAvailable, motion.isDeviceMotionAvailable else {
            return .unavailable
        }
        guard !isRecording else { return lastResult ?? .unavailable }

        isRecording = true
        accelerationSamples.removeAll()
        attitudeSamples.removeAll()

        let start = Date()

        // ── Acelerómetro: captura vibraciones de la superficie ──────────
        motion.accelerometerUpdateInterval = 1.0 / accelerometerHz
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            // Magnitud del vector de aceleración menos la gravedad (~1g en reposo)
            // Usamos la varianza de la magnitud como indicador de rugosidad.
            let mag = sqrt(data.acceleration.x * data.acceleration.x +
                           data.acceleration.y * data.acceleration.y +
                           data.acceleration.z * data.acceleration.z)
            // Restar 1g (gravedad) para obtener solo la aceleración dinámica
            let dynamic = abs(mag - 1.0)
            self.accelerationSamples.append(dynamic)
        }

        // ── Device Motion: captura inclinación (pitch) ──────────────────
        motion.deviceMotionUpdateInterval = 1.0 / 20.0   // 20 Hz es suficiente para slope
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            // pitch en radianes → grados. Valor absoluto (no importa subir o bajar)
            let pitchDeg = abs(data.attitude.pitch * 180.0 / .pi)
            self.attitudeSamples.append(pitchDeg)
        }

        // ── Esperar la ventana ──────────────────────────────────────────
        try? await Task.sleep(nanoseconds: UInt64(windowDuration * 1_000_000_000))

        motion.stopAccelerometerUpdates()
        motion.stopDeviceMotionUpdates()

        let elapsed = Date().timeIntervalSince(start)
        let result = buildResult(elapsed: elapsed)

        isRecording = false
        lastResult = result
        return result
    }

    // MARK: - Continuous mode (para uso futuro en tracking de ruta)

    /// Inicia medición continua. Los resultados se publican en `lastResult` cada `windowDuration` s.
    func startContinuous() {
        guard motion.isAccelerometerAvailable, motion.isDeviceMotionAvailable else { return }
        guard !isRecording else { return }
        isRecording = true
        scheduleNextWindow()
    }

    func stopContinuous() {
        motion.stopAccelerometerUpdates()
        motion.stopDeviceMotionUpdates()
        isRecording = false
    }

    private func scheduleNextWindow() {
        accelerationSamples.removeAll()
        attitudeSamples.removeAll()

        motion.accelerometerUpdateInterval = 1.0 / accelerometerHz
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let mag = sqrt(data.acceleration.x * data.acceleration.x +
                           data.acceleration.y * data.acceleration.y +
                           data.acceleration.z * data.acceleration.z)
            self.accelerationSamples.append(abs(mag - 1.0))
        }

        motion.deviceMotionUpdateInterval = 1.0 / 20.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.attitudeSamples.append(abs(data.attitude.pitch * 180.0 / .pi))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + windowDuration) { [weak self] in
            guard let self, self.isRecording else { return }
            self.motion.stopAccelerometerUpdates()
            self.motion.stopDeviceMotionUpdates()
            self.lastResult = self.buildResult(elapsed: self.windowDuration)
            self.scheduleNextWindow()   // ventana siguiente
        }
    }

    // MARK: - Score calculation

    private func buildResult(elapsed: TimeInterval) -> TerrainMotionResult {
        let accCount  = accelerationSamples.count
        let attiCount = attitudeSamples.count

        // ── Vibration score ─────────────────────────────────────────────
        // Usamos la desviación estándar de las magnitudes dinámicas.
        // SD ≈ 0.0  → superficie muy lisa
        // SD ≈ 0.3+ → superficie muy irregular (adoquín, raíces, etc.)
        let vibration: Double
        if accCount > 5 {
            let mean = accelerationSamples.reduce(0, +) / Double(accCount)
            let variance = accelerationSamples.map { pow($0 - mean, 2) }.reduce(0, +) / Double(accCount)
            let sd = sqrt(variance)
            // Normalizar: 0.0 g SD = 0.0, 0.3 g SD = 1.0 (clamp)
            vibration = (sd / 0.30).clamped(to: 0...1)
        } else {
            vibration = 0
        }

        // ── Slope score ─────────────────────────────────────────────────
        // Usamos la mediana del pitch para robustez ante picos.
        let slope: Double
        if attiCount > 3 {
            let sorted = attitudeSamples.sorted()
            let medianPitch = sorted[sorted.count / 2]
            // Normalizar: 0° = 0.0, maxSlopeDegrees° = 1.0
            slope = (medianPitch / maxSlopeDegrees).clamped(to: 0...1)
        } else {
            slope = 0
        }

        // ── Confidence ──────────────────────────────────────────────────
        // Mínimo esperado: windowDuration × accelerometerHz muestras de accel
        let expectedSamples = windowDuration * accelerometerHz
        let sampleRatio = Double(accCount) / expectedSamples
        let confidence = sampleRatio.clamped(to: 0...1)

        return TerrainMotionResult(
            terrainVibration:  vibration,
            terrainSlope:      slope,
            motionConfidence:  confidence,
            sampleCount:       accCount,
            windowDuration:    elapsed
        )
    }
}

// MARK: - Comparable clamp helper

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
