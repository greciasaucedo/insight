//
//  InsightAppApp.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 17/04/26.
//

import SwiftUI

@main
struct InsightAppApp: App {
    
    @StateObject private var themeManager = ThemeManager()
    
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
            }
            .environmentObject(themeManager)
        }
    }
}
