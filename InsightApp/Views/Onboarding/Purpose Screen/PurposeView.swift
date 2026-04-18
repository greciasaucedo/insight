//
//  PurposeView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 17/04/26.
//

import SwiftUI

struct PurposeView: View {
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(spacing: 28) {
            
            Spacer()
            
            VStack(spacing: 18) {
                Text("¿Por qué Insight?")
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                Text("Insight te ayuda a entender qué rutas son más accesibles, cómodas y seguras según la experiencia real del camino.")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            
            VStack(spacing: 16) {
                PurposePointView(
                    icon: "figure.roll",
                    text: "Navega con mayor confianza"
                )
                
                PurposePointView(
                    icon: "map",
                    text: "Entiende cómo es el camino"
                )
                
                PurposePointView(
                    icon: "accessibility",
                    text: "Elige rutas que se adapten a ti"
                )
            }
            .padding(.horizontal, 24)
            
            Spacer()
                .frame(height: 60)
            
            NavigationLink {
                SignUpView()
            } label: {
                Text("Continuar")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.primaryColor)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 4)
            
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    NavigationStack {
        PurposeView()
    }
}
