//
//  menu_statsApp.swift
//  menu-stats
//
//  Created by Cain on 2025/12/24.
//

import SwiftUI

@main
struct MenuStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()  // macOS 自动处理窗口生命周期
        }
    }
}
