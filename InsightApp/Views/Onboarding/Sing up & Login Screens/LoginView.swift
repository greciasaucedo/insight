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
    
    let primaryColor = Color(red: 136/255, green: 205/255, blue: 212/255) // #88CDD4
    
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
                    
                    VStack(alignment: .leading, spacing: 8) {
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
                            
                            Button(action: {
                                showPassword.toggle()
                            }) {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundStyle(primaryColor)
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
                    Text("Iniciar sesión")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(primaryColor)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                
                HStack(spacing: 4) {
                    Text("¿No tienes cuenta?")
                        .foregroundStyle(.secondary)
                    
                    NavigationLink(destination: SignUpView()){
                        Text("Crear cuenta")
                            .fontWeight(.semibold)
                            .foregroundStyle(primaryColor)
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
