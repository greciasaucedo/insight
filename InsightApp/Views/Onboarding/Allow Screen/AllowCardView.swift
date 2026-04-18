//
//  AllowCardView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 18/04/26.
//
import SwiftUI

struct AllowCardView: View {
    
    let icon: String
    let title: String
    let description: String
    
    let primaryColor = Color(red: 136/255, green: 205/255, blue: 212/255)
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(primaryColor)
                .frame(width: 34)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                
                Text(description)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(18)
    }
}
