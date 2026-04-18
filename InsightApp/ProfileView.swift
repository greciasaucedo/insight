//
//  ProfileView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 18/04/26.
//

import SwiftUI
import UIKit

struct ProfileView: View {

    @EnvironmentObject var themeManager: ThemeManager
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @State private var highContrast = true
    @State private var voiceGuidance = false
    @State private var hapticFeedback = true
    @State private var selectedColorMode: ColorAccessibilityMode = .defaultMode
    @State private var selectedProfile: AccessibilityProfile = ProfileService.shared.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    accessibilitySection
                    preferencesSection
                    permissionsSection
                    accountSection
                    colorAccessibilitySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Perfil")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 14) {
            Image(systemName: selectedProfile.icon)
                .font(.system(size: 72))
                .foregroundStyle(themeManager.primaryColor)

            VStack(spacing: 4) {
                Text("Perfil activo")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(selectedProfile.displayName)
                    .font(.system(size: 26, weight: .bold))
            }

            Text("Administra tu información, preferencias y accesibilidad en Insight.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var colorAccessibilitySection: some View {
        profileCard(title: "Accesibilidad visual", icon: "paintpalette.fill") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Elige una paleta que haga la interfaz más cómoda y legible según tu visión.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                ForEach(ColorAccessibilityMode.allCases, id: \.self) { mode in
                    Button(action: {
                        selectedColorMode = mode
                    }) {
                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(mode.previewColors[0])
                                    .frame(width: 16, height: 16)

                                Circle()
                                    .fill(mode.previewColors[1])
                                    .frame(width: 16, height: 16)

                                Circle()
                                    .fill(mode.previewColors[2])
                                    .frame(width: 16, height: 16)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Text(mode.description)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: selectedColorMode == mode ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedColorMode == mode ? themeManager.primaryColor : .secondary.opacity(0.4))
                                .font(.system(size: 20))
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private var accessibilitySection: some View {
        profileCard(title: "Perfil de movilidad", icon: "accessibility") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Insight adapta las rutas y penalizaciones según tu perfil.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                ForEach(AccessibilityProfile.allCases) { profile in
                    Button(action: {
                        selectedProfile = profile
                        ProfileService.shared.current = profile
                        Task { await SupabaseService.shared.saveProfile(profile) }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: profile.icon)
                                .foregroundStyle(selectedProfile == profile ? themeManager.primaryColor : .secondary)
                                .frame(width: 24)
                            Text(profile.displayName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: selectedProfile == profile ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedProfile == profile ? themeManager.primaryColor : .secondary.opacity(0.4))
                                .font(.system(size: 20))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var preferencesSection: some View {
        profileCard(title: "Preferencias", icon: "slider.horizontal.3") {
            VStack(spacing: 16) {
                ToggleRow(title: "Alto contraste", icon: "circle.lefthalf.filled", isOn: $highContrast, tint: themeManager.primaryColor)
                ToggleRow(title: "Indicaciones por voz", icon: "speaker.wave.2.fill", isOn: $voiceGuidance, tint: themeManager.primaryColor)
                ToggleRow(title: "Vibración", icon: "iphone.radiowaves.left.and.right", isOn: $hapticFeedback, tint: themeManager.primaryColor)
            }
        }
    }

    private var permissionsSection: some View {
        profileCard(title: "Permisos", icon: "lock.shield") {
            VStack(spacing: 14) {
                PermissionStatusRow(title: "Ubicación", icon: "location.fill", status: "Activado", statusColor: .green)
                PermissionStatusRow(title: "Cámara", icon: "camera.fill", status: "Activado", statusColor: .green)
                PermissionStatusRow(title: "Movimiento", icon: "figure.walk.motion", status: "Activado", statusColor: .green)

                Button(action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("Abrir configuración")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(themeManager.primaryColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var accountSection: some View {
        profileCard(title: "Cuenta", icon: "person.text.rectangle") {
            VStack(spacing: 14) {
                Button(action: {}) {
                    accountRow(title: "Editar información", icon: "pencil")
                }

                Button(action: {}) {
                    accountRow(title: "Cambiar contraseña", icon: "key.fill")
                }

                Button(action: {
                    PersistenceService.shared.clearAll()
                    didFinishOnboarding = false
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(.red)
                        Text("Cerrar sesión")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func profileCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(themeManager.primaryColor)
                Text(title)
                    .font(.system(size: 18, weight: .bold))
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private func accountRow(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(themeManager.primaryColor)
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ToggleRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 16, weight: .medium))

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(tint)
        }
    }
}

struct PermissionStatusRow: View {
    let title: String
    let icon: String
    let status: String
    let statusColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(statusColor)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 16, weight: .medium))

            Spacer()

            Text(status)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
    }
}

struct FlexibleTagView: View {
    let tags: [String]
    let primaryColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(chunkedTags(), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(primaryColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(primaryColor.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    private func chunkedTags() -> [[String]] {
        stride(from: 0, to: tags.count, by: 2).map {
            Array(tags[$0..<min($0 + 2, tags.count)])
        }
    }
}

enum ColorAccessibilityMode: CaseIterable {
    case defaultMode
    case deuteranopia
    case protanopia
    case tritanopia
    case highContrast

    var title: String {
        switch self {
        case .defaultMode:
            return "Estándar"
        case .deuteranopia:
            return "Verde/Rojo accesible"
        case .protanopia:
            return "Contraste cálido"
        case .tritanopia:
            return "Azul/amarillo accesible"
        case .highContrast:
            return "Alto contraste"
        }
    }

    var description: String {
        switch self {
        case .defaultMode:
            return "Paleta original de Insight."
        case .deuteranopia:
            return "Mejor diferenciación para dificultad verde-rojo."
        case .protanopia:
            return "Reduce confusión entre tonos rojizos."
        case .tritanopia:
            return "Optimiza contraste entre azules y amarillos."
        case .highContrast:
            return "Mayor legibilidad en toda la interfaz."
        }
    }

    var previewColors: [Color] {
        switch self {
        case .defaultMode:
            return [
                Color(red: 136/255, green: 205/255, blue: 212/255),
                Color(red: 255/255, green: 214/255, blue: 102/255),
                Color(red: 160/255, green: 160/255, blue: 165/255)
            ]
        case .deuteranopia:
            return [
                Color.blue,
                Color.orange,
                Color.gray
            ]
        case .protanopia:
            return [
                Color.cyan,
                Color.yellow,
                Color.gray
            ]
        case .tritanopia:
            return [
                Color.purple,
                Color.orange,
                Color.gray
            ]
        case .highContrast:
            return [
                Color.black,
                Color.white,
                Color.yellow
            ]
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(ThemeManager())
}
