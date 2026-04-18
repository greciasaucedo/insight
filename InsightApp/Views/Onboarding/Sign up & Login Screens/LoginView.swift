//
//  LoginView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 17/04/26.
//
import SwiftUI

struct LoginView: View {

    @State private var phoneNumber = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showErrors = false
    @State private var isLoading = false
    @State private var authError: String?
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @EnvironmentObject var themeManager: ThemeManager

    private var isPhoneValid:    Bool { !phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isPasswordValid: Bool { password.count >= 8 }
    private var isFormValid:     Bool { isPhoneValid && isPasswordValid }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                Spacer()
                    .frame(height: 110)

                VStack(spacing: 12) {
                    Text("Bienvenido de nuevo")
                        .font(.system(size: 32, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text("Inicia sesión para continuar usando Insight.")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 10)

                VStack(spacing: 16) {

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Número de teléfono")
                            .font(.system(size: 15, weight: .semibold))

                        TextField("Escribe tu número", text: $phoneNumber)
                            .keyboardType(.phonePad)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                            .textContentType(.telephoneNumber)

                        if showErrors && !isPhoneValid {
                            Text("El número de teléfono no puede estar vacío.")
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Contraseña")
                            .font(.system(size: 15, weight: .semibold))

                        HStack {
                            Group {
                                if showPassword {
                                    TextField("Escribe tu contraseña", text: $password)
                                } else {
                                    SecureField("Escribe tu contraseña", text: $password)
                                }
                            }

                            Button(action: { showPassword.toggle() }) {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundStyle(themeManager.primaryColor)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)

                        if showErrors && !isPasswordValid {
                            Text("La contraseña debe tener al menos 8 caracteres.")
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)

                if let err = authError {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button(action: {
                    guard isFormValid else { showErrors = true; return }
                    authError = nil
                    isLoading = true
                    Task {
                        do {
                            try await AuthService.shared.signIn(phone: phoneNumber, password: password)
                            didFinishOnboarding = true
                        } catch {
                            authError = error.localizedDescription
                        }
                        isLoading = false
                    }
                }) {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Iniciar sesión").font(.headline)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.primaryColor)
                    .cornerRadius(16)
                    .opacity(isFormValid ? 1 : 0.5)
                }
                .disabled(isLoading)
                .padding(.horizontal, 24)
                .padding(.top, 8)

                HStack(spacing: 4) {
                    Text("¿No tienes cuenta?")
                        .foregroundStyle(.secondary)

                    NavigationLink(destination: SignUpView()) {
                        Text("Crear cuenta")
                            .fontWeight(.semibold)
                            .foregroundStyle(themeManager.primaryColor)
                    }
                }
                .font(.system(size: 16))
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    LoginView()
}
