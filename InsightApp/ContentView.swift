//
//  ContentView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 17/04/26.
//

import SwiftUI

struct ContentView: View {

    // Guarda si el usuario ya terminó el onboarding
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @StateObject private var themeManager = ThemeManager()

    var body: some View {
        if didFinishOnboarding {
            // Si ya terminó → entra directo al mapa
            MapView()
        } else {
            // Si no → muestra onboarding
            NavigationStack {
                WelcomeView()
                    .environmentObject(themeManager)
            }
        }
    }
}

#Preview {
    ContentView()
}
