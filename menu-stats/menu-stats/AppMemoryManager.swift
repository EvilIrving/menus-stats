//
//  AppMemoryManager.swift
//  menu-stats
//
//  Created on 2024/12/24.
//

import Foundation
import AppKit
import Combine

// MARK: - Process Info (Internal)

/// Internal structure for single process information
struct AppProcessInfo {
    let pid: pid_t
    let ppid: pid_t
    let name: String
    let icon: NSImage
    let memoryBytes: UInt64
    let bundleIdentifier: String?
    let isMainProcess: Bool  // Whether this is the main UI process
}

// MARK: - App Group (Public)

/// Represents a merged application group (main process + child processes)
struct AppGroup: Identifiable {
    let id: pid_t  // Main process PID
    let name: String
    let icon: NSImage
    let totalMemoryBytes: UInt64
    let processCount: Int
    let allPids: [pid_t]  // All process PIDs (for termination)
    let bundleIdentifier: String?
    
    /// Display name: shows process count if multiple processes
    var displayName: String {
        processCount > 1 ? "\(name) (\(processCount))" : name
    }
    
    var memoryFormatted: String {
        ByteFormatter.format(totalMemoryBytes)
    }
}

// MARK: - Legacy Alias (for compatibility)

typealias RunningApp = AppGroup

// MARK: - App Memory Manager

/// Manages user application information and memory usage
@MainActor
final class AppMemoryManager: ObservableObject {
    
    @Published var runningApps: [AppGroup] = []
    @Published var totalMemoryUsed: UInt64 = 0
    @Published var totalMemory: UInt64 = 0
    @Published var appCount: Int = 0
    
    private var timer: Timer?
    
    static let shared = AppMemoryManager()
    
    /// Cache of known user app bundle identifiers for WebKit process attribution
    private var knownAppBundleIds: Set<String> = []
    
    private init() {
        totalMemory = ProcessInfo.processInfo.physicalMemory
    }
    
    func startMonitoring(interval: TimeInterval = 3.0) {
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
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
        
        // Step 1: Collect all user app processes (regular + accessory)
        var mainProcesses: [pid_t: AppProcessInfo] = [:]
        knownAppBundleIds.removeAll()
        
        for app in apps {
            // Include regular apps and status bar apps
            guard app.activationPolicy == .regular else { continue }
            guard let name = app.localizedName else { continue }
            
            let pid = app.processIdentifier
            let ppid = getParentPid(for: pid)
            let memory = getMemoryUsage(for: pid)
            let icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
            
            if let bundleId = app.bundleIdentifier {
                knownAppBundleIds.insert(bundleId)
            }
            
            let processInfo = AppProcessInfo(
                pid: pid,
                ppid: ppid,
                name: name,
                icon: icon,
                memoryBytes: memory,
                bundleIdentifier: app.bundleIdentifier,
                isMainProcess: true
            )
            mainProcesses[pid] = processInfo
        }
        
        // Step 2: Find child processes and build process tree
        let childProcesses = findChildProcesses(mainProcessPids: Set(mainProcesses.keys))
        
        // Step 3: Merge processes into app groups
        let appGroups = mergeProcessesIntoGroups(mainProcesses: mainProcesses, childProcesses: childProcesses)
        
        // Step 4: Sort by total memory usage (descending)
        let sortedGroups = appGroups.sorted { $0.totalMemoryBytes > $1.totalMemoryBytes }
        
        runningApps = sortedGroups
        appCount = sortedGroups.count
        
        // Update total memory info
        let memInfo = MemoryInfo.getMemoryInfo()
        totalMemoryUsed = memInfo.used
    }
    
    // MARK: - Process Tree Building
    
    /// Find all child processes that belong to main user app processes
    private func findChildProcesses(mainProcessPids: Set<pid_t>) -> [pid_t: [AppProcessInfo]] {
        var childrenByParent: [pid_t: [AppProcessInfo]] = [:]
        
        // Get all system processes
        let allPids = getAllProcessIds()
        
        for pid in allPids {
            let ppid = getParentPid(for: pid)
            
            // Skip if parent is launchd (pid 1) or not a known main process
            guard ppid != 1 else { continue }
            
            // Find the root user app for this process
            if let rootPid = findRootUserProcess(for: pid, mainProcessPids: mainProcessPids) {
                // Don't add the main process itself as a child
                guard pid != rootPid else { continue }
                
                let memory = getMemoryUsage(for: pid)
                let name = getProcessName(for: pid) ?? "Unknown"
                
                let childInfo = AppProcessInfo(
                    pid: pid,
                    ppid: ppid,
                    name: name,
                    icon: NSImage(),
                    memoryBytes: memory,
                    bundleIdentifier: nil,
                    isMainProcess: false
                )
                
                childrenByParent[rootPid, default: []].append(childInfo)
            }
        }
        
        return childrenByParent
    }
    
    /// Find the root user app process for a given pid by traversing up the process tree
    private func findRootUserProcess(for pid: pid_t, mainProcessPids: Set<pid_t>) -> pid_t? {
        var currentPid = pid
        var visited = Set<pid_t>()
        
        while currentPid > 1 && !visited.contains(currentPid) {
            visited.insert(currentPid)
            
            if mainProcessPids.contains(currentPid) {
                return currentPid
            }
            
            let ppid = getParentPid(for: currentPid)
            if ppid == currentPid || ppid <= 1 {
                break
            }
            currentPid = ppid
        }
        
        return nil
    }
    
    /// Merge main processes and their children into app groups
    private func mergeProcessesIntoGroups(
        mainProcesses: [pid_t: AppProcessInfo],
        childProcesses: [pid_t: [AppProcessInfo]]
    ) -> [AppGroup] {
        var groups: [AppGroup] = []
        
        for (pid, mainProcess) in mainProcesses {
            let children = childProcesses[pid] ?? []
            
            // Calculate total memory
            let totalMemory = mainProcess.memoryBytes + children.reduce(0) { $0 + $1.memoryBytes }
            
            // Collect all PIDs
            var allPids = [pid]
            allPids.append(contentsOf: children.map { $0.pid })
            
            let group = AppGroup(
                id: pid,
                name: mainProcess.name,
                icon: mainProcess.icon,
                totalMemoryBytes: totalMemory,
                processCount: allPids.count,
                allPids: allPids,
                bundleIdentifier: mainProcess.bundleIdentifier
            )
            groups.append(group)
        }
        
        return groups
    }
    
    // MARK: - App Control
    
    /// Terminate an app group (handles single and multi-process apps)
    func terminateApp(_ app: AppGroup) -> Bool {
        // Single process: direct terminate
        if app.processCount == 1 {
            guard let nsApp = NSRunningApplication(processIdentifier: app.id) else {
                return false
            }
            return nsApp.terminate()
        }
        
        // Multi-process: terminate main process first
        guard let mainApp = NSRunningApplication(processIdentifier: app.id) else {
            return false
        }
        
        let mainTerminated = mainApp.terminate()
        
        if mainTerminated {
            // Wait briefly then check for surviving child processes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.terminateSurvivingChildren(app.allPids)
            }
        }
        
        return mainTerminated
    }
    
    /// Terminate any surviving child processes
    private func terminateSurvivingChildren(_ pids: [pid_t]) {
        for pid in pids {
            // Check if process still exists
            if kill(pid, 0) == 0 {
                // Process still alive, try to terminate via NSRunningApplication
                if let app = NSRunningApplication(processIdentifier: pid) {
                    _ = app.terminate()
                } else {
                    // Not an NSRunningApplication, use SIGTERM
                    kill(pid, SIGTERM)
                }
            }
        }
    }
    
    /// Force terminate an app group (all processes)
    func forceTerminateApp(_ app: AppGroup) -> Bool {
        var allSucceeded = true
        
        // Force terminate main process first
        if let mainApp = NSRunningApplication(processIdentifier: app.id) {
            if !mainApp.forceTerminate() {
                allSucceeded = false
            }
        } else {
            // Use SIGKILL directly
            if kill(app.id, SIGKILL) != 0 {
                allSucceeded = false
            }
        }
        
        // Force terminate all child processes
        for pid in app.allPids where pid != app.id {
            if let childApp = NSRunningApplication(processIdentifier: pid) {
                if !childApp.forceTerminate() {
                    allSucceeded = false
                }
            } else {
                // Use SIGKILL for non-app processes
                if kill(pid, SIGKILL) != 0 {
                    allSucceeded = false
                }
            }
        }
        
        return allSucceeded
    }
    
    // MARK: - Private - Memory Usage
    
    private func getMemoryUsage(for pid: pid_t) -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        var task: mach_port_t = 0
        let result = task_for_pid(mach_task_self_, pid, &task)
        
        guard result == KERN_SUCCESS else {
            // Fallback: use proc_pidinfo
            return getMemoryUsageFallback(for: pid)
        }
        
        defer {
            mach_port_deallocate(mach_task_self_, task)
        }
        
        let infoResult = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(task, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard infoResult == KERN_SUCCESS else {
            return getMemoryUsageFallback(for: pid)
        }
        
        return UInt64(info.resident_size)
    }
    
    private func getMemoryUsageFallback(for pid: pid_t) -> UInt64 {
        var taskInfo = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size)
        
        if result > 0 {
            return taskInfo.pti_resident_size
        }
        
        return 0
    }
    
    // MARK: - Private - Process Tree
    
    /// Get parent process ID using sysctl
    private func getParentPid(for pid: pid_t) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        
        if result == 0 && size > 0 {
            return info.kp_eproc.e_ppid
        }
        
        return 1  // Default to launchd if unable to get ppid
    }
    
    /// Get all process IDs in the system
    private func getAllProcessIds() -> [pid_t] {
        // First call to get the count
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        
        // Allocate buffer and get PIDs
        var pids = [pid_t](repeating: 0, count: Int(count))
        count = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * Int(count)))
        
        guard count > 0 else { return [] }
        
        return Array(pids.prefix(Int(count))).filter { $0 > 0 }
    }
    
    /// Get process name for a given PID
    private func getProcessName(for pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        
        if pathLength > 0 {
            let path = String(cString: pathBuffer)
            return (path as NSString).lastPathComponent
        }
        
        // Fallback: try to get name from kinfo_proc
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        
        if sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 && size > 0 {
            let name = withUnsafePointer(to: &info.kp_proc.p_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                    String(cString: $0)
                }
            }
            if !name.isEmpty {
                return name
            }
        }
        
        return nil
    }
}

// Import for proc_pidinfo and other system calls
import Darwin
