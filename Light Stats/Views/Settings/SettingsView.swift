//
//  SettingsView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var showMinimumItemAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status Bar Items Card
                BentoCard(title: "状态栏显示", icon: "menubar.rectangle") {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        SettingsGridItem(title: "Logo", isOn: $settings.showLogo, icon: "applelogo") { validateMinimumItems() }
                        SettingsGridItem(title: "CPU", isOn: $settings.showCPU, icon: "cpu") { validateMinimumItems() }
                        SettingsGridItem(title: "GPU", isOn: $settings.showGPU, icon: "square.grid.2x2") { validateMinimumItems() }
                        SettingsGridItem(title: "内存", isOn: $settings.showMemory, icon: "memorychip") { validateMinimumItems() }
                        SettingsGridItem(title: "磁盘", isOn: $settings.showDisk, icon: "internaldrive") { validateMinimumItems() }
                        SettingsGridItem(title: "网络", isOn: $settings.showNetwork, icon: "network") { validateMinimumItems() }
                        SettingsGridItem(title: "风扇", isOn: $settings.showFan, icon: "fanblades") { validateMinimumItems() }
                    }
                    .padding(.vertical, 4)
                }
                
                // Refresh Rate Card
                BentoCard(title: "刷新频率", icon: "timer") {
                    Picker("", selection: $settings.refreshRate) {
                        ForEach(SettingsManager.RefreshRate.allCases, id: \.self) { rate in
                            Text(rate.displayName).tag(rate)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                
                // Units Card
                BentoCard(title: "单位设置", icon: "ruler") {
                    VStack(spacing: 16) {
                        HStack {
                            Text("温度单位")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.temperatureUnit) {
                                ForEach(SettingsManager.TemperatureUnit.allCases, id: \.self) { unit in
                                    Text(unit.displayName).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                            .labelsHidden()
                        }
                        
                        HStack {
                            Text("网速单位")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.networkSpeedUnit) {
                                ForEach(SettingsManager.NetworkSpeedUnit.allCases, id: \.self) { unit in
                                    Text(unit.displayName).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                            .labelsHidden()
                        }
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .frame(width: 380, height: 520)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow).ignoresSafeArea())
        .alert("状态栏至少需要显示一个系统状态", isPresented: $showMinimumItemAlert) {
            Button("确定", role: .cancel) {}
        }
    }
    
    private func validateMinimumItems() {
        if !settings.hasAtLeastOneItem {
            settings.ensureAtLeastOneItem()
            showMinimumItemAlert = true
        }
    }
}

// MARK: - Settings Grid Item

struct SettingsGridItem: View {
    let title: String
    @Binding var isOn: Bool
    let icon: String
    let onChange: () -> Void
    
    var body: some View {
        Button {
            isOn.toggle()
            onChange()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isOn ? .blue : .secondary)
                
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isOn ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isOn ? Color.blue.opacity(0.1) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isOn ? Color.blue.opacity(0.2) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
    
#Preview {
    SettingsView()
}
