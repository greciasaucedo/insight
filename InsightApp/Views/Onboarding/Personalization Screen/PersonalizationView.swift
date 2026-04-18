//
//  PersonalizationView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 17/04/26.
//
import SwiftUI

struct PersonalizationView: View {
    
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var selectedOptions: Set<AccessibilityOption> = []
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            
            Spacer()
                .frame(height: 20)
            
            VStack(spacing: 12) {
                Text("Personalicemos tu experiencia")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                Text("Selecciona las opciones que mejor describan tus necesidades o la forma en que te mueves por la ciudad.")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(AccessibilityOption.allCases, id: \.self) { option in
                        SelectionCardView(
                            option: option,
                            isSelected: selectedOptions.contains(option),
                            primaryColor: themeManager.primaryColor
                        )
                        .onTapGesture {
                            toggleSelection(for: option)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            
            NavigationLink(destination: AllowsView()){
                Text("Continuar")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.primaryColor)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
    }
    
    private func toggleSelection(for option: AccessibilityOption) {
        if selectedOptions.contains(option) {
            selectedOptions.remove(option)
        } else {
            selectedOptions.insert(option)
        }
    }
}

#Preview {
    PersonalizationView()
}
