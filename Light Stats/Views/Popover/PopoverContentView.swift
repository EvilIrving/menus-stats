//
//  PopoverContentView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import SwiftUI

struct PopoverContentView: View {
    @State private var selectedTab: Int = 0
    @Namespace private var animation
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            HStack(spacing: 0) {
                HStack(spacing: 2) {
                    TabButton(title: "tab.overview".localized, isSelected: selectedTab == 0, namespace: animation) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedTab = 0
                        }
                    }
                    
                    TabButton(title: "tab.cleanup".localized, isSelected: selectedTab == 1, namespace: animation) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedTab = 1
                        }
                    }
                }
                .padding(3)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.03))
                )

                Spacer()

                // Settings Button
                SettingsLink {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Circle().fill(Color.primary.opacity(0.03)))
                }
                .buttonStyle(.plain)
                .help("tab.settings".localized)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Content Area
            ZStack {
                OverviewTabView()
                    .opacity(selectedTab == 0 ? 1 : 0)
                
                CleanupTabView()
                    .opacity(selectedTab == 1 ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow).ignoresSafeArea())
        .frame(width: 360, height: 520)
        .id(localization.currentLanguage) // Force refresh when language changes
    }
}

#Preview {
    PopoverContentView()
}
