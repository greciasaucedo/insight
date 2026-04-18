//
//  SelectionCardView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 17/04/26.
//
import SwiftUI

struct SelectionCardView: View {
    
    let option: AccessibilityOption
    let isSelected: Bool
    let primaryColor: Color
    
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: option.icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(isSelected ? .white : primaryColor)
            
            Text(option.title)
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding()
        .background(isSelected ? primaryColor : Color(.secondarySystemBackground))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isSelected ? primaryColor : Color.clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    SelectionCardView(
        option: .wheelchairUser,
        isSelected: false,
        primaryColor: Color(red: 136/255, green: 205/255, blue: 212/255)
    )
    .padding()
}
