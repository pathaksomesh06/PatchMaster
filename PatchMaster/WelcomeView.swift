//
//  WelcomeView.swift
//  PatchMaster
//
//  Created by Somesh Pathak on 03/01/2026.
//

import SwiftUI

struct WelcomeView: View {
    @State private var showMainUI = false
    
    var body: some View {
        if showMainUI {
            ContentView()
        } else {
            ZStack {
                // Gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.2, blue: 0.4),
                        Color(red: 0.15, green: 0.35, blue: 0.6)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    // Icon with shadow
                    Image(systemName: "gearshape.circle.fill")
                        .font(.system(size: 120))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.8, green: 0.6, blue: 0.2),
                                    Color(red: 1.0, green: 0.7, blue: 0.3)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    // Title & Subtitle
                    VStack(spacing: 16) {
                        Text("PatchMaster")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Keep Your Apps Updated")
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("Automatically discover and install app updates")
                            .font(.system(size: 16, design: .default))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    
                    Spacer()
                    
                    // Get Started Button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showMainUI = true
                        }
                    }) {
                        Text("Get Started")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.3, green: 0.6, blue: 1.0),
                                        Color(red: 0.1, green: 0.5, blue: 0.9)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: Color.blue.opacity(0.4), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 60)
                }
            }
        }
    }
}

#Preview {
    WelcomeView()
}
