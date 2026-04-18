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
    @StateObject private var profileService = ProfileService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .environmentObject(profileService)
        }
    }
}
