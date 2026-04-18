//
//  PermissionStatusService.swift
//  InsightApp
//
//  FIX 1: PermissionStatusService ahora es una clase normal — NO ObservableObject.
//         Los @Published no funcionan sin Combine y causan el error de módulo.
//         En su lugar, ProfileView llama refresh() en .onAppear y lee las
//         propiedades directamente (se re-renderiza vía @State local).
//
//  FIX 2: Switch exhaustivo — PermissionState cubre todos los casos de
//         CLAuthorizationStatus, AVAuthorizationStatus y CMAuthorizationStatus.
//
//  FIX 3: CMMotionActivityManager import correcto para authorizationStatus.
//

import SwiftUI
import CoreLocation
import AVFoundation
import CoreMotion

// MARK: - PermissionState

enum PermissionState {
    case granted
    case denied
    case restricted
    case limited
    case notDetermined

    var label: String {
        switch self {
        case .granted:       return "Activado"
        case .denied:        return "Denegado"
        case .restricted:    return "Restringido"
        case .limited:       return "Limitado"
        case .notDetermined: return "No solicitado"
        }
    }

    var color: Color {
        switch self {
        case .granted:             return .green
        case .limited:             return .orange
        case .notDetermined:       return .secondary
        case .denied, .restricted: return .red
        }
    }

    var icon: String {
        switch self {
        case .granted:       return "checkmark.circle.fill"
        case .denied:        return "xmark.circle.fill"
        case .restricted:    return "minus.circle.fill"
        case .limited:       return "exclamationmark.circle.fill"
        case .notDetermined: return "questionmark.circle"
        }
    }
}

// MARK: - PermissionStatusService

/// Servicio sin @Published para evitar dependencia de Combine.
/// ProfileView usa @State local y llama refresh() en onAppear.
final class PermissionStatusService {
    static let shared = PermissionStatusService()
    private init() {}

    private let locationManager = CLLocationManager()

    // MARK: Snapshot (call refresh() before reading)

    private(set) var locationState: PermissionState = .notDetermined
    private(set) var cameraState:   PermissionState = .notDetermined
    private(set) var motionState:   PermissionState = .notDetermined

    /// Lee el estado real de los tres permisos.
    func refresh() {
        locationState = currentLocationState()
        cameraState   = currentCameraState()
        motionState   = currentMotionState()
    }

    // MARK: Location

    private func currentLocationState() -> PermissionState {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if #available(iOS 14.0, *) {
                return locationManager.accuracyAuthorization == .reducedAccuracy ? .limited : .granted
            }
            return .granted
        case .denied:        return .denied
        case .restricted:    return .restricted
        case .notDetermined: return .notDetermined
        @unknown default:    return .notDetermined   // FIX: switch exhaustivo
        }
    }

    // MARK: Camera

    private func currentCameraState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    return .granted
        case .denied:        return .denied
        case .restricted:    return .restricted
        case .notDetermined: return .notDetermined
        @unknown default:    return .notDetermined   // FIX: switch exhaustivo
        }
    }

    // MARK: Motion

    private func currentMotionState() -> PermissionState {
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized:    return .granted
        case .denied:        return .denied
        case .restricted:    return .restricted
        case .notDetermined: return .notDetermined
        @unknown default:    return .notDetermined   // FIX: switch exhaustivo
        }
    }
}

// MARK: - PermissionStatusSection

/// Vista que reemplaza permissionsSection en ProfileView.
/// Usa @State local en lugar de @ObservedObject para evitar
/// la dependencia de ObservableObject/Combine.
///
/// INTEGRACIÓN en ProfileView.swift:
///
/// 1. Reemplazar el contenido de `permissionsSection`:
///
///    private var permissionsSection: some View {
///        PermissionStatusSection()
///    }
///
/// 2. En el ScrollView del body, agregar:
///
///    .onAppear { PermissionStatusService.shared.refresh() }
///
struct PermissionStatusSection: View {
    // FIX: @State local + onAppear en lugar de @ObservedObject
    @State private var locationState: PermissionState = .notDetermined
    @State private var cameraState:   PermissionState = .notDetermined
    @State private var motionState:   PermissionState = .notDetermined

    @Environment(\.openURL) private var openURL
    let teal = Color(red: 136/255, green: 205/255, blue: 212/255)

    var body: some View {
        profileCardStyle(title: "Permisos", icon: "lock.shield") {
            VStack(spacing: 14) {
                PermissionRow(
                    title:  "Ubicación",
                    icon:   "location.fill",
                    state:  locationState,
                    detail: locationDetail(locationState)
                )
                PermissionRow(
                    title:  "Cámara",
                    icon:   "camera.fill",
                    state:  cameraState,
                    detail: cameraDetail(cameraState)
                )
                PermissionRow(
                    title:  "Movimiento",
                    icon:   "figure.walk.motion",
                    state:  motionState,
                    detail: motionDetail(motionState)
                )

                Divider()

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if hasDenied {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 13)).foregroundColor(.red)
                            Text("Activar permisos denegados")
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(.red)
                        } else {
                            Text("Administrar permisos")
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(teal)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            PermissionStatusService.shared.refresh()
            locationState = PermissionStatusService.shared.locationState
            cameraState   = PermissionStatusService.shared.cameraState
            motionState   = PermissionStatusService.shared.motionState
        }
    }

    private var hasDenied: Bool {
        locationState == .denied || cameraState == .denied || motionState == .denied
    }

    // MARK: Detail strings

    private func locationDetail(_ s: PermissionState) -> String {
        switch s {
        case .granted:       return "Precisión completa activa"
        case .limited:       return "Precisión reducida — activa precisión completa en Ajustes"
        case .denied:        return "Activa la ubicación para usar el mapa"
        case .restricted:    return "Restringida por política del dispositivo"
        case .notDetermined: return "Requerida para funcionalidades del mapa"
        }
    }

    private func cameraDetail(_ s: PermissionState) -> String {
        switch s {
        case .granted:       return "Disponible para escanear zonas"
        case .denied:        return "Activa la cámara para escanear el terreno"
        case .restricted:    return "Restringida por política del dispositivo"
        case .notDetermined: return "Requerida para el escaneo de terreno"
        case .limited:       return "Acceso limitado a la cámara"
        }
    }

    private func motionDetail(_ s: PermissionState) -> String {
        switch s {
        case .granted:       return "Vibración e inclinación activas"
        case .denied:        return "Activa el movimiento para medir el terreno"
        case .restricted:    return "Restringido por política del dispositivo"
        case .notDetermined: return "Requerido para medir vibración e inclinación"
        case .limited:       return "Acceso limitado a sensores de movimiento"
        }
    }

    // MARK: Card style (replica profileCard de ProfileView)

    private func profileCardStyle<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(teal)
                Text(title)
                    .font(.system(size: 17, weight: .bold))
            }
            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - PermissionRow

struct PermissionRow: View {
    let title: String
    let icon: String
    let state: PermissionState
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(state.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Text(detail)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: state.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(state.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundColor(state.color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(state.color.opacity(0.10), in: Capsule())
        }
    }
}
