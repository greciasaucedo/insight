//
//  WelcomeView.swift
//  InsightApp
//
//  Created by Grecia Saucedo on 17/04/26.
//

import SwiftUI

struct WelcomeView : View {
        
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(spacing: 20) {
            
            Spacer()
            
            //Logo
            Image("insight_logo")
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
            
            //Title
            Text("Insight")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            //Subtitle
            Text("Mapa que se adapta a ti")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            NavigationLink(destination: PurposeView()) {
                Text("Empezar")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.primaryColor)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    NavigationStack {
        WelcomeView()
    }
}
