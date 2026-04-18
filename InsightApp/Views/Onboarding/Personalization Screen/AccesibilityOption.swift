//
//  AccesibilityOption.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 17/04/26.
//
import SwiftUI

enum AccessibilityOption: String, CaseIterable, Hashable {
    case wheelchairUser
    case limitedMobility
    case lowVision
    case hardOfHearing
    case colorBlindness
    case elderly
    
    var title: String {
        switch self {
        case .wheelchairUser:
            return "Usuario de silla de ruedas"
        case .limitedMobility:
            return "Movilidad limitada"
        case .lowVision:
            return "Baja visión"
        case .colorBlindness:
            return "Daltonismo"
        case .hardOfHearing:
            return "Dificultad auditiva"
        case .elderly:
            return "Adulto mayor"
        }
    }
    
    var icon: String {
        switch self {
        case .wheelchairUser:
            return "figure.roll"
        case .limitedMobility:
            return "figure.walk"
        case .lowVision:
            return "eye.slash"
        case .hardOfHearing:
            return "ear.badge.waveform"
        case .colorBlindness:
            return "eyedropper.halffull"
        case .elderly:
            return "figure.walk.circle"
        }
    }
}
