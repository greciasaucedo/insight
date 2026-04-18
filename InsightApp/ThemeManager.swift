//
//  ThemeManager.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 18/04/26.
//
import SwiftUI
import Combine

final class ThemeManager: ObservableObject {
    @Published var selectedMode: ColorAccessibilityMode = .defaultMode
    static let shared = ThemeManager()

    var primaryColor: Color {
        switch selectedMode {
        case .defaultMode:
            return Color(red: 136/255, green: 205/255, blue: 212/255)
        case .deuteranopia:
            return .blue
        case .protanopia:
            return .cyan
        case .tritanopia:
            return .purple
        case .highContrast:
            return .black
        }
    }

    var secondaryColor: Color {
        switch selectedMode {
        case .defaultMode:
            return Color(red: 255/255, green: 214/255, blue: 102/255)
        case .deuteranopia:
            return .orange
        case .protanopia:
            return .yellow
        case .tritanopia:
            return .orange
        case .highContrast:
            return .yellow
        }
    }

    var neutralColor: Color {
        switch selectedMode {
        case .highContrast:
            return .white
        default:
            return Color(red: 160/255, green: 160/255, blue: 165/255)
        }
    }
}
