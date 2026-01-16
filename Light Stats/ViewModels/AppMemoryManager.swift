//
//  AppMemoryManager.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation
import AppKit
import Combine

// MARK: - App Memory Manager

/// Manages user application information and memory usage
@MainActor
final class AppMemoryManager: ObservableObject {
    
    @Published var runningApps: [AppGroup] = []
    @Published var totalMemoryUsed: UInt64 = 0
    @Published var totalMemory: UInt64 = 0
    @Published var appCount: Int = 0
    
    // Detailed memory info
    @Published var detailedMemory: MemoryInfo.DetailedInfo?
    @Published var memoryPressure: MemoryPressureLevel = .normal
    
    private var timer: Timer?
    
    static let shared = AppMemoryManager()
    
    /// Cache of known user app bundle identifiers for WebKit process attribution
    private var knownAppBundleIds: Set<String> = []
    
    /// ProcessService 实例
    private let processService: ProcessServiceProtocol
    
    /// 默认图标（缓存）
    private lazy var defaultAppIcon: NSImage = {
        NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }()
    
    private lazy var defaultGearIcon: NSImage = {
        NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) ?? NSImage()
    }()
    
    private init(processService: ProcessServiceProtocol = ProcessService.shared) {
        self.processService = processService
        totalMemory = ProcessInfo.processInfo.physicalMemory
    }
    
    func startMonitoring(interval: TimeInterval = AppConfig.appMemoryRefreshInterval) {
        stopMonitoring()
        
        // Initial update
        Task {
            await updateRunningApps()
        }
        
        // Periodic updates
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateRunningApps()
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func updateRunningApps() async {
        // Step 1: Get top N memory-consuming processes using top command
        let topProcesses = await processService.getTopMemoryProcesses(count: AppConfig.topMemoryProcessCount)
        
        // Step 2: Get running GUI apps for icons and bundle identifiers
        let workspace = NSWorkspace.shared
        let guiApps = workspace.runningApplications
        
        // Build lookup maps for GUI apps
        var guiAppByPid: [pid_t: NSRunningApplication] = [:]
        var guiAppByBundleId: [String: NSRunningApplication] = [:]
        knownAppBundleIds.removeAll()
        
        for app in guiApps {
            guard app.activationPolicy == .regular || app.activationPolicy == .accessory else { continue }
            guiAppByPid[app.processIdentifier] = app
            if let bundleId = app.bundleIdentifier {
                knownAppBundleIds.insert(bundleId)
                if guiAppByBundleId[bundleId] == nil {
                    guiAppByBundleId[bundleId] = app
                }
            }
        }
        
        // Step 3: Group processes by responsible PID
        var groupedByResponsible: [pid_t: [TopProcessInfo]] = [:]
        var pidToBundleInfo: [pid_t: ProcessBundleInfo] = [:]
        
        for process in topProcesses {
            let responsiblePid = responsibility_get_pid_responsible_for_pid(process.pid)
            // Use the responsible PID, fallback to self if 0
            let groupPid = responsiblePid > 0 ? responsiblePid : process.pid
            groupedByResponsible[groupPid, default: []].append(process)
            
            // Cache bundle info for each process
            if pidToBundleInfo[process.pid] == nil {
                pidToBundleInfo[process.pid] = processService.getBundleInfo(for: process.pid)
            }
        }
        
        // Step 4: Build initial app groups (keyed by responsible PID)
        var initialGroups: [pid_t: (processes: [TopProcessInfo], bundleInfo: ProcessBundleInfo)] = [:]
        
        for (responsiblePid, processes) in groupedByResponsible {
            let bundleInfo = processService.getBundleInfo(for: responsiblePid)
            initialGroups[responsiblePid] = (processes: processes, bundleInfo: bundleInfo)
        }
        
        // Step 5: Merge groups by BundleID (for multi-process apps like Electron)
        var mergedByBundleId: [String: (mainPid: pid_t, processes: [TopProcessInfo], bundleInfo: ProcessBundleInfo)] = [:]
        var ungroupedGroups: [(pid: pid_t, processes: [TopProcessInfo], bundleInfo: ProcessBundleInfo)] = []
        
        for (responsiblePid, data) in initialGroups {
            // Try to get bundleId from the group's processes
            var effectiveBundleId: String? = data.bundleInfo.bundleId
            
            // If responsible process has no bundleId, check its processes
            if effectiveBundleId == nil {
                for process in data.processes {
                    if let info = pidToBundleInfo[process.pid], let bid = info.bundleId {
                        effectiveBundleId = bid
                        break
                    }
                }
            }
            
            if let bundleId = effectiveBundleId, !bundleId.isEmpty {
                if var existing = mergedByBundleId[bundleId] {
                    // Merge into existing group
                    existing.processes.append(contentsOf: data.processes)
                    // Keep the main PID with higher memory usage
                    let existingMemory = existing.processes.filter { $0.pid == existing.mainPid }.first?.memoryBytes ?? 0
                    let newMemory = data.processes.reduce(0) { $0 + $1.memoryBytes }
                    if newMemory > existingMemory {
                        existing.mainPid = responsiblePid
                        existing.bundleInfo = data.bundleInfo
                    }
                    mergedByBundleId[bundleId] = existing
                } else {
                    mergedByBundleId[bundleId] = (mainPid: responsiblePid, processes: data.processes, bundleInfo: data.bundleInfo)
                }
            } else {
                ungroupedGroups.append((pid: responsiblePid, processes: data.processes, bundleInfo: data.bundleInfo))
            }
        }
        
        // Step 6: Build final app groups
        var appGroups: [AppGroup] = []
        
        // Process merged groups (by BundleID)
        for (bundleId, data) in mergedByBundleId {
            let bundleInfo = data.bundleInfo
            
            // 过滤规则
            if !shouldShowProcess(bundleInfo) {
                continue
            }
            
            let totalMemory = data.processes.reduce(0) { $0 + $1.memoryBytes }
            let allPids = data.processes.map { $0.pid }
            
            let guiApp = guiAppByBundleId[bundleId] ?? guiAppByPid[data.mainPid]
            let name: String
            let icon: NSImage
            let bundlePath: String?
            let execPath: String?
            
            if let app = guiApp {
                name = app.localizedName ?? data.processes.first?.command ?? "Unknown"
                icon = app.icon ?? defaultAppIcon
                bundlePath = app.bundleURL?.path ?? bundleInfo.bundlePath
                execPath = app.executableURL?.path ?? bundleInfo.execPath
            } else {
                name = processService.getProcessName(for: data.mainPid) ?? data.processes.first?.command ?? "Unknown"
                icon = defaultGearIcon
                bundlePath = bundleInfo.bundlePath
                execPath = bundleInfo.execPath
            }
            
            let group = AppGroup(
                id: data.mainPid,
                name: name,
                icon: icon,
                totalMemoryBytes: totalMemory,
                processCount: data.processes.count,
                allPids: allPids,
                bundleIdentifier: bundleId,
                bundlePath: bundlePath,
                execPath: execPath
            )
            appGroups.append(group)
        }
        
        // Process ungrouped groups (no BundleID)
        for data in ungroupedGroups {
            let bundleInfo = data.bundleInfo
            
            if !shouldShowProcess(bundleInfo) {
                continue
            }
            
            let totalMemory = data.processes.reduce(0) { $0 + $1.memoryBytes }
            let allPids = data.processes.map { $0.pid }
            
            let guiApp = guiAppByPid[data.pid]
            let name: String
            let icon: NSImage
            let bundleId: String?
            let bundlePath: String?
            let execPath: String?
            
            if let app = guiApp {
                name = app.localizedName ?? data.processes.first?.command ?? "Unknown"
                icon = app.icon ?? defaultAppIcon
                bundleId = app.bundleIdentifier ?? bundleInfo.bundleId
                bundlePath = app.bundleURL?.path ?? bundleInfo.bundlePath
                execPath = app.executableURL?.path ?? bundleInfo.execPath
            } else {
                name = processService.getProcessName(for: data.pid) ?? data.processes.first?.command ?? "Unknown"
                icon = defaultGearIcon
                bundleId = bundleInfo.bundleId
                bundlePath = bundleInfo.bundlePath
                execPath = bundleInfo.execPath
            }
            
            let group = AppGroup(
                id: data.pid,
                name: name,
                icon: icon,
                totalMemoryBytes: totalMemory,
                processCount: data.processes.count,
                allPids: allPids,
                bundleIdentifier: bundleId,
                bundlePath: bundlePath,
                execPath: execPath
            )
            appGroups.append(group)
        }
        
        // Step 7: Sort by total memory usage (descending)
        let sortedGroups = appGroups.sorted { $0.totalMemoryBytes > $1.totalMemoryBytes }
        
        runningApps = sortedGroups
        appCount = sortedGroups.count
        
        // Update detailed memory info
        let detailedInfo = MemoryInfo.getDetailedMemoryInfo()
        detailedMemory = detailedInfo
        totalMemoryUsed = detailedInfo.used
        memoryPressure = detailedInfo.pressureLevel
    }
    
    // MARK: - App Control
    
    /// Trigger system memory cleanup
    func triggerMemoryCleanup() async {
        await processService.triggerMemoryCleanup()
        await updateRunningApps()
    }
    
    /// Terminate an app group
    func terminateApp(_ app: AppGroup) -> Bool {
        processService.terminateApp(app)
    }
    
    /// Force terminate an app group
    func forceTerminateApp(_ app: AppGroup) -> Bool {
        processService.forceTerminateApp(app)
    }
}

