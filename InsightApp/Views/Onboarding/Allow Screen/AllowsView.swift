//
//  AllowsView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 17/04/26.
//

import SwiftUI
import CoreLocation
import AVFoundation
import CoreMotion

struct AllowsView: View {

    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @EnvironmentObject var themeManager: ThemeManager

    private let locationManager = CLLocationManager()
    private let motionManager   = CMMotionActivityManager()

    var body: some View {
        VStack(spacing: 24) {
            
            Spacer()
                .frame(height: 30)
            
            VStack(spacing: 12) {
                Text("Antes de comenzar")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                
                Text("Insight necesita algunos permisos para ayudarte a entender mejor tu recorrido.")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 20)
            .padding(.bottom, 10)
            
            VStack(spacing: 14) {
                
                AllowCardView(
                    icon: "location.fill",
                    title: "Ubicación",
                    description: "Para mostrar tu posición, detectar rutas cercanas y ayudarte a navegar por la ciudad."
                )
                
                AllowCardView(
                    icon: "figure.walk.motion",
                    title: "Movimiento",
                    description: "Para interpretar vibración, inclinación y otros cambios en el trayecto."
                )
                
                AllowCardView(
                    icon: "camera.fill",
                    title: "Cámara",
                    description: "Para analizar el entorno y detectar obstáculos o condiciones del camino."
                )
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            VStack(spacing: 12) {
                
                Button(action: {
                    requestAllPermissions()
                    didFinishOnboarding = true
                }) {
                    Text("Permitir acceso")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(themeManager.primaryColor)
                        .cornerRadius(16)
                }

                Button(action: {
                    didFinishOnboarding = true
                }) {
                    Text("Ahora no")
                        .font(.headline)
                        .foregroundColor(themeManager.primaryColor)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
    }

    private func requestAllPermissions() {
        locationManager.requestWhenInUseAuthorization()
        AVCaptureDevice.requestAccess(for: .video) { _ in }
        if CMMotionActivityManager.isActivityAvailable() {
            motionManager.queryActivityStarting(from: Date(), to: Date(), to: .main) { _, _ in }
        }
    }
}

#Preview {
    AllowsView()
}
