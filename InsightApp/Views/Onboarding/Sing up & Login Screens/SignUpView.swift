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
    @EnvironmentObject var themeManager: ThemeManager
    
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nombre")
                            .font(.system(size: 15, weight: .semibold))
                        
                        TextField("Escribe tu nombre", text: $firstName)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                            .textContentType(.givenName)
                    }
                    
                    // Apellido
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Apellido")
                            .font(.system(size: 15, weight: .semibold))
                        
                        TextField("Escribe tu apellido", text: $lastName)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                            .textContentType(.familyName)
                    }
                    
                    // Teléfono
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Número de teléfono")
                            .font(.system(size: 15, weight: .semibold))
                        
                        TextField("Escribe tu número", text: $phoneNumber)
                            .keyboardType(.phonePad)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                            .textContentType(.telephoneNumber)
                    }
                    
                    // Contraseña
                    VStack(alignment: .leading, spacing: 8) {
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
                            
                            Button(action: {
                                showPassword.toggle()
                            }) {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundStyle(themeManager.primaryColor)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                
                    NavigationLink(destination: PersonalizationView()){
                    Text("Continuar")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(themeManager.primaryColor)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                
                HStack(spacing: 4) {
                    Text("¿Ya tienes cuenta?")
                        .foregroundStyle(.secondary)
                    
                    NavigationLink(destination: LoginView()){
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
