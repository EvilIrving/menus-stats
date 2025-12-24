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
        // Empty Settings scene - required for menu bar only apps
        Settings {
            EmptyView()
        }
    }
}
