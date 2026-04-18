//
//  SignUpView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 18/04/26.
//
import SwiftUI

struct SignUpView: View {

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phoneNumber = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showErrors = false
    @State private var navigate = false
    @State private var isLoading = false
    @State private var authError: String?
    @EnvironmentObject var themeManager: ThemeManager

    private var isFirstNameValid: Bool { !firstName.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isLastNameValid:  Bool { !lastName.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isPhoneValid:     Bool { phoneNumber.filter(\.isNumber).count >= 10 }
    private var isPasswordValid:  Bool { password.count >= 8 }
    private var isFormValid:      Bool { isFirstNameValid && isLastNameValid && isPhoneValid && isPasswordValid }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                Spacer()
                    .frame(height: 30)

                VStack(spacing: 12) {
                    Text("Crea tu cuenta")
                        .font(.system(size: 32, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text("Completa tus datos para comenzar a usar Insight.")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 10)

                VStack(spacing: 16) {

                    // Nombre
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nombre")
                            .font(.system(size: 15, weight: .semibold))

                        TextField("Escribe tu nombre", text: $firstName)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                            .textContentType(.givenName)

                        if showErrors && !isFirstNameValid {
                            Text("El nombre no puede estar vacío.")
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                        }
                    }

                    // Apellido
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apellido")
                            .font(.system(size: 15, weight: .semibold))

                        TextField("Escribe tu apellido", text: $lastName)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                            .textContentType(.familyName)

                        if showErrors && !isLastNameValid {
                            Text("El apellido no puede estar vacío.")
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                        }
                    }

                    // Teléfono
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
                            Text("Ingresa un número de al menos 10 dígitos.")
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                        }
                    }

                    // Contraseña
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Contraseña")
                            .font(.system(size: 15, weight: .semibold))

                        HStack {
                            Group {
                                if showPassword {
                                    TextField("Crea una contraseña", text: $password)
                                } else {
                                    SecureField("Crea una contraseña", text: $password)
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

                NavigationLink(destination: PersonalizationView(), isActive: $navigate) {
                    EmptyView()
                }
                .hidden()

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
                            try await AuthService.shared.signUp(
                                firstName: firstName.trimmingCharacters(in: .whitespaces),
                                lastName:  lastName.trimmingCharacters(in: .whitespaces),
                                phone:     phoneNumber,
                                password:  password
                            )
                            navigate = true
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
                            Text("Continuar").font(.headline)
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
                    Text("¿Ya tienes cuenta?")
                        .foregroundStyle(.secondary)

                    NavigationLink(destination: LoginView()) {
                        Text("Inicia sesión")
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
    NavigationStack {
        SignUpView()
    }
}
