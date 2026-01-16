//
//  SettingsView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var showMinimumItemAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status Bar Items Card
                BentoCard(title: "settings.statusBar".localized, icon: "menubar.rectangle") {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        SettingsGridItem(title: "settings.logo".localized, isOn: $settings.showLogo, icon: "applelogo") { validateMinimumItems() }
                        SettingsGridItem(title: "settings.cpu".localized, isOn: $settings.showCPU, icon: "cpu") { validateMinimumItems() }
                        SettingsGridItem(title: "settings.gpu".localized, isOn: $settings.showGPU, icon: "square.grid.2x2") { validateMinimumItems() }
                        SettingsGridItem(title: "settings.memory".localized, isOn: $settings.showMemory, icon: "memorychip") { validateMinimumItems() }
                        SettingsGridItem(title: "settings.disk".localized, isOn: $settings.showDisk, icon: "internaldrive") { validateMinimumItems() }
                        SettingsGridItem(title: "settings.network".localized, isOn: $settings.showNetwork, icon: "network") { validateMinimumItems() }
                        SettingsGridItem(title: "settings.fan".localized, isOn: $settings.showFan, icon: "fanblades") { validateMinimumItems() }
                    }
                    .padding(.vertical, 4)
                }
                
                // Language Card
                BentoCard(title: "settings.language".localized, icon: "globe") {
                    Picker("", selection: $settings.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                
                // Refresh Rate Card
                BentoCard(title: "settings.refreshRate".localized, icon: "timer") {
                    Picker("", selection: $settings.refreshRate) {
                        ForEach(SettingsManager.RefreshRate.allCases, id: \.self) { rate in
                            Text(rate.displayName).tag(rate)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                
                // Units Card
                BentoCard(title: "settings.units".localized, icon: "ruler") {
                    VStack(spacing: 16) {
                        HStack {
                            Text("settings.temperatureUnit".localized)
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
                            Text("settings.networkSpeedUnit".localized)
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
        .alert("settings.minimumItemAlert".localized, isPresented: $showMinimumItemAlert) {
            Button("settings.ok".localized, role: .cancel) {}
        }
        .id(localization.currentLanguage) // Force refresh when language changes
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
