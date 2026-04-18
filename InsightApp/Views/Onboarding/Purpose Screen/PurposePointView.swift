//
//  PurposePointView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 17/04/26.
//
import SwiftUI

struct PurposePointView: View {

    let icon: String
    let text: String
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 30)
                .foregroundStyle(Color(red: 136/255, green: 205/255, blue: 212/255))

            Text(text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(18)
    }
}
