//
//  AuthService.swift
//  InsightApp
//
//  Supabase GoTrue auth via URLSession — no SDK needed.
//  Uses a "virtual email" (phone@insight.app) so users log in with phone+password.
//
//  REQUIRED — run once in Supabase Auth Settings (dashboard):
//    Authentication > Configuration > Disable "Confirm email"
//

import Foundation

// MARK: - Error

enum AuthError: LocalizedError {
    case userAlreadyExists
    case invalidCredentials
    case emailNotConfirmed
    case notAuthenticated
    case networkError
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .userAlreadyExists:  return "Este número ya tiene una cuenta. Inicia sesión."
        case .invalidCredentials: return "Teléfono o contraseña incorrectos."
        case .emailNotConfirmed:  return "Desactiva 'Confirm email' en Supabase Auth Settings."
        case .notAuthenticated:   return "No hay sesión activa."
        case .networkError:       return "Error de red. Verifica tu conexión."
        case .invalidResponse:    return "Respuesta inesperada del servidor."
        case .serverError(let m): return m
        }
    }
}

// MARK: - Service

final class AuthService: ObservableObject {
    static let shared = AuthService()
    private init() { restoreSession() }

    @Published private(set) var currentUser: AuthUser?
    private(set) var accessToken: String?
    private var refreshToken: String?

    var isAuthenticated: Bool { accessToken != nil && currentUser != nil }

    private let defaults     = UserDefaults.standard
    private let accessKey    = "insight.auth.accessToken"
    private let refreshKey   = "insight.auth.refreshToken"
    private let userKey      = "insight.auth.user"

    // MARK: Sign Up

    @MainActor
    func signUp(firstName: String, lastName: String, phone: String, password: String) async throws {
        let body: [String: Any] = [
            "email":    virtualEmail(phone),
            "password": password,
            "data": ["first_name": firstName, "last_name": lastName, "phone": phone]
        ]
        let data = try await authRequest(path: "/auth/v1/signup", method: "POST", body: body, token: nil)
        try parseSession(data, phoneFallback: phone)
    }

    // MARK: Sign In

    @MainActor
    func signIn(phone: String, password: String) async throws {
        let body: [String: Any] = [
            "email":    virtualEmail(phone),
            "password": password
        ]
        let data = try await authRequest(
            path: "/auth/v1/token?grant_type=password", method: "POST", body: body, token: nil
        )
        try parseSession(data, phoneFallback: phone)
    }

    // MARK: Sign Out

    @MainActor
    func signOut() async {
        if let token = accessToken {
            _ = try? await authRequest(path: "/auth/v1/logout", method: "POST", body: [:], token: token)
        }
        clearSession()
    }

    // MARK: Update display name

    @MainActor
    func updateInfo(firstName: String, lastName: String) async throws {
        guard let token = accessToken, let user = currentUser else { throw AuthError.notAuthenticated }
        let body: [String: Any] = [
            "data": ["first_name": firstName, "last_name": lastName, "phone": user.phone]
        ]
        let data = try await authRequest(path: "/auth/v1/user", method: "PUT", body: body, token: token)
        try parseSession(data, phoneFallback: user.phone)
    }

    // MARK: Change password

    @MainActor
    func changePassword(newPassword: String) async throws {
        guard let token = accessToken, let user = currentUser else { throw AuthError.notAuthenticated }
        let data = try await authRequest(
            path: "/auth/v1/user", method: "PUT",
            body: ["password": newPassword], token: token
        )
        try parseSession(data, phoneFallback: user.phone)
    }

    // MARK: Session persistence

    func clearSession() {
        accessToken  = nil
        refreshToken = nil
        currentUser  = nil
        [accessKey, refreshKey, userKey].forEach { defaults.removeObject(forKey: $0) }
    }

    private func restoreSession() {
        accessToken  = defaults.string(forKey: accessKey)
        refreshToken = defaults.string(forKey: refreshKey)
        if let data = defaults.data(forKey: userKey),
           let user = try? JSONDecoder().decode(AuthUser.self, from: data) {
            currentUser = user
        }
    }

    // MARK: Helpers

    private func virtualEmail(_ phone: String) -> String {
        let clean = phone.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map { String($0) }
            .joined()
        return "\(clean)@insight.app"
    }

    private func parseSession(_ data: Data, phoneFallback: String) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.invalidResponse
        }
        // Map GoTrue error codes → typed errors
        if let code = json["error_code"] as? String {
            switch code {
            case "user_already_exists":  throw AuthError.userAlreadyExists
            case "invalid_credentials":  throw AuthError.invalidCredentials
            case "email_not_confirmed":  throw AuthError.emailNotConfirmed
            default:
                let msg = json["msg"] as? String ?? json["message"] as? String ?? code
                throw AuthError.serverError(msg)
            }
        }
        // Some errors come back without error_code
        if json["access_token"] == nil,
           let msg = json["msg"] as? String ?? json["message"] as? String {
            throw AuthError.serverError(msg)
        }
        guard
            let token   = json["access_token"] as? String,
            let refresh = json["refresh_token"] as? String,
            let userJson = json["user"] as? [String: Any],
            let userId   = userJson["id"] as? String
        else { throw AuthError.invalidResponse }

        let meta  = userJson["user_metadata"] as? [String: Any] ?? [:]
        let user  = AuthUser(
            id:        userId,
            firstName: meta["first_name"] as? String ?? "",
            lastName:  meta["last_name"]  as? String ?? "",
            phone:     meta["phone"]      as? String ?? phoneFallback
        )
        accessToken  = token
        refreshToken = refresh
        currentUser  = user
        defaults.set(token, forKey: accessKey)
        defaults.set(refresh, forKey: refreshKey)
        if let encoded = try? JSONEncoder().encode(user) {
            defaults.set(encoded, forKey: userKey)
        }
    }

    @discardableResult
    private func authRequest(
        path: String, method: String, body: [String: Any], token: String?
    ) async throws -> Data {
        let url = URL(string: SupabaseConfig.projectURL + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if !body.isEmpty { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}
