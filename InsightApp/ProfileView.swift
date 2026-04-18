//
//  ProfileView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 18/04/26.
//

import SwiftUI
import PhotosUI

struct ProfileView: View {

    @EnvironmentObject var themeManager: ThemeManager
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @ObservedObject private var profileService = ProfileService.shared
    @ObservedObject private var authService    = AuthService.shared
    @ObservedObject private var prefs          = UserPreferencesService.shared
    @Environment(\.openURL)   private var openURL
    @Environment(\.dismiss)   private var dismiss

    // Edit info sheet
    @State private var showEditInfo   = false
    @State private var editFirstName  = ""
    @State private var editLastName   = ""
    @State private var editError: String?
    @State private var editLoading    = false
    // Change password sheet
    @State private var showChangePwd   = false
    @State private var newPassword     = ""
    @State private var confirmPassword = ""
    @State private var pwdError: String?
    @State private var pwdLoading      = false
    // Avatar
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var localAvatarImage: UIImage?
    @State private var isUploadingAvatar = false

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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(themeManager.primaryColor)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 16) {

                // Avatar big, centered
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let img = localAvatarImage {
                            Image(uiImage: img)
                                .resizable().scaledToFill()
                        } else if let urlStr = authService.currentUser?.avatarURL,
                                  let url   = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default:                avatarPlaceholder
                                }
                            }
                        } else {
                            avatarPlaceholder
                        }
                    }
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(themeManager.primaryColor.opacity(0.35), lineWidth: 2))
                    .overlay {
                        if isUploadingAvatar {
                            Circle().fill(.black.opacity(0.35))
                            ProgressView().tint(.white)
                        }
                    }
                    .contextMenu {
                        if localAvatarImage != nil || authService.currentUser?.avatarURL != nil {
                            Button(role: .destructive) {
                                localAvatarImage = nil
                                Task { try? await AuthService.shared.removeAvatar() }
                            } label: {
                                Label("Eliminar foto", systemImage: "trash")
                            }
                        }
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(7)
                            .background(themeManager.primaryColor, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
                    }
                    .disabled(isUploadingAvatar)
                }
                .onChange(of: selectedPhoto) { _, item in
                    Task { await handleAvatarSelection(item) }
                }

                // Info rows
                VStack(spacing: 10) {
                    if let user = authService.currentUser {
                        profileInfoRow(icon: "person.fill",
                                       text: user.displayName.isEmpty ? "—" : user.displayName)
                        profileInfoRow(icon: "phone.fill",
                                       text: user.phone.isEmpty ? "—" : user.phone)
                    }
                    if profileService.selectedOptions.isEmpty {
                        profileInfoRow(icon: profileService.currentProfile.icon,
                                       text: profileService.currentProfile.displayName)
                    } else {
                        ForEach(profileService.selectedOptions, id: \.self) { option in
                            profileInfoRow(icon: option.icon, text: option.title)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(18)

            // Pencil edit button top-right
            Button {
                editFirstName = authService.currentUser?.firstName ?? ""
                editLastName  = authService.currentUser?.lastName  ?? ""
                editError     = nil
                showEditInfo  = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.primaryColor)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(12)
        }
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

    private var avatarPlaceholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundStyle(themeManager.primaryColor.opacity(0.45))
    }

    private func profileInfoRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(themeManager.primaryColor)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    @MainActor
    private func handleAvatarSelection(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data  = try? await item.loadTransferable(type: Data.self),
              let uiImg = UIImage(data: data),
              let jpeg  = uiImg.jpegData(compressionQuality: 0.75) else { return }
        localAvatarImage  = uiImg
        isUploadingAvatar = true
        do { _ = try await AuthService.shared.uploadAvatar(jpeg) } catch {}
        isUploadingAvatar = false
    }

    // MARK: - Mobility profile

    private var accessibilitySection: some View {
        profileCard(title: "Perfil de movilidad", icon: "accessibility") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Insight adapta las rutas y penalizaciones según tu perfil.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                ForEach(AccessibilityProfile.allCases) { profile in
                    Button {
                        profileService.setProfile(profile)
                        Task { await SupabaseService.shared.saveProfile(profile) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: profile.icon)
                                .foregroundStyle(profileService.currentProfile == profile
                                                 ? themeManager.primaryColor : .secondary)
                                .frame(width: 24)
                            Text(profile.displayName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: profileService.currentProfile == profile
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(profileService.currentProfile == profile
                                                 ? themeManager.primaryColor : .secondary.opacity(0.4))
                                .font(.system(size: 20))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        profileCard(title: "Preferencias", icon: "slider.horizontal.3") {
            VStack(spacing: 16) {
                ToggleRow(
                    title: "Alto contraste",
                    icon: "circle.lefthalf.filled",
                    isOn: Binding(
                        get: { themeManager.selectedMode == .highContrast },
                        set: { themeManager.selectedMode = $0 ? .highContrast : .defaultMode }
                    ),
                    tint: themeManager.primaryColor
                )
                ToggleRow(title: "Indicaciones por voz",
                          icon: "speaker.wave.2.fill",
                          isOn: $prefs.voiceGuidanceEnabled,
                          tint: themeManager.primaryColor)
                ToggleRow(title: "Vibración",
                          icon: "iphone.radiowaves.left.and.right",
                          isOn: $prefs.hapticsEnabled,
                          tint: themeManager.primaryColor)
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        profileCard(title: "Permisos", icon: "lock.shield") {
            VStack(spacing: 14) {
                PermissionStatusRow(title: "Ubicación", icon: "location.fill",
                                    status: "Activado", statusColor: .green)
                PermissionStatusRow(title: "Cámara", icon: "camera.fill",
                                    status: "Activado", statusColor: .green)
                PermissionStatusRow(title: "Movimiento", icon: "figure.walk.motion",
                                    status: "Activado", statusColor: .green)
                Button {
                    if let url = URL(string: "app-settings:") { openURL(url) }
                } label: {
                    Text("Abrir configuración")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(themeManager.primaryColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        profileCard(title: "Cuenta", icon: "person.text.rectangle") {
            VStack(spacing: 14) {
                Button {
                    editFirstName = authService.currentUser?.firstName ?? ""
                    editLastName  = authService.currentUser?.lastName  ?? ""
                    editError     = nil
                    showEditInfo  = true
                } label: {
                    accountRow(title: "Editar información", icon: "pencil")
                }

                Button {
                    newPassword = ""; confirmPassword = ""; pwdError = nil
                    showChangePwd = true
                } label: {
                    accountRow(title: "Cambiar contraseña", icon: "key.fill")
                }

                Button {
                    Task {
                        await AuthService.shared.signOut()
                        PersistenceService.shared.clearAll()
                        didFinishOnboarding = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.portrait.and.arrow.right").foregroundStyle(.red)
                        Text("Cerrar sesión")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(isPresented: $showEditInfo) {
            NavigationStack {
                Form {
                    Section("Nombre") {
                        TextField("Nombre",   text: $editFirstName)
                        TextField("Apellido", text: $editLastName)
                    }
                    if let err = editError {
                        Section { Text(err).foregroundStyle(.red).font(.system(size: 13)) }
                    }
                }
                .navigationTitle("Editar información")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { showEditInfo = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if editLoading { ProgressView() } else {
                            Button("Guardar") {
                                let fn = editFirstName.trimmingCharacters(in: .whitespaces)
                                let ln = editLastName.trimmingCharacters(in: .whitespaces)
                                guard !fn.isEmpty, !ln.isEmpty else {
                                    editError = "Los campos no pueden estar vacíos."; return
                                }
                                editLoading = true
                                Task {
                                    do {
                                        try await AuthService.shared.updateInfo(firstName: fn, lastName: ln)
                                        showEditInfo = false
                                    } catch { editError = error.localizedDescription }
                                    editLoading = false
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showChangePwd) {
            NavigationStack {
                Form {
                    Section("Nueva contraseña") {
                        SecureField("Mínimo 8 caracteres", text: $newPassword)
                        SecureField("Confirmar contraseña", text: $confirmPassword)
                    }
                    if let err = pwdError {
                        Section { Text(err).foregroundStyle(.red).font(.system(size: 13)) }
                    }
                }
                .navigationTitle("Cambiar contraseña")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { showChangePwd = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if pwdLoading { ProgressView() } else {
                            Button("Guardar") {
                                guard newPassword.count >= 8 else {
                                    pwdError = "La contraseña debe tener al menos 8 caracteres."; return
                                }
                                guard newPassword == confirmPassword else {
                                    pwdError = "Las contraseñas no coinciden."; return
                                }
                                pwdLoading = true
                                Task {
                                    do {
                                        try await AuthService.shared.changePassword(newPassword: newPassword)
                                        showChangePwd = false
                                    } catch { pwdError = error.localizedDescription }
                                    pwdLoading = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Visual accessibility

    private var colorAccessibilitySection: some View {
        profileCard(title: "Accesibilidad visual", icon: "paintpalette.fill") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Elige una paleta que haga la interfaz más cómoda y legible según tu visión.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                ForEach(ColorAccessibilityMode.allCases, id: \.self) { mode in
                    Button { themeManager.selectedMode = mode } label: {
                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                ForEach(0..<3, id: \.self) { i in
                                    Circle().fill(mode.previewColors[i]).frame(width: 16, height: 16)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                                Text(mode.description)
                                    .font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: themeManager.selectedMode == mode
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(themeManager.selectedMode == mode
                                                 ? themeManager.primaryColor : .secondary.opacity(0.4))
                                .font(.system(size: 20))
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    // MARK: - Card builder

    private func profileCard<Content: View>(title: String, icon: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(themeManager.primaryColor)
                Text(title).font(.system(size: 18, weight: .bold))
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color.white.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private func accountRow(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(themeManager.primaryColor)
            Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Supporting Views

struct ToggleRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
            Text(title).font(.system(size: 16, weight: .medium))
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(tint)
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
            Image(systemName: icon).foregroundStyle(statusColor).frame(width: 24)
            Text(title).font(.system(size: 16, weight: .medium))
            Spacer()
            Text(status)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 10).padding(.vertical, 6)
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
                            .padding(.horizontal, 12).padding(.vertical, 8)
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

// MARK: - Color Mode Enum

enum ColorAccessibilityMode: String, CaseIterable {
    case defaultMode  = "default"
    case deuteranopia = "deuteranopia"
    case protanopia   = "protanopia"
    case tritanopia   = "tritanopia"
    case highContrast = "highContrast"

    var title: String {
        switch self {
        case .defaultMode:  return "Estándar"
        case .deuteranopia: return "Verde/Rojo accesible"
        case .protanopia:   return "Contraste cálido"
        case .tritanopia:   return "Azul/amarillo accesible"
        case .highContrast: return "Alto contraste"
        }
    }

    var description: String {
        switch self {
        case .defaultMode:  return "Paleta original de Insight."
        case .deuteranopia: return "Mejor diferenciación para dificultad verde-rojo."
        case .protanopia:   return "Reduce confusión entre tonos rojizos."
        case .tritanopia:   return "Optimiza contraste entre azules y amarillos."
        case .highContrast: return "Mayor legibilidad en toda la interfaz."
        }
    }

    var previewColors: [Color] {
        switch self {
        case .defaultMode:
            return [Color(red: 136/255, green: 205/255, blue: 212/255),
                    Color(red: 255/255, green: 214/255, blue: 102/255),
                    Color(red: 160/255, green: 160/255, blue: 165/255)]
        case .deuteranopia: return [.blue, .orange, .gray]
        case .protanopia:   return [.cyan, .yellow, .gray]
        case .tritanopia:   return [.purple, .orange, .gray]
        case .highContrast: return [.black, .white, .yellow]
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(ThemeManager())
}
