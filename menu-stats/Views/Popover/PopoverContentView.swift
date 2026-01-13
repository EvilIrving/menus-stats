//
//  PopoverContentView.swift
//  menu-stats
//
//  Created on 2024/12/24.
//

import SwiftUI

struct PopoverContentView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            HStack(spacing: 0) {
                TabButton(title: "概览", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabButton(title: "清理释放", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }

                Spacer()

                // Settings Button - 打开独立设置窗口
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("设置")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Divider()
                .padding(.top, 8)

            // Content Area
            Group {
                if selectedTab == 0 {
                    OverviewTabView()
                } else {
                    CleanupTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 360, height: 480)
    }
}

#Preview {
    PopoverContentView()
}
