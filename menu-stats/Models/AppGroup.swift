//
//  AppGroup.swift
//  menu-stats
//
//  Created on 2024/12/24.
//

import Foundation
import AppKit

// MARK: - Top Process Info

/// Process info parsed from top command output
struct TopProcessInfo {
    let pid: pid_t
    let command: String
    let memoryBytes: UInt64
}

// MARK: - Process Bundle Info

/// Bundle information extracted from process path
struct ProcessBundleInfo {
    let execPath: String?       // 可执行文件完整路径
    let bundlePath: String?     // .app bundle 路径
    let bundleId: String?       // Bundle Identifier
    
    /// 是否在 .app bundle 内
    var isInAppBundle: Bool {
        bundlePath != nil
    }
    
    /// 是否为 Apple 应用
    var isAppleApp: Bool {
        bundleId?.hasPrefix("com.apple.") == true
    }
    
    /// 是否为系统路径（/System/、/usr/、/sbin/、/Library/Apple/ 等）
    var isSystemPath: Bool {
        guard let path = execPath else { return false }
        return path.hasPrefix("/System/") || 
               path.hasPrefix("/usr/") ||
               path.hasPrefix("/sbin/") ||
               path.hasPrefix("/Library/Apple/")
    }
    
    /// 判断是否为系统应用
    /// 系统应用 = 系统路径 或 (/Applications/ 下的 Apple 应用)
    var isSystemApp: Bool {
        if isSystemPath {
            return true
        }
        if let path = bundlePath, path.hasPrefix("/Applications/"), isAppleApp {
            return true
        }
        return false
    }
}

// MARK: - App Group

/// Represents a merged application group (main process + child processes)
struct AppGroup: Identifiable {
    let id: pid_t  // Main process PID
    let name: String
    let icon: NSImage
    let totalMemoryBytes: UInt64
    let processCount: Int
    let allPids: [pid_t]  // All process PIDs (for termination)
    let bundleIdentifier: String?
    let bundlePath: String?       // .app bundle 路径
    let execPath: String?         // 可执行文件路径
    
    /// Display name: shows process count if multiple processes
    var displayName: String {
        processCount > 1 ? "\(name) (\(processCount))" : name
    }
    
    var memoryFormatted: String {
        ByteFormatter.format(totalMemoryBytes)
    }
    
    /// 是否为 Apple 应用
    var isAppleApp: Bool {
        bundleIdentifier?.hasPrefix("com.apple.") == true
    }
    
    /// 是否为系统路径
    var isSystemPath: Bool {
        guard let path = execPath else { return false }
        return path.hasPrefix("/System/") || 
               path.hasPrefix("/usr/") ||
               path.hasPrefix("/sbin/") ||
               path.hasPrefix("/Library/Apple/")
    }
    
    /// 是否为系统应用
    var isSystemApp: Bool {
        if isSystemPath {
            return true
        }
        if let path = bundlePath, path.hasPrefix("/Applications/"), isAppleApp {
            return true
        }
        return false
    }
}

// MARK: - Legacy Alias (for compatibility)

typealias RunningApp = AppGroup
