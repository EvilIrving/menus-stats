//
//  SettingsView.swift
//  menu-stats
//
//  Created on 2024/12/24.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var showMinimumItemAlert = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Status Bar Items
                statusBarSection
                
                Divider()
                
                // Other Settings
                otherSettingsSection
            }
            .padding()
        }
        .frame(width: 360, height: 480)
        .alert("状态栏至少需要显示一个系统状态", isPresented: $showMinimumItemAlert) {
            Button("确定", role: .cancel) {}
        }
    }
    
    // MARK: - Status Bar Section
    
    private var statusBarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("状态栏显示")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                SettingsToggle(title: "Logo", isOn: $settings.showLogo) {
                    validateMinimumItems()
                }
                SettingsToggle(title: "CPU", isOn: $settings.showCPU) {
                    validateMinimumItems()
                }
                SettingsToggle(title: "GPU", isOn: $settings.showGPU) {
                    validateMinimumItems()
                }
                SettingsToggle(title: "内存 (MEM)", isOn: $settings.showMemory) {
                    validateMinimumItems()
                }
                SettingsToggle(title: "磁盘 (DISK)", isOn: $settings.showDisk) {
                    validateMinimumItems()
                }
                SettingsToggle(title: "网络 (NET)", isOn: $settings.showNetwork) {
                    validateMinimumItems()
                }
                SettingsToggle(title: "风扇 (FAN)", isOn: $settings.showFan) {
                    validateMinimumItems()
                }
            }
        }
    }
    
    // MARK: - Other Settings Section
    
    private var otherSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("其他设置")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            // Refresh Rate
            VStack(alignment: .leading, spacing: 8) {
                Text("刷新频率")
                    .font(.system(size: 13))
                
                Picker("", selection: $settings.refreshRate) {
                    ForEach(SettingsManager.RefreshRate.allCases, id: \.self) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            
            // Temperature Unit
            VStack(alignment: .leading, spacing: 8) {
                Text("温度单位")
                    .font(.system(size: 13))
                
                Picker("", selection: $settings.temperatureUnit) {
                    ForEach(SettingsManager.TemperatureUnit.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            
            // Network Speed Unit
            VStack(alignment: .leading, spacing: 8) {
                Text("网速单位")
                    .font(.system(size: 13))
                
                Picker("", selection: $settings.networkSpeedUnit) {
                    ForEach(SettingsManager.NetworkSpeedUnit.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
    
    // MARK: - Validation
    
    private func validateMinimumItems() {
        if !settings.hasAtLeastOneItem {
            settings.ensureAtLeastOneItem()
            showMinimumItemAlert = true
        }
    }
}

// MARK: - Settings Toggle

struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool
    let onChange: () -> Void
    
    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 13))
        }
        .toggleStyle(.checkbox)
        .onChange(of: isOn) { _, _ in
            onChange()
        }
    }
}

#Preview {
    SettingsView()
}
