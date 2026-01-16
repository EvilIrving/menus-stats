//
//  SettingsManager.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation
import Combine

enum AppConfig {
    static let topCPUProcessCount: Int = 5
    static let topMemoryProcessCount: Int = 150
    static let appMemoryRefreshInterval: TimeInterval = 5.0
}

/// User settings for the menu stats app
protocol SettingsManaging: ObservableObject {
    var showLogo: Bool { get set }
    var showCPU: Bool { get set }
    var showGPU: Bool { get set }
    var showMemory: Bool { get set }
    var showDisk: Bool { get set }
    var showNetwork: Bool { get set }
    var showFan: Bool { get set }
    var refreshRate: SettingsManager.RefreshRate { get set }
    var temperatureUnit: SettingsManager.TemperatureUnit { get set }
    var networkSpeedUnit: SettingsManager.NetworkSpeedUnit { get set }
}

@MainActor
final class SettingsManager: ObservableObject, SettingsManaging {
    
    // MARK: - Status Bar Display Settings
    
    @Published var showLogo: Bool {
        didSet { save(showLogo, for: .showLogo) }
    }
    @Published var showCPU: Bool {
        didSet { save(showCPU, for: .showCPU) }
    }
    @Published var showGPU: Bool {
        didSet { save(showGPU, for: .showGPU) }
    }
    @Published var showMemory: Bool {
        didSet { save(showMemory, for: .showMemory) }
    }
    @Published var showDisk: Bool {
        didSet { save(showDisk, for: .showDisk) }
    }
    @Published var showNetwork: Bool {
        didSet { save(showNetwork, for: .showNetwork) }
    }
    @Published var showFan: Bool {
        didSet { save(showFan, for: .showFan) }
    }
    
    // MARK: - Other Settings
    
    @Published var refreshRate: RefreshRate {
        didSet { save(refreshRate.rawValue, for: .refreshRate) }
    }
    @Published var temperatureUnit: TemperatureUnit {
        didSet { save(temperatureUnit.rawValue, for: .temperatureUnit) }
    }
    @Published var networkSpeedUnit: NetworkSpeedUnit {
        didSet { save(networkSpeedUnit.rawValue, for: .networkSpeedUnit) }
    }
    
    @Published var appLanguage: AppLanguage {
        didSet {
            save(appLanguage.rawValue, for: .appLanguage)
            LocalizationManager.shared.setLanguage(appLanguage)
        }
    }
    
    // MARK: - Singleton
    
    static let shared = SettingsManager()
    
    // MARK: - Enums
    
    enum RefreshRate: String, CaseIterable {
        case low = "low"       // 5 seconds
        case medium = "medium" // 2 seconds
        case high = "high"     // 1 second
        
        var interval: TimeInterval {
            switch self {
            case .low: return 5.0
            case .medium: return 2.0
            case .high: return 1.0
            }
        }
        
        var displayName: String {
            switch self {
            case .low: return "refreshRate.low".localized
            case .medium: return "refreshRate.medium".localized
            case .high: return "refreshRate.high".localized
            }
        }
    }
    
    enum TemperatureUnit: String, CaseIterable {
        case celsius = "celsius"
        case fahrenheit = "fahrenheit"
        
        var displayName: String {
            switch self {
            case .celsius: return "°C"
            case .fahrenheit: return "°F"
            }
        }
        
        func format(_ celsius: Double) -> String {
            switch self {
            case .celsius:
                return String(format: "%.0f°C", celsius)
            case .fahrenheit:
                let fahrenheit = celsius * 9 / 5 + 32
                return String(format: "%.0f°F", fahrenheit)
            }
        }
    }
    
    enum NetworkSpeedUnit: String, CaseIterable {
        case auto = "auto"
        case kbps = "kbps"
        case mbps = "mbps"
        
        var displayName: String {
            switch self {
            case .auto: return "networkSpeed.auto".localized
            case .kbps: return "KB/s"
            case .mbps: return "MB/s"
            }
        }
        
        func format(_ bytesPerSecond: Double) -> String {
            switch self {
            case .auto:
                return ByteFormatter.formatSpeed(bytesPerSecond)
            case .kbps:
                return String(format: "%.1f KB/s", bytesPerSecond / 1_000)
            case .mbps:
                return String(format: "%.2f MB/s", bytesPerSecond / 1_000_000)
            }
        }
    }
    
    // MARK: - Keys
    
    private enum Key: String {
        case showLogo = "settings.showLogo"
        case showCPU = "settings.showCPU"
        case showGPU = "settings.showGPU"
        case showMemory = "settings.showMemory"
        case showDisk = "settings.showDisk"
        case showNetwork = "settings.showNetwork"
        case showFan = "settings.showFan"
        case refreshRate = "settings.refreshRate"
        case temperatureUnit = "settings.temperatureUnit"
        case networkSpeedUnit = "settings.networkSpeedUnit"
        case appLanguage = "settings.appLanguage"
    }
    
    // MARK: - Init
    
    private init() {
        let defaults = UserDefaults.standard
        
        // Status bar items - default all to true except disk/fan
        showLogo = defaults.object(forKey: Key.showLogo.rawValue) as? Bool ?? true
        showCPU = defaults.object(forKey: Key.showCPU.rawValue) as? Bool ?? true
        showGPU = defaults.object(forKey: Key.showGPU.rawValue) as? Bool ?? true
        showMemory = defaults.object(forKey: Key.showMemory.rawValue) as? Bool ?? true
        showDisk = defaults.object(forKey: Key.showDisk.rawValue) as? Bool ?? false
        showNetwork = defaults.object(forKey: Key.showNetwork.rawValue) as? Bool ?? false
        showFan = defaults.object(forKey: Key.showFan.rawValue) as? Bool ?? false
        
        // Other settings
        let refreshRateStr = defaults.string(forKey: Key.refreshRate.rawValue) ?? RefreshRate.medium.rawValue
        refreshRate = RefreshRate(rawValue: refreshRateStr) ?? .medium
        
        let tempUnitStr = defaults.string(forKey: Key.temperatureUnit.rawValue) ?? TemperatureUnit.celsius.rawValue
        temperatureUnit = TemperatureUnit(rawValue: tempUnitStr) ?? .celsius
        
        let netUnitStr = defaults.string(forKey: Key.networkSpeedUnit.rawValue) ?? NetworkSpeedUnit.auto.rawValue
        networkSpeedUnit = NetworkSpeedUnit(rawValue: netUnitStr) ?? .auto
        
        let langStr = defaults.string(forKey: Key.appLanguage.rawValue) ?? AppLanguage.system.rawValue
        appLanguage = AppLanguage(rawValue: langStr) ?? .system
    }
    
    // MARK: - Validation
    
    /// Returns true if at least one status bar item is enabled
    var hasAtLeastOneItem: Bool {
        showLogo || showCPU || showGPU || showMemory || showDisk || showNetwork || showFan
    }
    
    /// Ensures at least one item is shown; if all are off, enable CPU
    func ensureAtLeastOneItem() {
        if !hasAtLeastOneItem {
            showCPU = true
        }
    }
    
    // MARK: - Private
    
    private func save<T>(_ value: T, for key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
        // 延迟执行以避免在视图更新过程中修改状态
        Task { @MainActor in
            ensureAtLeastOneItem()
        }
    }
}
